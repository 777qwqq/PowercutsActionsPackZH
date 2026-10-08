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

static NSString *ZHLogDir(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *g = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.is.workflow.shortcuts"];
        dir = g ? g.path : @"/var/mobile/Documents";
    });
    return dir;
}

// 0.4.26：WFCustomAction -name swizzle（显示层终结打点）
static IMP g_origForCat = NULL, g_origActions = NULL;
static NSArray *ZH_logItems(NSArray *items, NSString *via) {
    static int n = 0;
    if (n < 6 && items.count) {
        n++;
        NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_query.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
        [lg appendFormat:@"%@ count=%lu\n", via, (unsigned long)items.count];
        for (id it in items) {
            if ([it isKindOfClass:[NSArray class]]) { [lg appendFormat:@"  arr:\n"]; for (id a in it) [lg appendFormat:@"    %@\n", NSStringFromClass([a class])]; }
            else [lg appendFormat:@"  %@\n", NSStringFromClass([it class])];
        }
        [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_query.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
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
    if (g_wcNameCalls <= 3 || g_wcNameCalls % 50 == 0) {
        NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_wcname.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
        [lg appendFormat:@"call#%d\n", g_wcNameCalls];
        [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_wcname.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    @try {
        NSString *ident = [self valueForKey:@"identifier"];
        if ([ident isKindOfClass:[NSString class]] && [ident hasPrefix:@"com.anthopak.powercuts.action."]) {
            NSString *si = [ident substringFromIndex:30];
            NSDictionary *tr = g_tr[si];
            if (tr && tr[@"n"]) {
                static int logged = 0;
                if (logged < 10) {
                    logged++;
                    NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_wchits.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
                    [lg appendFormat:@"%@ | class=%@ | tr=%@ | g_trcount=%lu\n", ident, NSStringFromClass([self class]), tr[@"n"], (unsigned long)g_tr.count];
                    [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_wchits.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
                return tr[@"n"];
            }
        }
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origWCName)(self, _cmd);
}


static void ZHLogAction(id act, NSString *ident, NSString *via) {
    if (!g_createSeen) g_createSeen = [NSMutableSet new];
    NSString *key = [NSString stringWithFormat:@"%@|%@", via, ident];
    if ([g_createSeen containsObject:key]) return;
    [g_createSeen addObject:key];
    NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_create.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
    NSMutableString *props = [NSMutableString string];
    unsigned int pc = 0;
    objc_property_t *pl = class_copyPropertyList([act class], &pc);
    for (unsigned int i2 = 0; i2 < pc && i2 < 30; i2++) [props appendFormat:@"%s ", property_getName(pl[i2])];
    free(pl);
    [lg appendFormat:@"%@ | %@ | %@ | props: %@\n", via, ident, NSStringFromClass([act class]), props];
    [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_create.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void ZHTranslateActionObj(id act, NSString *via) {
    @try {
        NSString *ident = [act valueForKey:@"identifier"];
        if (![ident isKindOfClass:[NSString class]]) return;
        if (![ident hasPrefix:@"com.anthopak.powercuts.action."]) return;
        ZHLogAction(act, ident, via);
        if (!g_createSeen) g_createSeen = [NSMutableSet new];
        NSString *k2 = [NSString stringWithFormat:@"VAL|%@", ident];
        if (![g_createSeen containsObject:k2]) {
            [g_createSeen addObject:k2];
            id nm = nil, ti = nil;
            @try { nm = [act valueForKey:@"name"]; } @catch (id e) {}
            @try { ti = [act valueForKey:@"title"]; } @catch (id e) {}
            NSMutableString *lg = [NSMutableString stringWithContentsOfFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_values.txt"] encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
            [lg appendFormat:@"%@ name=%@ title=%@\n", ident, nm, ti];
            [lg writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_values.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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



static void PCZHDelayedInit(void) {
        NSMutableString *report = [NSMutableString string];
        NSString *procName = [NSProcessInfo processInfo].processName;
        @try {
            PCZHInitTables();
            [report appendFormat:@"proc=%@ step=entry\n", procName];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (id e) { return; }
        if (![procName isEqualToString:@"Shortcuts"]) {
            [report appendString:@"skipped (not Shortcuts)\n"];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (id e) {
            [report appendFormat:@"scan CRASHED: %@\n", e];
            [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
            [report appendString:@"step=done v0.4.28\n"];
        } @catch (id e) {
            [report appendFormat:@"hooks CRASHED: %@\n", e];
        }
        [report writeToFile:[ZHLogDir() stringByAppendingPathComponent:@"pczh58_hooked.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%ctor {
    @autoreleasepool {
        PCZHDelayedInit();
    }
}
