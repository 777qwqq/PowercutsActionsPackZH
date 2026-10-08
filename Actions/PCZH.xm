#include <dlfcn.h>
// PCZH Hook v0.4.1 — 运行时枚举 PCAction 子类逐类替换显示方法
// 官方动作对象的 name/description/parameters/summary 全部按 identifier 映射为中文
#import "pczh_api.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>

#pragma mark - 映射表

static NSDictionary *g_tr;   // identifier → {name, desc, summary}
static NSDictionary *g_lab;  // 参数 Label/Placeholder 英文 → 中文
static NSDictionary *g_setMap = nil;

static NSString *ZHMap(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return nil;
    NSString *m = g_setMap[s];
    if (m) return m;
    if ([s length] > 40) {
        if ([s hasPrefix:@"- Disable Automation notifications:"])
            return @"- 关闭自动化通知：自动化运行时不再弹通知\n- 自动化无需确认：所有触发器（邮件和信息除外）运行自动化时无需手动确认\n- 允许以文件方式导入/导出快捷指令：改为导入/导出 .shortcuts 或 .wflow 文件而非 iCloud 链接\n- 敏感动作无需解锁验证：部分动作不再要求解锁手机（在锁屏自动化的场景有用，并非对所有敏感动作生效）\n- 隐藏顶部进度横幅：从主屏幕图标、辅助触控等运行快捷指令时，不再显示顶部进度横幅";
        if ([s hasPrefix:@"Powercuts is a library"])
            return @"Powercuts 是一个为 iOS「快捷指令」提供的动作库，让你能在快捷指令和个人自动化中使用新的动作。安装后请在包管理器里搜索 \"Powercuts\" 安装动作包，之后在快捷指令编辑器的「App > Powercuts」中就能找到这些动作。";
    }
    return nil;
}
static IMP g_origSpecName = NULL, g_origSpecProp = NULL;
static NSString *ZH_specname_imp(id self, SEL _cmd) {
    @try {
        NSString *o = ((NSString *(*)(id, SEL))g_origSpecName)(self, _cmd);
        NSString *m = ZHMap(o);
        return m ?: o;
    } @catch (id e) { return ((NSString *(*)(id, SEL))g_origSpecName)(self, _cmd); }
}
static id ZH_specprop_imp(id self, SEL _cmd, NSString *key) {
    @try {
        id v = ((id(*)(id, SEL, id))g_origSpecProp)(self, _cmd, key);
        if ([v isKindOfClass:[NSString class]]) {
            NSString *m = ZHMap(v);
            if (m) return m;
        }
        return v;
    } @catch (id e) { return ((id(*)(id, SEL, id))g_origSpecProp)(self, _cmd, key); }
}

static NSDictionary *ZHTr(NSString *ident) {
    if (![ident isKindOfClass:[NSString class]]) return nil;
    NSDictionary *t = g_tr[ident];
    if (t) return t;
    if ([ident hasPrefix:@"com.anthopak.powercuts.action."]) return g_tr[[ident substringFromIndex:30]];
    return nil;
}

static void PCZHInitTables(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 1.0.2：路径统一 /var/jb（roothide/Dopamine 通用符号链接），不再 dladdr
        NSData *jd = [NSData dataWithContentsOfFile:@"/var/jb/usr/share/pczh/table.json"];
        NSDictionary *root = jd ? [NSJSONSerialization JSONObjectWithData:jd options:0 error:nil] : nil;
        if (root) {
            g_tr = root[@"tr"] ?: @{};
            g_lab = root[@"lab"] ?: @{};
            g_setMap = root[@"settings"] ?: @{};
        } else {
            g_tr = @{}; g_lab = @{}; g_setMap = @{};
        }
    });
}

#pragma mark - 原始 IMP 保存

static NSMutableDictionary *g_origs;  // "类名|方法类型" → NSValue(IMP)

static NSDictionary *PCZHL10N(NSDictionary *orig) {
    if (!orig || !orig.count) return orig;
    NSMutableDictionary *out = [orig mutableCopy];
    for (NSString *ident in out.allKeys) {
        NSString *shortIdent = [ident hasPrefix:@"com.anthopak.powercuts.action."]
            ? [ident substringFromIndex:@"com.anthopak.powercuts.action.".length] : ident;
        NSDictionary *tr = ZHTr(ident);
        if (!tr) continue;
        NSMutableDictionary *def = [out[ident] mutableCopy];
        if (!def) continue;
        id nm = tr[@"n"];   if (nm) def[@"name"] = nm;
        id ds = tr[@"d"];   if (ds) def[@"descriptionSummary"] = ds;
        id sm = tr[@"s"];   if (sm && [(NSString *)sm length]) def[@"parameterSummary"] = sm;
        id params = def[@"parameters"];
        if ([params isKindOfClass:[NSArray class]]) {
            NSMutableArray *np = [NSMutableArray array];
            for (id p in params) {
                if ([p isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *pd = [p mutableCopy];
                    id lb = pd[@"Label"];
                    if (lb && g_lab[lb]) pd[@"Label"] = g_lab[lb];
                    [np addObject:pd];
                } else [np addObject:p];
            }
            def[@"parameters"] = np;
        }
        out[ident] = def;
    }
    return out;
}
#pragma mark - 显示链咽喉（0.4.21：仅 Shortcuts 进程）

static IMP g_origGet = NULL;
static IMP g_origCreate = NULL, g_origCreateMulti = NULL, g_origAdd = NULL, g_origSet = NULL;
static NSMutableSet *g_createSeen = nil;



static NSString *ZHLogDir(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *g = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.is.workflow.shortcuts"];
        dir = g ? g.path : @"/var/mobile/Documents";
    });
    return dir;
}

// 0.4.29：模板库 name swizzle（添加动作页渲染源候选）
static IMP g_origTplName[2] = {NULL, NULL};
static NSString *ZH_tplname_imp(id self, SEL _cmd) {
    @try {
        NSString *ident = [self valueForKey:@"identifier"];
        if ([ident isKindOfClass:[NSString class]] && [ident hasPrefix:@"com.anthopak.powercuts.action."]) {
            NSString *si = [ident substringFromIndex:30];
            NSDictionary *tr = ZHTr(ident);
            if (tr && tr[@"n"]) {
                return tr[@"n"];
            }
        }
    } @catch (id e) {}
    IMP o = nil;
    Class c = [self class];
    if (class_getInstanceMethod(object_getClass(c), _cmd) == NULL && c == objc_getClass("WFActionTemplateMetadata")) o = g_origTplName[0];
    else o = g_origTplName[0];
    if (c == objc_getClass("WFActionTemplate")) o = g_origTplName[1];
    return o ? ((NSString *(*)(id, SEL))o)(self, _cmd) : nil;
}

// 0.4.30：WFCustomAction.processedParametersDic swizzle（名字就在这个字典里——渲染源实锤）
static IMP g_origPPD = NULL;
static NSMapTable *g_ppdCache = nil;
static NSDictionary *ZH_ppd_imp(id self, SEL _cmd) {
    @try {
        NSDictionary *orig = ((NSDictionary *(*)(id, SEL))g_origPPD)(self, _cmd);

        if (!g_ppdCache) g_ppdCache = [NSMapTable weakToStrongObjectsMapTable];
        NSDictionary *cached = [g_ppdCache objectForKey:self];
        if (cached) return cached;
        if (![orig isKindOfClass:[NSDictionary class]]) return orig;
        NSString *ident = [self valueForKey:@"identifier"];
        if (![ident isKindOfClass:[NSString class]]) return orig;
        NSString *si = [ident hasPrefix:@"com.anthopak.powercuts.action."] ? [ident substringFromIndex:30] : ident;
        NSDictionary *tr = ZHTr(ident);
        if (!tr) return orig;
        NSMutableDictionary *out = [orig mutableCopy];
        if (tr[@"n"]) { out[@"name"] = tr[@"n"]; if ([out[@"summary"] isKindOfClass:[NSString class]]) out[@"summary"] = tr[@"n"]; }
        if (tr[@"d"]) out[@"descriptionSummary"] = tr[@"d"];
        if (tr[@"s"] && [(NSString *)tr[@"s"] length]) { out[@"parameterSummary"] = tr[@"s"]; if ([out[@"canvasSummary"] isKindOfClass:[NSString class]]) out[@"canvasSummary"] = tr[@"s"]; }
        id params = out[@"parameters"];
        if ([params isKindOfClass:[NSArray class]]) {
            NSMutableArray *np = [NSMutableArray array];
            for (NSDictionary *p in params) {
                NSMutableDictionary *q = [p mutableCopy];
                id lab = q[@"Label"];      if (lab) q[@"Label"] = g_lab[lab] ?: lab;
                id ph  = q[@"Placeholder"]; if (ph) q[@"Placeholder"] = g_lab[ph] ?: ph;
                [np addObject:q];
            }
            out[@"parameters"] = np;
        }

        [g_ppdCache setObject:out forKey:self];
        return out;
    } @catch (id e) {
        return ((NSDictionary *(*)(id, SEL))g_origPPD)(self, _cmd);
    }
}

// 0.4.33：详情页 descriptionSummary / description swizzle
static IMP g_origWCDs = NULL, g_origWCDesc = NULL;
static NSString *ZH_dsummary_imp(id self, SEL _cmd) {
    @try {
        NSString *ident = [self valueForKey:@"identifier"];
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"d"]) return tr[@"d"];
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origWCDs)(self, _cmd);
}
static NSString *ZH_desc_imp(id self, SEL _cmd) {
    @try {
        NSString *ident = [self valueForKey:@"identifier"];
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"d"]) return tr[@"d"];
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origWCDesc)(self, _cmd);
}

// 0.4.26：WFCustomAction -name swizzle（显示层终结打点）
static IMP g_origForCat = NULL, g_origActions = NULL;
static NSArray *ZH_logItems(NSArray *items, NSString *via) {
    return items;
}
static NSArray *ZH_forcat_imp(id self, SEL _cmd, id cat) {
    NSArray *r = ((NSArray *(*)(id, SEL, id))g_origForCat)(self, _cmd, cat);
    return ZH_logItems(r, @"forCat");
}
static NSArray *ZH_actions_imp(id self, SEL _cmd) {
    NSArray *r = ((NSArray *(*)(id, SEL))g_origActions)(self, _cmd);
    return ZH_logItems(r, @"actions");
}
static IMP g_origWCName = NULL;
static int g_wcNameCalls = 0;
static NSString *ZH_wcname_imp(id self, SEL _cmd) {
    g_wcNameCalls++;

    @try {
        NSString *ident = [self valueForKey:@"identifier"];
        if ([ident isKindOfClass:[NSString class]] && [ident hasPrefix:@"com.anthopak.powercuts.action."]) {
            NSString *si = [ident substringFromIndex:30];
            NSDictionary *tr = ZHTr(ident);
            if (tr && tr[@"n"]) {
                return tr[@"n"];
            }
        }
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origWCName)(self, _cmd);
}


static void ZHLogAction(id act, NSString *ident, NSString *via) { (void)act; (void)ident; (void)via; }

static void ZHTranslateActionObj(id act, NSString *via) {
    @try {
        NSString *ident = [act valueForKey:@"identifier"];
        if (![ident isKindOfClass:[NSString class]]) return;
        if (![ident hasPrefix:@"com.anthopak.powercuts.action."]) return;
        NSDictionary *tr = ZHTr(ident);
        if (tr && act) {
            if (tr[@"n"]) [act setValue:tr[@"n"] forKey:@"name"];
            if (tr[@"d"]) [act setValue:tr[@"d"] forKey:@"descriptionSummary"];
            if (tr[@"s"] && [(NSString *)tr[@"s"] length]) [act setValue:tr[@"s"] forKey:@"parameterSummary"];
        }
    } @catch (id e) {}
}

// PCM getter：翻译一次后记忆化——固定返回同一对象，避免 KVO 变更检测死循环（0.4.20 卡顿根因）
static NSMutableDictionary *g_getterCache = nil; // proc|origClass -> translated
static id ZH_cacheGet_imp(id self, SEL _cmd) {
    @try {
        id v = ((id(*)(id, SEL))g_origGet)(self, _cmd);
        if (!g_getterCache) g_getterCache = [NSMutableDictionary new];
        NSString *ck = NSStringFromClass([v class]);
        id cached = g_getterCache[ck];
        if (cached) return cached;
        if ([v isKindOfClass:[NSDictionary class]]) {
            id t = PCZHL10N(v);
            if (t) g_getterCache[ck] = t;
            return t;
        }
        if ([v isKindOfClass:[NSArray class]]) {
            NSMutableArray *out = [NSMutableArray array];
            for (id item in v) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    NSString *ident = item[@"identifier"];
                    NSString *si = [ident isKindOfClass:[NSString class]] && [ident hasPrefix:@"com.anthopak.powercuts.action."] ? [ident substringFromIndex:30] : ident;
                    NSDictionary *tr = ZHTr(ident);
                    if (tr) {
                        NSMutableDictionary *q = [item mutableCopy];
                        if (tr[@"n"]) q[@"name"] = tr[@"n"];
                        if (tr[@"d"]) q[@"descriptionSummary"] = tr[@"d"];
                        if (tr[@"s"] && [(NSString *)tr[@"s"] length]) q[@"parameterSummary"] = tr[@"s"];
                        [out addObject:q];
                        continue;
                    }
                } else if ([item isKindOfClass:objc_getClass("PCAction")]) {
                    ZHTranslateActionObj(item, @"getter");
                    [out addObject:item];
                    continue;
                }
                [out addObject:item];
            }
            g_getterCache[ck] = out;
            return out;
        }
        g_getterCache[ck] = v;
        return v;
    } @catch (id e) { return ((id(*)(id, SEL))g_origGet)(self, _cmd); }
}

static id ZH_create_imp(id self, SEL _cmd, NSString *ident, id params) {
    id act = ((id(*)(id, SEL, id, id))g_origCreate)(self, _cmd, ident, params);
    if (act) ZHTranslateActionObj(act, @"create1");
    return act;
}
static id ZH_createmulti_imp(id self, SEL _cmd, NSArray *idents, NSArray *params) {
    id out = ((id(*)(id, SEL, id, id))g_origCreateMulti)(self, _cmd, idents, params);
    @try {
        if ([out isKindOfClass:[NSArray class]]) for (id act in out) {
            if ([act isKindOfClass:[NSArray class]]) { for (id a in act) ZHTranslateActionObj(a, @"createN"); }
            else ZHTranslateActionObj(act, @"createN");
        }
    } @catch (id e) {}
    return out;
}
static void ZH_add_imp(id self, SEL _cmd, NSArray *actions, id provider) {
    ((void(*)(id, SEL, id, id))g_origAdd)(self, _cmd, actions, provider);
    @try {
        for (id act in actions) {
            if ([act isKindOfClass:[NSArray class]]) { for (id a in act) ZHTranslateActionObj(a, @"add"); }
            else ZHTranslateActionObj(act, @"add");
        }
    } @catch (id e) {}
}
static void ZH_set_imp(id self, SEL _cmd, NSArray *actions, id provider) {
    ((void(*)(id, SEL, id, id))g_origSet)(self, _cmd, actions, provider);
    @try {
        for (id act in actions) {
            if ([act isKindOfClass:[NSArray class]]) { for (id a in act) ZHTranslateActionObj(a, @"set"); }
            else ZHTranslateActionObj(act, @"set");
        }
    } @catch (id e) {}
}


static int ZHScanDir(NSMutableString *report, NSString *dir, int depth, int *hits) {
    if (depth > 4 || *hits > 15) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (!items) return 0;
    int scanned = 0;
    for (NSString *f in items) {
        if (scanned > 300) break;
        NSString *p = [dir stringByAppendingPathComponent:f];
        NSDictionary *st = [fm attributesOfItemAtPath:p error:nil];
        if (!st) continue;
        if ([st.fileType isEqualToString:NSFileTypeDirectory]) {
            if ([f containsString:@"Caches"] || [f containsString:@"SplashBoard"]) continue;
            scanned += ZHScanDir(report, p, depth + 1, hits);
        } else {
            unsigned long long sz = [st fileSize];
            if (sz == 0 || sz > 5 * 1024 * 1024) continue;
            NSData *d = [NSData dataWithContentsOfFile:p];
            if (!d) continue;
            scanned++;
            if (d.length > 100 && memmem(d.bytes, d.length, "com.anthopak.powercuts.action", 29)) {
                (*hits)++;
                [report appendFormat:@"HIT: %@ (%llu KB)\n", p, sz / 1024];
            }
        }
    }
    return scanned;
}



// 0.4.35：WFActionParameterSummary（画布卡片标题渲染对象）
static IMP g_origSumInit = NULL, g_origSumTitle = NULL, g_origSumLocTitle = NULL;
static id ZH_suminit_imp(id self, SEL _cmd, id action, id definition, NSString *title) {
    id r = ((id(*)(id, SEL, id, id, id))g_origSumInit)(self, _cmd, action, definition, title);
    @try { objc_setAssociatedObject(self, "zh_action", action, OBJC_ASSOCIATION_RETAIN_NONATOMIC); } @catch (id e) {}
    return r;
}
static NSString *ZH_sumtitle_imp(id self, SEL _cmd) {
    @try {
        id act = objc_getAssociatedObject(self, "zh_action");
        if (act) {
            NSDictionary *tr = ZHTr([act valueForKey:@"identifier"]);
            if (tr && tr[@"s"] && [(NSString *)tr[@"s"] length]) return tr[@"s"];
        }
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origSumTitle)(self, _cmd);
}
static NSString *ZH_sumloctitle_imp(id self, SEL _cmd) {
    @try {
        id act = objc_getAssociatedObject(self, "zh_action");
        if (act) {
            NSDictionary *tr = ZHTr([act valueForKey:@"identifier"]);
            if (tr && tr[@"s"] && [(NSString *)tr[@"s"] length]) return tr[@"s"];
        }
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origSumLocTitle)(self, _cmd);
}

// ===== 1.0.0 正式版 =====
// SpringBoard：延迟异步（文件翻译，防 dyld 早期初始化时序问题）
// Shortcuts：name/descriptionSummary/description/PPD 四 getter（显示链）
// Preferences：PSSpecifier 精确映射（设置页）
static void PCZHDelayedInit(void);

static void PCZHDelayedInit(void) {
        // 1.0.2：dyld 初始化阶段零工作——全部移入延迟块（0.5 秒后台）
        // 根因：新 bootstrap 环境 dyld 早期阶段 dladdr/字符串操作即崩（0.4.35/1.0.1 两份崩溃实证）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
            @autoreleasepool {
                @try { PCZHInitTables(); } @catch (id e) { return; }
                NSString *procName = [NSProcessInfo processInfo].processName;
                if ([procName isEqualToString:@"Shortcuts"]) {
                    @try {
                        Class pcm = objc_getClass("PCSharedBucketManager");
                        if (pcm) {
                            Method gm = class_getInstanceMethod(pcm, sel_registerName("registeredCustomActionsCachedData"));
                            if (gm && !g_origGet) {
                                g_origGet = method_getImplementation(gm);
                                method_setImplementation(gm, (IMP)ZH_cacheGet_imp);
                            }
                        }
                        Class wcc = objc_getClass("WFCustomAction");
                        if (wcc) {
                            struct { SEL s; IMP *orig; IMP rep; } hooks[] = {
                                { sel_registerName("name"), &g_origWCName, (IMP)ZH_wcname_imp },
                                { sel_registerName("descriptionSummary"), &g_origWCDs, (IMP)ZH_dsummary_imp },
                                { sel_registerName("description"), &g_origWCDesc, (IMP)ZH_desc_imp },
                                { sel_registerName("processedParametersDic"), &g_origPPD, (IMP)ZH_ppd_imp },
                            };
                            for (int hi = 0; hi < 4; hi++) {
                                Method cm = class_getInstanceMethod(wcc, hooks[hi].s);
                                if (cm && !*hooks[hi].orig) {
                                    *hooks[hi].orig = method_getImplementation(cm);
                                    method_setImplementation(cm, hooks[hi].rep);
                                }
                            }
                        }
                        Class wps = objc_getClass("WFActionParameterSummary");
                        if (wps) {
                            Method im = class_getInstanceMethod(wps, sel_registerName("initWithAction:definition:title:"));
                            if (im && !g_origSumInit) {
                                g_origSumInit = method_getImplementation(im);
                                method_setImplementation(im, (IMP)ZH_suminit_imp);
                            }
                            Method tm = class_getInstanceMethod(wps, sel_registerName("title"));
                            if (tm && !g_origSumTitle) {
                                g_origSumTitle = method_getImplementation(tm);
                                method_setImplementation(tm, (IMP)ZH_sumtitle_imp);
                            }
                            Method lm = class_getInstanceMethod(wps, sel_registerName("localizedTitle"));
                            if (lm && !g_origSumLocTitle) {
                                g_origSumLocTitle = method_getImplementation(lm);
                                method_setImplementation(lm, (IMP)ZH_sumloctitle_imp);
                            }
                        }
                    } @catch (id e) {}
                }
                else if ([procName isEqualToString:@"Preferences"]) {
                    @try {
                        Class psc = objc_getClass("PSSpecifier");
                        if (psc) {
                            Method nm = class_getInstanceMethod(psc, sel_registerName("name"));
                            if (nm && !g_origSpecName) {
                                g_origSpecName = method_getImplementation(nm);
                                method_setImplementation(nm, (IMP)ZH_specname_imp);
                            }
                            Method pm = class_getInstanceMethod(psc, sel_registerName("propertyForKey:"));
                            if (pm && !g_origSpecProp) {
                                g_origSpecProp = method_getImplementation(pm);
                                method_setImplementation(pm, (IMP)ZH_specprop_imp);
                            }
                        }
                    } @catch (id e) {}
                }
// SpringBoard 不在过滤器中：无 SB 侧代码}
            }
        });
}

%ctor {
    @autoreleasepool {
        PCZHDelayedInit();
    }
}
