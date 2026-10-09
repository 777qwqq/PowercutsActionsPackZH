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
        g_tr = @{
            @"com.anthopak.powercuts.action.audioBalance": @{ @"n": @"音量平衡", @"d": @"设置左右声道音量平衡。左为 -1，右为 1。默认 0。", @"s": @"音量平衡设为 ${balanceValue}" },
            @"com.anthopak.powercuts.action.autoTouchRunFile": @{ @"n": @"运行 LUA 文件", @"d": @"运行 AutoTouch 的 LUA 脚本。", @"s": @"" },
            @"com.anthopak.powercuts.action.connectToBluetoothDevice": @{ @"n": @"连接/断开蓝牙设备", @"d": @"连接或断开指定名称的蓝牙设备。", @"s": @"${connect}名为 ${deviceName} 的蓝牙设备" },
            @"com.anthopak.powercuts.action.deleteGlobalVariable": @{ @"n": @"删除全局变量", @"d": @"删除指定键的全局变量值。", @"s": @"删除键为 ${key} 的全局变量" },
            @"com.anthopak.powercuts.action.dismissSiri": @{ @"n": @"关闭 Siri", @"d": @"关闭 Siri 界面。适用于配合 Siri 使用的快捷指令：先关闭 Siri 再执行其他动作。", @"s": @"" },
            @"com.anthopak.powercuts.action.donate": @{ @"n": @"支持开发者", @"d": @"运行我！运行我！", @"s": @"" },
            @"com.anthopak.powercuts.action.getAllInstalledApps": @{ @"n": @"获取全部已装应用", @"d": @"返回设备上所有已安装应用的标识符。当前返回值为文本（暂不支持数组输出），可用\"拆分文本\"以换行分隔拆分。", @"s": @"" },
            @"com.anthopak.powercuts.action.getAppBadgeCount": @{ @"n": @"获取应用角标数", @"d": @"获取指定应用当前的角标数。", @"s": @"获取标识符为 ${bundleId} 的应用角标数" },
            @"com.anthopak.powercuts.action.getAppNameFromIdentifier": @{ @"n": @"获取应用信息", @"d": @"根据标识符返回已安装应用的信息。", @"s": @"获取标识符为 ${bundleId} 的应用的 ${informationType}" },
            @"com.anthopak.powercuts.action.getBluetoothDeviceBattery": @{ @"n": @"获取蓝牙设备电量", @"d": @"返回指定名称蓝牙设备的电量。", @"s": @"获取名为 ${deviceName} 的蓝牙设备电量" },
            @"com.anthopak.powercuts.action.getBluetoothDevices": @{ @"n": @"获取蓝牙设备", @"d": @"返回已连接或已配对的蓝牙设备。当前返回值为文本（暂不支持数组输出），可用\"拆分文本\"以换行分隔拆分。", @"s": @"获取${type}的蓝牙设备" },
            @"com.anthopak.powercuts.action.getCurrentApp": @{ @"n": @"获取当前应用", @"d": @"返回当前前台应用的标识符。", @"s": @"" },
            @"com.anthopak.powercuts.action.getFileContent": @{ @"n": @"获取文本文件内容", @"d": @"以文本形式获取任意文件的内容。", @"s": @"" },
            @"com.anthopak.powercuts.action.getFilesFromFolderPath": @{ @"n": @"获取文件夹内容", @"d": @"获取文件夹内的所有文件与子文件夹。当前返回值为文本（暂不支持数组输出）。", @"s": @"" },
            @"com.anthopak.powercuts.action.getGlobalVariable": @{ @"n": @"获取全局变量", @"d": @"按键读取全局变量的值。", @"s": @"获取键为 ${key} 的全局变量值" },
            @"com.anthopak.powercuts.action.getIsDeviceLocked": @{ @"n": @"获取设备锁定状态", @"d": @"设备已锁定时返回\"是\"，否则返回\"否\"。", @"s": @"" },
            @"com.anthopak.powercuts.action.getNowPlayingApp": @{ @"n": @"获取正在播放的应用", @"d": @"返回正在播放媒体的应用标识符。", @"s": @"" },
            @"com.anthopak.powercuts.action.getPressedButtons": @{ @"n": @"获取按下的按键", @"d": @"返回当前所有被按住的按键，可用于构建条件。可能的值：电源键、音量+、音量-。当前返回值为文本。", @"s": @"" },
            @"com.anthopak.powercuts.action.getWorkflowRunSource": @{ @"n": @"获取运行来源", @"d": @"返回快捷指令的运行来源。可能的值：快捷指令 App、Siri、小组件、主屏幕图标、自动化等。", @"s": @"" },
            @"com.anthopak.powercuts.action.goHome": @{ @"n": @"回到主屏幕", @"d": @"返回主屏幕。", @"s": @"" },
            @"com.anthopak.powercuts.action.goToHomeScreenPage": @{ @"n": @"跳转主屏幕页", @"d": @"将主屏幕滚动到指定页（从 1 开始）。", @"s": @"跳到主屏幕第 ${pageIndex} 页" },
            @"com.anthopak.powercuts.action.killApp": @{ @"n": @"结束应用", @"d": @"按标识符结束已安装的应用。", @"s": @"结束标识符为 ${bundleId} 的应用" },
            @"com.anthopak.powercuts.action.ldRestart": @{ @"n": @"LD 重启", @"d": @"运行 LDRestart 命令。需要 ldrestarthelper 包。", @"s": @"" },
            @"com.anthopak.powercuts.action.lock": @{ @"n": @"锁定设备", @"d": @"锁定设备。", @"s": @"" },
            @"com.anthopak.powercuts.action.openApp": @{ @"n": @"打开应用", @"d": @"按标识符打开已安装的应用。", @"s": @"打开标识符为 ${bundleId} 的应用" },
            @"com.anthopak.powercuts.action.quickSwitch": @{ @"n": @"快速开关", @"d": @"创建快捷指令时快速停用某些动作的开关。输出开（是）/关（否），配合\"如果\"动作使用。", @"s": @"快速开关 - ${state}" },
            @"com.anthopak.powercuts.action.removeNotifications": @{ @"n": @"移除匹配的通知", @"d": @"移除匹配过滤条件（应用标识符或关键词）的通知。", @"s": @"" },
            @"com.anthopak.powercuts.action.respring": @{ @"n": @"注销", @"d": @"注销设备（重启 SpringBoard）。", @"s": @"" },
            @"com.anthopak.powercuts.action.runCommand": @{ @"n": @"运行命令", @"d": @"以 root 身份运行系统命令。", @"s": @"" },
            @"com.anthopak.powercuts.action.safeMode": @{ @"n": @"安全模式", @"d": @"使设备进入安全模式。", @"s": @"" },
            @"com.anthopak.powercuts.action.sendDistributedNotification": @{ @"n": @"发送分布式通知", @"d": @"向 NSDistributedNotificationCenter 发送通知（面向开发者）。", @"s": @"发送名为 ${notificationName} 的分布式通知" },
            @"com.anthopak.powercuts.action.sendNotification": @{ @"n": @"发送通知", @"d": @"以指定应用的名义向设备发送推送通知，横幅使用该应用的图标和名称。需要 libnotifications 插件。", @"s": @"" },
            @"com.anthopak.powercuts.action.setAppBadgeCount": @{ @"n": @"设置应用角标", @"d": @"设置指定应用的角标数。", @"s": @"将标识符为 ${bundleId} 的应用角标设为 ${badgeCount}" },
            @"com.anthopak.powercuts.action.setGlobalVariable": @{ @"n": @"设置全局变量", @"d": @"为指定键的全局变量设置值。", @"s": @"将键为 ${key} 的全局变量设为 ${value}" },
            @"com.anthopak.powercuts.action.showAppSwitcher": @{ @"n": @"显示多任务", @"d": @"以动画方式打开应用切换器。", @"s": @"" },
            @"com.anthopak.powercuts.action.uiCache": @{ @"n": @"重建图标缓存", @"d": @"运行 UICache 命令。", @"s": @"" },
            @"com.anthopak.powercuts.action.unlock": @{ @"n": @"密码解锁", @"d": @"使用传入的密码解锁设备。请谨慎使用，这可能带来安全风险。", @"s": @"使用密码 ${password} 解锁设备" },
            @"com.anthopak.powercuts.action.wakeScreen": @{ @"n": @"唤醒屏幕", @"d": @"唤醒屏幕（模拟轻点唤醒，适合自动化或 SSH 场景）。", @"s": @"" },
        };
        g_lab = @{
            @"Balance value": @"平衡值",
            @"File Path": @"文件路径",
            @"Device name": @"设备名称",
            @"key": @"键名",
            @"bundleId": @"应用标识符",
            @"informationType": @"信息类型",
            @"type": @"类型",
            @"pageIndex": @"页码",
            @"badgeCount": @"角标数",
            @"value": @"值",
            @"state": @"状态",
            @"notificationName": @"通知名称",
            @"password": @"密码",
            @"connect": @"操作",
            @"Label": @"标签",
            @"Name": @"名称",
            @"Password": @"密码",
            @"Filter": @"过滤条件",
        };
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
                static int tl = 0;
                if (tl < 10) {
                    tl++;
                    NSMutableString *lg = nil;
                    [lg appendFormat:@"%@ | %@\n", NSStringFromClass([self class]), tr[@"n"]];
                    if (lg) [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh60_tplhits.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
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
        {
            static int pd2 = 0;
            if (pd2 < 3 && orig.count) { pd2++;
                NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_ppd.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
                NSString *ident = nil;
                @try { ident = [self valueForKey:@"identifier"]; } @catch (id e) {}
                [lg appendFormat:@"ident=%@\n%@$\n----\n", ident, [orig description]];
                [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_ppd.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
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
        if (tr[@"n"]) out[@"name"] = tr[@"n"];
        if (tr[@"d"]) out[@"descriptionSummary"] = tr[@"d"];
        if (tr[@"s"] && [(NSString *)tr[@"s"] length]) out[@"parameterSummary"] = tr[@"s"];
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
        // 0.4.33：观察日志已移除
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



static BOOL g_cacheTrDone = NO;
// 0.4.39：缓存层深度翻译（画布直接读 registeredCustomActionsCachedData 的最后可能）
static IMP g_origCacheGet = NULL, g_origCacheSet = NULL;

static void ZHDeepTr(NSMutableDictionary *def, NSDictionary *tr) {
    if (!tr) return;
    for (NSString *k in [def copy]) {
        id v = def[k];
        if ([v isKindOfClass:[NSMutableDictionary class]] || [v isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *vd = [(NSDictionary *)v mutableCopy];
            ZHDeepTr(vd, tr);
            def[k] = vd;
        } else if ([v isKindOfClass:[NSMutableArray class]] || [v isKindOfClass:[NSArray class]]) {
            NSMutableArray *na = [NSMutableArray array];
            for (id it in (NSArray *)v) {
                if ([it isKindOfClass:[NSDictionary class]]) {
                    NSMutableDictionary *nit = [(NSDictionary *)it mutableCopy];
                    ZHDeepTr(nit, tr);
                    [na addObject:nit];
                } else [na addObject:it];
            }
            def[k] = na;
        } else if ([v isKindOfClass:[NSString class]]) {
            if ([k isEqualToString:@"ActionName"] && tr[@"n"]) { def[k] = tr[@"n"]; continue; }
            if ([k isEqualToString:@"ActionDescriptionSummary"] && tr[@"d"]) { def[k] = tr[@"d"]; continue; }
            if ([k isEqualToString:@"ActionDescription"] && tr[@"d"]) { def[k] = tr[@"d"]; continue; }
            if ([k rangeOfString:@"ummary"].location != NSNotFound && tr[@"s"]) { def[k] = tr[@"s"]; continue; }
            if ([k isEqualToString:@"Label"] || [k isEqualToString:@"Placeholder"]) {
                id t = g_lab[v];
                if (t) def[k] = t;
            }
        }
    }
}

static id ZHCacheTr(NSDictionary *raw) {
    if ([raw isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [(NSDictionary *)raw mutableCopy];
        for (NSString *k in [out copy]) {
            id v = out[k];
            if ([k hasPrefix:@"com.anthopak.powercuts"] && [v isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *vd = [(NSDictionary *)v mutableCopy];
                ZHDeepTr(vd, ZHTr(k));
                out[k] = vd;
            } else if ([v isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *vd = [(NSDictionary *)v mutableCopy];
                id aid = vd[@"ActionIdentifier"] ?: vd[@"Identifier"];
                if ([aid isKindOfClass:[NSString class]]) { ZHDeepTr(vd, ZHTr(aid)); out[k] = vd; }
            } else if ([v isKindOfClass:[NSArray class]]) {
                NSMutableArray *na = [NSMutableArray array];
                for (id it in (NSArray *)v) {
                    if ([it isKindOfClass:[NSDictionary class]]) {
                        NSMutableDictionary *nit = [(NSDictionary *)it mutableCopy];
                        id aid = nit[@"ActionIdentifier"] ?: [k isKindOfClass:[NSString class]] ? k : nil;
                        id tr = ZHTr([aid isKindOfClass:[NSString class]] ? aid : @"");
                        if (!tr && [nit isKindOfClass:[NSDictionary class]]) {
                            id an = nit[@"ActionName"];
                            if ([an isKindOfClass:[NSString class]]) {
                                for (NSString *ik in g_tr) { if ([g_tr[ik][@"n"] isEqualToString:an]) { tr = g_tr[ik]; break; } }
                            }
                        }
                        ZHDeepTr(nit, tr);
                        [na addObject:nit];
                    } else [na addObject:it];
                }
                out[k] = na;
            }
        }
        return out;
    }
    return raw;
}

static id ZH_cacheget_imp(id self, SEL _cmd) {
    id orig = ((id(*)(id, SEL))g_origCacheGet)(self, _cmd);
    @try {
        if (orig && !g_cacheTrDone) {
            g_cacheTrDone = YES;
            NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_cache.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
            [lg appendFormat:@"RAW结构:\n%@\n----\n", [orig description]];
            [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_cache.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        id tr = ZHCacheTr(orig);
        if (tr != orig) {
            static int cgt = 0;
            if (cgt < 2) { cgt++;
                NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_cache.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
                [lg appendFormat:@"GET 已翻译 (第%d次)\n----\n", cgt];
                [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_cache.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
        return tr;
    } @catch (id e) { return orig; }
}
static void ZH_cachegetset_imp(id self, SEL _cmd, id v) {
    @try { ((void(*)(id, SEL, id))g_origCacheSet)(self, _cmd, v); } @catch (id e) {}
}

// 0.4.38：WFAction 级显示名（画布卡标题候选源）
static IMP g_origLN = NULL, g_origLSN = NULL;
static void ZHLNLog(NSString *tag, NSString *cls, NSString *ident, NSString *orig) {
    static int n = 0;
    if (n < 12) { n++;
        NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_ln.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
        [lg appendFormat:@"%@ cls=%@ ident=%@ orig=%@\n", tag, cls, ident, orig];
        [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_ln.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
static NSString *ZH_ln_imp(id self, SEL _cmd) {
    NSString *o = nil;
    @try { o = ((NSString *(*)(id, SEL))g_origLN)(self, _cmd); } @catch (id e) { return nil; }
    @try {
        if ([self isKindOfClass:objc_getClass("WFCustomAction")]) {
            NSString *ident = nil;
            @try { ident = [self valueForKey:@"identifier"]; } @catch (id e) {}
            NSDictionary *tr = ZHTr(ident);
            ZHLNLog(@"LN", NSStringFromClass([self class]), ident, o);
            if (tr && tr[@"n"]) return tr[@"n"];
        }
    } @catch (id e) {}
    return o;
}
static NSString *ZH_lsn_imp(id self, SEL _cmd) {
    NSString *o = nil;
    @try { o = ((NSString *(*)(id, SEL))g_origLSN)(self, _cmd); } @catch (id e) { return nil; }
    @try {
        if ([self isKindOfClass:objc_getClass("WFCustomAction")]) {
            NSString *ident = nil;
            @try { ident = [self valueForKey:@"identifier"]; } @catch (id e) {}
            NSDictionary *tr = ZHTr(ident);
            ZHLNLog(@"LSN", NSStringFromClass([self class]), ident, o);
            if (tr && tr[@"n"]) return tr[@"n"];
        }
    } @catch (id e) {}
    return o;
}

// 0.4.37：PCAction 按 identifier 查询的显示口
static IMP g_origPCName = NULL, g_origPCDesc = NULL, g_origPCSum = NULL;
static NSString *ZH_pcname_imp(id self, SEL _cmd, NSString *ident) {
    @try {
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"n"]) {
            static int pc1 = 0;
            if (pc1 < 5) { pc1++;
                NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_pca.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
                [lg appendFormat:@"name HIT ident=%@\n", ident];
                [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_pca.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
            return tr[@"n"];
        }
        static int pc2 = 0;
        if (pc2 < 5) { pc2++;
            NSString *o = ((NSString *(*)(id, SEL, NSString *))g_origPCName)(self, _cmd, ident);
            NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_pca.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
            [lg appendFormat:@"name MISS ident=%@ orig=%@\n", ident, o];
            [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh69_pca.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return o;
        }
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL, NSString *))g_origPCName)(self, _cmd, ident);
}
static NSString *ZH_pcdesc_imp(id self, SEL _cmd, NSString *ident) {
    @try {
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"d"]) return tr[@"d"];
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL, NSString *))g_origPCDesc)(self, _cmd, ident);
}
static NSString *ZH_pcsum_imp(id self, SEL _cmd, NSString *ident) {
    @try {
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"s"] && [(NSString *)tr[@"s"] length]) return tr[@"s"];
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL, NSString *))g_origPCSum)(self, _cmd, ident);
}

// 0.4.36：画布卡片 WFActionParameterSummary（标题在 init 的 title 参数里传入）
static IMP g_origSumInit = NULL, g_origSumTitle = NULL, g_origSumLocTitle = NULL;

static void ZHDefTranslate(NSMutableDictionary *def, NSDictionary *tr) {
    if (![def isKindOfClass:[NSMutableDictionary class]]) return;
    for (NSString *k in [def copy]) {
        id v = def[k];
        if ([k isEqualToString:@"ActionName"]) {
            if (tr[@"n"]) def[k] = tr[@"n"];
        } else if ([k rangeOfString:@"ummary"].location != NSNotFound) {
            if ([v isKindOfClass:[NSString class]] && tr[@"s"]) def[k] = tr[@"s"];
            else if ([v isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *vd = [v mutableCopy];
                id sv = vd[@"String"];
                if ([sv isKindOfClass:[NSString class]] && tr[@"s"]) { vd[@"String"] = tr[@"s"]; def[k] = vd; }
            }
        }
    }
}

static id ZH_suminit_imp(id self, SEL _cmd, id action, id definition, NSString *title) {
    @try {
        NSString *ident = nil;
        @try { ident = [action valueForKey:@"identifier"]; } @catch (id e) {}
        NSDictionary *tr = ZHTr(ident);
        if (tr) {
            if (tr[@"n"]) title = tr[@"n"];
            if ([definition isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *md = [definition mutableCopy];
                ZHDefTranslate(md, tr);
                definition = md;
            }
            static int dc = 0;
            if (dc < 5 && [definition isKindOfClass:[NSDictionary class]]) {
                dc++;
                NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh67_def.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
                [lg appendFormat:@"ident=%@\ntitle=%@\nkeys=%@\n", ident, title, [(NSDictionary *)definition allKeys]];
                for (NSString *k in (NSDictionary *)definition) {
                    id v = ((NSDictionary *)definition)[k];
                    if ([v isKindOfClass:[NSString class]]) [lg appendFormat:@"  %@ = %@\n", k, v];
                    else if ([v isKindOfClass:[NSDictionary class]]) [lg appendFormat:@"  %@ = dict%@\n", k, [(NSDictionary *)v allKeys]];
                    else if ([v isKindOfClass:[NSArray class]]) [lg appendFormat:@"  %@ = arr%lu\n", k, (unsigned long)[(NSArray *)v count]];
                }
                [lg appendString:@"----\n"];
                [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh67_def.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
        }
        objc_setAssociatedObject(self, "zh_ident", ident, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (id e) {}
    return ((id(*)(id, SEL, id, id, id))g_origSumInit)(self, _cmd, action, definition, title);
}
static NSString *ZH_sumtitle_imp(id self, SEL _cmd) {
    @try {
        NSString *ident = objc_getAssociatedObject(self, "zh_ident");
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"n"]) return tr[@"n"];
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origSumTitle)(self, _cmd);
}
static NSString *ZH_sumloctitle_imp(id self, SEL _cmd) {
    @try {
        NSString *ident = objc_getAssociatedObject(self, "zh_ident");
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"n"]) return tr[@"n"];
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origSumLocTitle)(self, _cmd);
}

// 0.4.40：设置页（Preferences 进程）—— PSSpecifier 拦截 + 全量 dump
static IMP g_origSpecName = NULL, g_origGetProp = NULL;
static NSDictionary *g_prefsTr = nil;

// 长文本：精确匹配 → 长键前缀匹配（≥30 字符）
static NSString *ZH_prefsLookup(NSString *o) {
    if (!o.length) return nil;
    id t = g_prefsTr[o];
    if ([t isKindOfClass:[NSString class]]) return t;
    if (o.length >= 30) {
        for (NSString *k in g_prefsTr) {
            if (k.length >= 30 && [o hasPrefix:k]) {
                id tv = g_prefsTr[k];
                if ([tv isKindOfClass:[NSString class]]) return tv;
            }
        }
    }
    return nil;
}

static NSString *ZH_prefsLineTr(NSString *line) {
    // 逐行前缀匹配（行内任何微差不影响）
    if ([line hasPrefix:@"- Disable Automation notifications:"]) return @"- 禁用自动化通知：自动化运行时不再发送通知";
    if ([line hasPrefix:@"- Automations without confirmation:"]) return @"- 自动化无需确认：所有触发器均可免确认直接运行自动化（注意：邮件和信息触发器不支持）";
    if ([line hasPrefix:@"- Allow import/export Shortcuts as files:"]) return @"- 允许以文件形式导入/导出快捷指令：以文件（.shortcuts 或 .wflow）而非 iCloud 链接导入/导出";
    if ([line hasPrefix:@"- Allow running sensitive actions unauthenticated:"]) return @"- 允许免认证运行敏感操作：部分操作运行前不再要求解锁。适合在锁屏可运行的自动化中使用。并非对所有敏感操作生效。";
    if ([line hasPrefix:@"- Hide top progress banner:"]) return @"- 隐藏顶部进度横幅：隐藏从主屏图标、辅助触控等运行快捷指令时顶部的进度横幅";
    return nil;
}

static NSString *ZH_prefsFooterFix(NSString *o) {
    // 长注释逐行兜底（换行变体）
    if ([o hasPrefix:@"- Disable Automation notifications:"] || [o containsString:@"- Disable Automation notifications:"]) {
        if (![o hasPrefix:@"- Disable"]) {
            // 逐行处理
            NSMutableArray *out = [NSMutableArray array];
            for (NSString *line in [o componentsSeparatedByString:@"\n"]) {
                NSString *t = ZH_prefsLineTr(line);
                [out addObject: t ?: line];
            }
            return [out componentsJoinedByString:@"\n"];
        }
        NSString *en1 = @"- Disable Automation notifications: prevents notifications when automations run\n";
        NSString *en2 = @"- Automations without confirmation: adds the ability to run automations without having to confirm, for all triggers (please note that it won't work for Mail and Message triggers)\n";
        NSString *en3 = @"- Allow import/export Shortcuts as files: adds the ability to import/export Shortcuts as a file (.shortcuts or .wflow) instead of an iCloud link\n";
        NSString *en4 = @"- Allow running sensitive actions unauthenticated: prevent some actions from asking to unlock your phone before running. It can be useful when using such actions in an automation which can run while locked. Does NOT work with all sensitive actions.\n";
        NSString *en5 = @"- Hide top progress banner: hide the intrusive top progress banner which shows while running a Shortcut from an homescreen icon, from Assistive Touch, or else";
        NSString *r = [o copy];
        r = [r stringByReplacingOccurrencesOfString:en1 withString:@"- 禁用自动化通知：自动化运行时不再发送通知\n"];
        r = [r stringByReplacingOccurrencesOfString:en2 withString:@"- 自动化无需确认：所有触发器均可免确认直接运行自动化（注意：邮件和信息触发器不支持）\n"];
        r = [r stringByReplacingOccurrencesOfString:en3 withString:@"- 允许以文件形式导入/导出快捷指令：以文件（.shortcuts 或 .wflow）而非 iCloud 链接导入/导出\n"];
        r = [r stringByReplacingOccurrencesOfString:en4 withString:@"- 允许免认证运行敏感操作：部分操作运行前不再要求解锁。适合在锁屏可运行的自动化中使用。并非对所有敏感操作生效。\n"];
        r = [r stringByReplacingOccurrencesOfString:en5 withString:@"- 隐藏顶部进度横幅：隐藏从主屏图标、辅助触控等运行快捷指令时顶部的进度横幅"];
        return r;
    }
    return nil;
}

static NSString *ZH_prefsTr(NSString *o) {
    NSString *r = ZH_prefsLookup(o);
    if (r) return r;
    return ZH_prefsFooterFix(o);
}

static NSString *ZH_specname_imp(id self, SEL _cmd) {
    NSString *o = nil;
    @try { o = ((NSString *(*)(id, SEL))g_origSpecName)(self, _cmd); } @catch (id e) { return nil; }
    @try {
        if (o.length) {
            NSString *t = ZH_prefsTr(o);
            if ([t isKindOfClass:[NSString class]]) return t;
            BOOL hasAscii = NO;
            for (NSUInteger ci = 0; ci < o.length && !hasAscii; ci++) {
                unichar ch = [o characterAtIndex:ci];
                if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) hasAscii = YES;
            }
            if (hasAscii) {
                static int sn = 0;
                if (sn < 200) { sn++;
                    id ident = nil;
                    @try { ident = [self valueForKey:@"identifier"]; } @catch (id e) {}
                    NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh71_prefs.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
                    [lg appendFormat:@"name=%@ | ident=%@\n", o, ident];
                    [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh71_prefs.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            }
        }
    } @catch (id e) {}
    return o;
}

static id ZH_getprop_imp(id self, SEL _cmd, NSString *key) {
    id v = ((id(*)(id, SEL, NSString *))g_origGetProp)(self, _cmd, key);
    @try {
        if ([v isKindOfClass:[NSString class]] && [key isKindOfClass:[NSString class]]) {
            NSString *t = ZH_prefsTr(v);
            if (t) return t;
        }
    } @catch (id e) {}
    return v;
}

static IMP g_origSetSpecs = NULL;
static void ZH_setspecs_imp(id self, SEL _cmd, NSArray *specs) {
    ((void(*)(id, SEL, NSArray *))g_origSetSpecs)(self, _cmd, specs);
    @try {
        for (PSSpecifier *spec in specs) {
            if (![spec isKindOfClass:objc_getClass("PSSpecifier")]) continue;
            for (NSString *key in @[@"name", @"header", @"footerText", @"title", @"label"]) {
                @try {
                    NSString *raw = [spec propertyForKey:key];
                    if (![raw isKindOfClass:[NSString class]]) continue;
                    NSString *t = ZH_prefsTr(raw);
                    if ([t isKindOfClass:[NSString class]]) {
                        Method m = class_getInstanceMethod([spec class], sel_registerName("setProperty:forKey:"));
                        if (m) {
                            void (*sp)(id, SEL, id, NSString *) = (void (*)(id, SEL, id, NSString *))method_getImplementation(m);
                            sp(spec, sel_registerName("setProperty:forKey:"), t, key);
                        }
                    }
                } @catch (id e) {}
            }
        }
    } @catch (id e) {}
}

static void PCZHPrefsInit(void) {
    @try {
        // prefs 表：table.json 的 prefs 分区（英文原文 → 中文）
        @try {
            NSString *tp = @"/var/jb/usr/share/pczh/table.json";
            NSDictionary *t = [NSDictionary dictionaryWithContentsOfFile:tp] ?: ({ NSData *td = [NSData dataWithContentsOfFile:tp]; td ? [NSJSONSerialization JSONObjectWithData:td options:0 error:nil] : nil; });
            id p = t[@"prefs"];
            if ([p isKindOfClass:[NSDictionary class]]) g_prefsTr = p;
        } @catch (id e) {}
        Class pss = objc_getClass("PSSpecifier");
        if (pss) {
            Method m = class_getInstanceMethod(pss, sel_registerName("name"));
            if (m && !g_origSpecName) {
                g_origSpecName = method_getImplementation(m);
                method_setImplementation(m, (IMP)ZH_specname_imp);
            }

            Method m3 = class_getInstanceMethod(pss, sel_registerName("propertyForKey:"));
            if (m3 && !g_origGetProp) { g_origGetProp = method_getImplementation(m3); method_setImplementation(m3, (IMP)ZH_getprop_imp); }
            Class plc = objc_getClass("PSListController");
            if (plc) {
                Method m4 = class_getInstanceMethod(plc, sel_registerName("setSpecifiers:"));
                if (m4 && !g_origSetSpecs) { g_origSetSpecs = method_getImplementation(m4); method_setImplementation(m4, (IMP)ZH_setspecs_imp); }
            }
            NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh71_prefs.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
            [lg appendString:@"== PSSpecifier name/setProp/getProp hooked ==\n"];
            [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh71_prefs.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (id e) {}
}

static void PCZHDelayedInit(void) {
        NSMutableString *report = [NSMutableString string];
        NSString *procName = [NSProcessInfo processInfo].processName;
        @try {
            PCZHInitTables();
            [report appendFormat:@"proc=%@ step=entry\n", procName];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (id e) { return; }
        if ([procName isEqualToString:@"Preferences"]) {
            PCZHPrefsInit();
            [report appendString:@"prefs-init done\n"];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        if (![procName isEqualToString:@"Shortcuts"]) {
            [report appendString:@"skipped (not Shortcuts)\n"];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        @try {
            NSFileManager *fm = [NSFileManager defaultManager];
            int hits = 0;
            for (NSString *root in @[@"/var/mobile/Containers/Data/Application", @"/var/mobile/Containers/Shared/AppGroup"]) {
                for (NSString *uuid in [fm contentsOfDirectoryAtPath:root error:nil]) {
                    if (hits > 15) break;
                    NSString *cpath = [root stringByAppendingPathComponent:uuid];
                    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:[cpath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
                    NSString *bid = [meta[@"MCMMetadataIdentifier"] isKindOfClass:[NSString class]] ? meta[@"MCMMetadataIdentifier"] : @"";
                    if (![bid containsString:@"shortcut"] && ![bid containsString:@"workflow"]) continue;
                    [report appendFormat:@"C: %@\n", cpath];
                    ZHScanDir(report, cpath, 2, &hits);
                }
            }
            [report appendFormat:@"scan hits=%d step=scan-done\n", hits];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (id e) {
            [report appendFormat:@"scan CRASHED: %@\n", e];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        @try {
            Class wfr = objc_getClass("WFActionRegistry");
            if (wfr) {
                int n = 4;
                SEL sl[4]; IMP *og[4]; IMP rp[4]; const char *tg[4];
                sl[0] = sel_registerName("createActionWithIdentifier:serializedParameters:");            og[0] = &g_origCreate;      rp[0] = (IMP)ZH_create_imp;      tg[0] = "create1";
                sl[1] = sel_registerName("createActionsWithIdentifiers:serializedParameterArray:");      og[1] = &g_origCreateMulti; rp[1] = (IMP)ZH_createmulti_imp; tg[1] = "createN";
                sl[2] = sel_registerName("addActions:fromActionProvider:");                              og[2] = &g_origAdd;         rp[2] = (IMP)ZH_add_imp;         tg[2] = "add";
                sl[3] = sel_registerName("setActions:forProvider:");                                     og[3] = &g_origSet;         rp[3] = (IMP)ZH_set_imp;         tg[3] = "set";
                // 0.4.28：registry 查询打点（渲染源）
                SEL acs = sel_registerName("actionsForCategory:");
                Method acm = class_getInstanceMethod(wfr, acs);
                if (acm && !g_origForCat) {
                    g_origForCat = method_getImplementation(acm);
                    method_setImplementation(acm, (IMP)ZH_forcat_imp);
                    [report appendString:@"forCat hooked\n"];
                }
                SEL asel = sel_registerName("actions");
                Method am = class_getInstanceMethod(wfr, asel);
                if (am && !g_origActions) {
                    g_origActions = method_getImplementation(am);
                    method_setImplementation(am, (IMP)ZH_actions_imp);
                    [report appendString:@"actions hooked\n"];
                }
                // 0.4.29：模板库 name hook
                {
                    const char *tplClasses[2] = {"WFActionTemplateMetadata", "WFActionTemplate"};
                    for (int ti = 0; ti < 2; ti++) {
                        Class tc = objc_getClass(tplClasses[ti]);
                        if (!tc) { [report appendFormat:@"%s nil\n", tplClasses[ti]]; continue; }
                        Method nm = class_getInstanceMethod(tc, sel_registerName("name"));
                        if (nm && !g_origTplName[ti]) {
                            g_origTplName[ti] = method_getImplementation(nm);
                            method_setImplementation(nm, (IMP)ZH_tplname_imp);
                            [report appendFormat:@"%s-name hooked\n", tplClasses[ti]];
                        } else if (!nm) [report appendFormat:@"%s-name NOT found\n", tplClasses[ti]];
                    }
                }
                // 0.4.31：类面扫描——WFAction* 类的 name/title 方法 + PC* 类全量方法
                @try {
                    int num3 = objc_getClassList(NULL, 0);
                    if (num3 > 0) {
                        Class *cls3 = (__unsafe_unretained Class *)malloc(sizeof(Class) * num3);
                        objc_getClassList(cls3, num3);
                        for (int ci = 0; ci < num3; ci++) {
                            const char *cn3 = class_getName(cls3[ci]);
                            BOOL isWF = strncmp(cn3, "WFAction", 8) == 0;
                            BOOL isPC = strncmp(cn3, "PC", 2) == 0;
                            if (!isWF && !isPC) continue;
                            if (isPC && strcmp(cn3, "PCAction") == 0) {} // PCAction 也要
                            NSMutableString *line = [NSMutableString string];
                            unsigned int mc3 = 0;
                            Method *ms3 = class_copyMethodList(cls3[ci], &mc3);
                            for (unsigned int mi = 0; mi < mc3; mi++) {
                                const char *sn = sel_getName(method_getName(ms3[mi]));
                                if (isPC || strstr(sn, "name") || strstr(sn, "Name") || strstr(sn, "title") || strstr(sn, "Title") || strstr(sn, "label") || strstr(sn, "descri")) {
                                    [line appendFormat:@"%s ", sn];
                                }
                            }
                            free(ms3);
                            if (line.length) [report appendFormat:@"%@ [%s]: %@\n", [NSString stringWithUTF8String:cn3], isPC ? "PC" : "WF", line];
                        }
                        free(cls3);
                    }
                } @catch (id e) {}
                // 0.4.29：Library 子目录全扫（找模板库持久化文件）
                @try {
                    int hits2 = 0;
                    NSFileManager *fm2 = [NSFileManager defaultManager];
                    for (NSString *d in [fm2 contentsOfDirectoryAtPath:@"/var/mobile/Library" error:nil]) {
                        if (hits2 > 10) break;
                        NSString *p = [@"/var/mobile/Library" stringByAppendingPathComponent:d];
                        BOOL isDir = NO;
                        [fm2 fileExistsAtPath:p isDirectory:&isDir];
                        if (!isDir) continue;
                        if ([d containsString:@"Caches"] || [d containsString:@"Media"] || [d containsString:@"SplashBoard"]) continue;
                        ZHScanDir(report, p, 1, &hits2);
                    }
                    [report appendFormat:@"lib-scan hits=%d\n", hits2];
                } @catch (id e) {}
                // 0.4.30：processedParametersDic hook（渲染源终结点）
                Class wcc2 = nil;
                if (wcc2 = objc_getClass("WFCustomAction")) {
                    Method pm = class_getInstanceMethod(wcc2, sel_registerName("processedParametersDic"));
                    if (pm && !g_origPPD) {
                        g_origPPD = method_getImplementation(pm);
                        method_setImplementation(pm, (IMP)ZH_ppd_imp);
                        [report appendString:@"PPD hooked\n"];
                    } else if (!pm) [report appendString:@"PPD NOT found\n"];
                }
                // WFCustomAction -name（第五打点）+ 全量方法/ivar dump
                {
                    Class wcc = objc_getClass("WFCustomAction");
                    if (wcc) {
                        { NSMutableString *chain = [NSMutableString string]; Class c = wcc; while (c) { [chain appendFormat:@"%@ <- ", NSStringFromClass(c)]; c = class_getSuperclass(c); } [report appendFormat:@"== WC chain: %@ ==\n", chain]; }
                        [report appendString:@"== WC methods ==\n"];
                        unsigned int mc = 0;
                        Method *ms = class_copyMethodList(wcc, &mc);
                        for (unsigned int mi = 0; mi < mc; mi++) [report appendFormat:@"%s\n", sel_getName(method_getName(ms[mi]))];
                        free(ms);
                        [report appendString:@"== WC ivars ==\n"];
                        unsigned int ic = 0;
                        Ivar *iv = class_copyIvarList(wcc, &ic);
                        for (unsigned int ii = 0; ii < ic; ii++) [report appendFormat:@"%s %s\n", ivar_getTypeEncoding(iv[ii]), ivar_getName(iv[ii])];
                        free(iv);
                        Method nm = class_getInstanceMethod(wcc, sel_registerName("name"));
                        if (nm && !g_origWCName) {
                            g_origWCName = method_getImplementation(nm);
                            method_setImplementation(nm, (IMP)ZH_wcname_imp);
                            [report appendString:@"WC-name hooked\n"];
                        } else if (!nm) [report appendString:@"WC-name NOT found\n"];
                        Method dsm = class_getInstanceMethod(wcc, sel_registerName("descriptionSummary"));
                        if (dsm && !g_origWCDs) {
                            g_origWCDs = method_getImplementation(dsm);
                            method_setImplementation(dsm, (IMP)ZH_dsummary_imp);
                            [report appendString:@"WC-dsummary hooked\n"];
                        }
                        Method dcm = class_getInstanceMethod(wcc, sel_registerName("description"));
                        if (dcm && !g_origWCDesc) {
                            g_origWCDesc = method_getImplementation(dcm);
                            method_setImplementation(dcm, (IMP)ZH_desc_imp);
                            [report appendString:@"WC-desc hooked\n"];
                        }
                    } else [report appendString:@"WFCustomAction class nil\n"];
                }
                for (int hi = 0; hi < n; hi++) {
                    Method cm = class_getInstanceMethod(wfr, sl[hi]);
                    if (cm && !*og[hi]) {
                        *og[hi] = method_getImplementation(cm);
                        method_setImplementation(cm, rp[hi]);
                        [report appendFormat:@"%s hooked\n", tg[hi]];
                    } else if (!cm) [report appendFormat:@"%s NOT found\n", tg[hi]];
                }
            } else [report appendString:@"WFActionRegistry nil\n"];
                // 0.4.39：PCSharedBucketManager 缓存层
                {
                    Class pbm = objc_getClass("PCSharedBucketManager");
                    if (pbm) {
                        Method m1 = class_getInstanceMethod(pbm, sel_registerName("registeredCustomActionsCachedData"));
                        BOOL c1 = NO;
                        if (!m1) { m1 = class_getClassMethod(pbm, sel_registerName("registeredCustomActionsCachedData")); c1 = YES; }
                        if (m1 && !g_origCacheGet) {
                            g_origCacheGet = method_getImplementation(m1);
                            method_setImplementation(m1, (IMP)ZH_cacheget_imp);
                            [report appendFormat:@"%sregisteredCustomActionsCachedData hooked\n", c1 ? "+" : "-"];
                        } else if (!m1) [report appendString:@"cacheGet NOT found\n"];
                    } else [report appendString:@"PCSharedBucketManager nil\n"];
                }
                // 0.4.38：WFAction 级显示名 hooks
                {
                    Class wfa = objc_getClass("WFAction");
                    if (wfa) {
                        Method m1 = class_getInstanceMethod(wfa, sel_registerName("localizedName"));
                        if (m1 && !g_origLN) { g_origLN = method_getImplementation(m1); method_setImplementation(m1, (IMP)ZH_ln_imp); [report appendString:@"WF-localizedName hooked\n"]; } else if (!m1) [report appendString:@"WF-localizedName NOT found\n"];
                        Method m2 = class_getInstanceMethod(wfa, sel_registerName("localizedShortName"));
                        if (m2 && !g_origLSN) { g_origLSN = method_getImplementation(m2); method_setImplementation(m2, (IMP)ZH_lsn_imp); [report appendString:@"WF-localizedShortName hooked\n"]; } else if (!m2) [report appendString:@"WF-localizedShortName NOT found\n"];
                    } else [report appendString:@"WFAction nil\n"];
                }
                // 0.4.37：PCAction 显示查询口（画布/列表真正的数据源）
                {
                    Class pca = objc_getClass("PCAction");
                    if (pca) {
                        const char *pcsels[3] = {"nameForIdentifier:", "descriptionSummaryForIdentifier:", "parameterSummaryForIdentifier:"};
                        IMP *imps[3] = {&g_origPCName, &g_origPCDesc, &g_origPCSum};
                        IMP imps2[3] = {(IMP)ZH_pcname_imp, (IMP)ZH_pcdesc_imp, (IMP)ZH_pcsum_imp};
                        for (int pi = 0; pi < 3; pi++) {
                            Method cm = class_getInstanceMethod(pca, sel_registerName(pcsels[pi]));
                            BOOL isClass = NO;
                            if (!cm) { cm = class_getClassMethod(pca, sel_registerName(pcsels[pi])); isClass = YES; }
                            if (cm && !*imps[pi]) {
                                *imps[pi] = method_getImplementation(cm);
                                method_setImplementation(cm, imps2[pi]);
                                [report appendFormat:@"%s%s hooked\n", isClass ? "+" : "-", pcsels[pi]];
                            } else if (!cm) [report appendFormat:@"%s NOT found\n", pcsels[pi]];
                        }
                    } else [report appendString:@"PCAction nil\n"];
                }
                // 0.4.36：画布卡片 hooks
                {
                    Class wps = objc_getClass("WFActionParameterSummary");
                    if (wps) {
                        Method m1 = class_getInstanceMethod(wps, sel_registerName("initWithAction:definition:title:"));
                        if (m1 && !g_origSumInit) {
                            g_origSumInit = method_getImplementation(m1);
                            method_setImplementation(m1, (IMP)ZH_suminit_imp);
                            [report appendString:@"SUM-init hooked\n"];
                        } else if (!m1) [report appendString:@"SUM-init NOT found\n"];
                        Method m2 = class_getInstanceMethod(wps, sel_registerName("title"));
                        if (m2 && !g_origSumTitle) {
                            g_origSumTitle = method_getImplementation(m2);
                            method_setImplementation(m2, (IMP)ZH_sumtitle_imp);
                            [report appendString:@"SUM-title hooked\n"];
                        } else if (!m2) [report appendString:@"SUM-title NOT found\n"];
                        Method m3 = class_getInstanceMethod(wps, sel_registerName("localizedTitle"));
                        if (m3 && !g_origSumLocTitle) {
                            g_origSumLocTitle = method_getImplementation(m3);
                            method_setImplementation(m3, (IMP)ZH_sumloctitle_imp);
                            [report appendString:@"SUM-loctitle hooked\n"];
                        } else if (!m3) [report appendString:@"SUM-loctitle NOT found\n"];
                    } else [report appendString:@"WFActionParameterSummary nil\n"];
                }
            [report appendString:@"step=done v0.4.44\n"];
        } @catch (id e) {
            [report appendFormat:@"hooks CRASHED: %@\n", e];
        }
        [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh70_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%ctor {
    @autoreleasepool {
        PCZHDelayedInit();
    }
}
