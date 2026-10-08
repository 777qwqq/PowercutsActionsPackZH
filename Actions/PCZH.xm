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
        NSDictionary *tr = g_tr[shortIdent];
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

static void ZHLogAction(id act, NSString *ident, NSString *via) {
    if (!g_createSeen) g_createSeen = [NSMutableSet new];
    NSString *key = [NSString stringWithFormat:@"%@|%@", via, ident];
    if ([g_createSeen containsObject:key]) return;
    [g_createSeen addObject:key];
    NSMutableString *lg = [NSMutableString stringWithContentsOfFile:@"/var/mobile/Documents/pczh51_create.txt" encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
    NSMutableString *props = [NSMutableString string];
    unsigned int pc = 0;
    objc_property_t *pl = class_copyPropertyList([act class], &pc);
    for (unsigned int i2 = 0; i2 < pc && i2 < 30; i2++) [props appendFormat:@"%s ", property_getName(pl[i2])];
    free(pl);
    [lg appendFormat:@"%@ | %@ | %@ | props: %@\n", via, ident, NSStringFromClass([act class]), props];
    [lg writeToFile:@"/var/mobile/Documents/pczh51_create.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void ZHTranslateActionObj(id act, NSString *via) {
    @try {
        NSString *ident = [act valueForKey:@"identifier"];
        if (![ident isKindOfClass:[NSString class]]) return;
        if (![ident hasPrefix:@"com.anthopak.powercuts.action."]) return;
        NSString *si = [ident substringFromIndex:30];
        NSDictionary *tr = g_tr[si];
        if (tr && act) {
            if (tr[@"n"]) [act setValue:tr[@"n"] forKey:@"name"];
            if (tr[@"d"]) [act setValue:tr[@"d"] forKey:@"descriptionSummary"];
            if (tr[@"s"] && [(NSString *)tr[@"s"] length]) [act setValue:tr[@"s"] forKey:@"parameterSummary"];
        }
        ZHLogAction(act, ident, via);
    } @catch (id e) {}
}

// PCM getter：返回翻译副本
static id ZH_cacheGet_imp(id self, SEL _cmd) {
    @try {
        id v = ((id(*)(id, SEL))g_origGet)(self, _cmd);
        if ([v isKindOfClass:[NSDictionary class]]) return PCZHL10N(v);
        if ([v isKindOfClass:[NSArray class]]) {
            NSMutableArray *out = [NSMutableArray array];
            for (id item in v) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    NSString *ident = item[@"identifier"];
                    NSString *si = [ident isKindOfClass:[NSString class]] && [ident hasPrefix:@"com.anthopak.powercuts.action."] ? [ident substringFromIndex:30] : ident;
                    NSDictionary *tr = si ? g_tr[si] : nil;
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
            return out;
        }
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

static void PCZHDelayedInit(void) {
        @try {
            PCZHInitTables();
            NSMutableString *report = [NSMutableString string];
            NSString *procName = [NSProcessInfo processInfo].processName;
            [report appendFormat:@"proc=%@\n", procName];
            if ([procName isEqualToString:@"Shortcuts"]) {
                Class pcm = objc_getClass("PCSharedBucketManager");
                if (pcm) {
                    Method gm = class_getInstanceMethod(pcm, sel_registerName("registeredCustomActionsCachedData"));
                    if (gm && !g_origGet) {
                        g_origGet = method_getImplementation(gm);
                        method_setImplementation(gm, (IMP)ZH_cacheGet_imp);
                        [report appendString:@"getter hooked\n"];
                    } else if (!gm) [report appendString:@"getter NOT found\n"];
                } else [report appendString:@"PCM nil\n"];
                Class wfr = objc_getClass("WFActionRegistry");
                if (wfr) {
                    struct { SEL s; IMP *orig; IMP rep; const char *tag; } hooks[] = {
                        { sel_registerName("createActionWithIdentifier:serializedParameters:"), &g_origCreate, (IMP)ZH_create_imp, "create1" },
                        { sel_registerName("createActionsWithIdentifiers:serializedParameterArray:"), &g_origCreateMulti, (IMP)ZH_createmulti_imp, "createN" },
                        { sel_registerName("addActions:fromActionProvider:"), &g_origAdd, (IMP)ZH_add_imp, "add" },
                        { sel_registerName("setActions:forProvider:"), &g_origSet, (IMP)ZH_set_imp, "set" },
                    };
                    for (int hi = 0; hi < 4; hi++) {
                        Method cm = class_getInstanceMethod(wfr, hooks[hi].s);
                        if (cm && !*hooks[hi].orig) {
                            *hooks[hi].orig = method_getImplementation(cm);
                            method_setImplementation(cm, hooks[hi].rep);
                            [report appendFormat:@"%s hooked\n", hooks[hi].tag];
                        } else if (!cm) [report appendFormat:@"%s NOT found\n", hooks[hi].tag];
                    }
                } else [report appendString:@"WFActionRegistry nil\n"];
            } else {
                [report appendString:@"registry hooks skipped (not Shortcuts)\n"];
            }
            [report appendString:@"mode=choke v0.4.21\n"];
            [report writeToFile:@"/var/mobile/Documents/pczh51_hooked.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (id e) {}
}

static void PCZHDelayedInit(void);

%ctor {
    @autoreleasepool {
        PCZHDelayedInit();
    }
}
