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

static IMP ZHOrig(id self, NSString *kind) {
    return (IMP)[g_origs[[NSString stringWithFormat:@"%@|%@", NSStringFromClass([self class]), kind]] pointerValue];
}

#pragma mark - 替换实现

static NSString *ZH_name_imp(id self, SEL _cmd, NSString *ident) {
    NSDictionary *tr = g_tr[ident];
    if (tr[@"n"]) return tr[@"n"];
    IMP o = ZHOrig(self, @"name");
    return o ? ((NSString *(*)(id, SEL, NSString *))o)(self, _cmd, ident) : ident;
}

static NSString *ZH_desc_imp(id self, SEL _cmd, NSString *ident) {
    NSDictionary *tr = g_tr[ident];
    if (tr[@"d"]) return tr[@"d"];
    IMP o = ZHOrig(self, @"desc");
    return o ? ((NSString *(*)(id, SEL, NSString *))o)(self, _cmd, ident) : @"";
}

static NSString *ZH_summary_imp(id self, SEL _cmd, NSString *ident) {
    NSDictionary *tr = g_tr[ident];
    if (tr[@"s"] && [(NSString *)tr[@"s"] length]) return tr[@"s"];
    IMP o = ZHOrig(self, @"summary");
    return o ? ((NSString *(*)(id, SEL, NSString *))o)(self, _cmd, ident) : @"";
}

static NSArray *ZH_params_imp(id self, SEL _cmd, NSString *ident) {
    IMP o = ZHOrig(self, @"params");
    NSArray *arr = o ? ((NSArray *(*)(id, SEL, NSString *))o)(self, _cmd, ident) : nil;
    if (!arr.count) return arr;
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *p in arr) {
        NSMutableDictionary *q = [p mutableCopy];
        id lab = q[@"Label"];   if (lab) q[@"Label"] = g_lab[lab] ?: lab;
        id ph  = q[@"Placeholder"]; if (ph) q[@"Placeholder"] = g_lab[ph] ?: ph;
        [out addObject:q];
    }
    return out;
}

#pragma mark - 安装



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


static IMP origStore = NULL;
static void ZH_store_imp(id self, SEL _cmd, NSDictionary *actionsData, BOOL writeToCache) {
    NSDictionary *translated = PCZHL10N(actionsData);
    if (origStore) ((void(*)(id,SEL,id,BOOL))origStore)(self, _cmd, translated, writeToCache);
}

static NSDictionary *ZH_cachedData_imp(id self, SEL _cmd) {
    NSDictionary *orig = ((NSDictionary*(*)(id,SEL))objc_msgSend)(self, _cmd);
    return PCZHL10N(orig);
}

static void ZHHookClass(Class cls) {
    NSString *cn = NSStringFromClass(cls);
    if (g_origs[[NSString stringWithFormat:@"%@|%@", cn, @"name"]] != nil) return;
#define HOOK(selName, kind, imp) do { \
    SEL s = sel_registerName(selName); \
    Method m = class_getInstanceMethod(cls, s); \
    if (m && class_addMethod(cls, s, (IMP)imp, method_getTypeEncoding(m)) == NO) { \
        g_origs[[NSString stringWithFormat:@"%@|%@", cn, kind]] = [NSValue valueWithPointer:(void *)method_getImplementation(m)]; \
        method_setImplementation(m, (IMP)imp); \
    } else if (m) { \
        g_origs[[NSString stringWithFormat:@"%@|%@", cn, kind]] = NULL; \
    } \
} while(0)
    HOOK("nameForIdentifier:", @"name", ZH_name_imp);
    HOOK("descriptionSummaryForIdentifier:", @"desc", ZH_desc_imp);
    HOOK("parameterSummaryForIdentifier:", @"summary", ZH_summary_imp);
    HOOK("parametersDefinitionForIdentifier:", @"params", ZH_params_imp);
#undef HOOK
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
        @try {
            PCZHInitTables();
            g_origs = [NSMutableDictionary new];
            NSMutableString *report = [NSMutableString string];
            int num = objc_getClassList(NULL, 0);
            if (num <= 0) return;
            Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * num);
            objc_getClassList(classes, num);
            Class pcAction = objc_getClass("PCAction");
            int hooked = 0;
            if (pcAction) {
                for (int i = 0; i < num; i++) {
                    Class c = classes[i];
                    BOOL isSub = NO;
                    Class p = class_getSuperclass(c);
                    while (p) {
                        if (p == pcAction) { isSub = YES; break; }
                        p = class_getSuperclass(p);
                    }
                    if (isSub) { ZHHookClass(c); hooked++; [report appendFormat:@"%@\n", NSStringFromClass(c)]; }
                }
            }
            free(classes);
            [report insertString:[NSString stringWithFormat:@"hooked=%d PCAction=%@\n", hooked, pcAction ? @"存在" : @"不存在"] atIndex:0];
            [report writeToFile:@"/var/mobile/Documents/pczh34_hooked.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];

            // getter swizzle: 缓存读取全走中文
            Class bm = objc_getClass("PCSharedBucketManager");
            if (bm) {
                Method m = class_getInstanceMethod(bm, sel_registerName("registeredCustomActionsCachedData"));
                if (m) method_setImplementation(m, (IMP)ZH_cachedData_imp);
            }
            // 写入路径 hook: 注册写缓存前先翻译
            Method m2 = class_getInstanceMethod(bm, sel_registerName("storeNewRegisteredCustomActionsCachedData:"));
            if (m2) {
                origStore = method_getImplementation(m2);
                method_setImplementation(m2, (IMP)ZH_store_imp);
            }

            // 缓存文件中文化（读原文件→翻译→写回）
            @try {
                NSString *path = @"/var/mobile/Library/Preferences/com.anthopak.powercuts.registeredActionsData.plist";
                NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:path];
                if (file) {
                    NSMutableDictionary *pf = [file mutableCopy];
                    id inner = pf[@"registeredActionsData.plist"];
                    if ([inner isKindOfClass:[NSDictionary class]]) {
                        pf[@"registeredActionsData.plist"] = PCZHL10N(inner);
                        [pf writeToFile:path atomically:YES];
                        notify_post("com.anthopak.powercuts.dataChanged");
                    }
                }
            } @catch (id e) {}
        } @catch (id e) {}
    });
}
