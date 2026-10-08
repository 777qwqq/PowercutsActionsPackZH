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
static void PCZHInitSettingsMap(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_setMap = @{
            @"HOW IT WORKS": @"工作原理",
            @"USEFUL ADDITIONS": @"实用增强",
            @"Disable Automation notifications": @"禁用自动化通知",
            @"Automations without confirmation": @"自动化无需确认",
            @"Allow import/export Shortcuts as files": @"允许以文件方式导入/导出快捷指令",
            @"Allow running sensitive actions unauthenticated": @"敏感动作无需解锁验证",
            @"Allow running sensistive actions unauthenticated": @"敏感动作无需解锁验证",
            @"Hide top progress banner": @"隐藏顶部进度横幅",
            @"Respring": @"注销",
            @"Enabled (respring required)": @"启用（需注销）",
        };
    });
}
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
static void PCZHSBDeferredInit(void);

static void PCZHDelayedInit(void) {
        PCZHInitTables();
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
                        { sel_registerName("initWithAction:definition:title:"), NULL, NULL },
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
                PCZHInitSettingsMap();
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
        else if ([procName isEqualToString:@"SpringBoard"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
                PCZHSBDeferredInit();
            });
        }
}

static void PCZHSBDeferredInit(void) {
        @try {
            PCZHInitTables();
            NSString *base = @"/var/mobile/Library/Preferences/com.anthopak.powercuts.registeredActionsData.plist";
            Dl_info di;
            if (dladdr((void *)PCZHSBDeferredInit, &di) && di.dli_fname) {
                NSString *self_ = [NSString stringWithUTF8String:di.dli_fname];
                NSRange r = [self_ rangeOfString:@".jbroot-"];
                if (r.location != NSNotFound) {
                    NSString *rest = [self_ substringFromIndex:r.location];
                    NSRange slash = [rest rangeOfString:@"/"];
                    if (slash.location != NSNotFound) {
                        NSString *jbroot = [self_ substringToIndex:r.location + slash.location];
                        base = [NSString stringWithFormat:@"%@/var/mobile/Library/Preferences/com.anthopak.powercuts.registeredActionsData.plist", jbroot];
                    }
                }
            }
            NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:base];
            if (file && [file[@"registeredCustomActionsData"] isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *pf = [file mutableCopy];
                pf[@"registeredCustomActionsData"] = PCZHL10N(pf[@"registeredCustomActionsData"]);
                if ([pf writeToFile:base atomically:YES]) notify_post("com.anthopak.powercuts.dataChanged");
            }
        } @catch (id e) {}
}

%ctor {
    @autoreleasepool {
        PCZHDelayedInit();
    }
}
