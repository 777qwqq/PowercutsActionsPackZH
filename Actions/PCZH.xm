// PCZH Hook 汉化 v0.4.0 — hook libpowercuts 数据层，官方动作包显示中文
// 原理：拦截 -[PCSharedBucketManager registeredCustomActionsCachedData]
//       在返回前按 identifier 映射表重写 name/descriptionSummary/parameterSummary/参数 Label
// 官方执行逻辑零改动
#import "pczh_api.h"
#import <Foundation/Foundation.h>

#pragma mark - 汉化映射表

static NSDictionary *PCZHNames(void) {
    static NSDictionary *t = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"audioBalance": @{@"name": @"音量平衡", @"desc": @"设置左右声道音量平衡。左为 -1，右为 1。默认 0。", @"summary": @"音量平衡设为 ${balanceValue}"},
            @"autoTouchRunFile": @{@"name": @"运行 LUA 文件", @"desc": @"运行 AutoTouch 的 LUA 脚本。", @"summary": @""},
            @"connectToBluetoothDevice": @{@"name": @"连接/断开蓝牙设备", @"desc": @"连接或断开指定名称的蓝牙设备。", @"summary": @"${connect}名为 ${deviceName} 的蓝牙设备"},
            @"deleteGlobalVariable": @{@"name": @"删除全局变量", @"desc": @"删除指定键的全局变量值。", @"summary": @"删除键为 ${key} 的全局变量"},
            @"dismissSiri": @{@"name": @"关闭 Siri", @"desc": @"关闭 Siri 界面。\n适用于配合 Siri 使用的快捷指令：先关闭 Siri 再执行其他动作。", @"summary": @""},
            @"donate": @{@"name": @"支持开发者", @"desc": @"运行我！运行我！", @"summary": @""},
            @"getAllInstalledApps": @{@"name": @"获取全部已装应用", @"desc": @"返回设备上所有已安装应用的标识符。\n当前返回值为文本（暂不支持数组输出），可用“拆分文本”动作以换行分隔拆分。", @"summary": @""},
            @"getAppBadgeCount": @{@"name": @"获取应用角标数", @"desc": @"获取指定应用当前的角标数。", @"summary": @"获取标识符为 ${bundleId} 的应用角标数"},
            @"getAppNameFromIdentifier": @{@"name": @"获取应用信息", @"desc": @"根据标识符返回应用信息。", @"summary": @"获取标识符为 ${bundleId} 的应用的 ${informationType}"},
            @"getBluetoothDeviceBattery": @{@"name": @"获取蓝牙设备电量", @"desc": @"返回指定名称蓝牙设备的电量。", @"summary": @"获取名为 ${deviceName} 的蓝牙设备电量"},
            @"getBluetoothDevices": @{@"name": @"获取蓝牙设备", @"desc": @"返回已连接/已配对的蓝牙设备。\n当前返回值为文本（暂不支持数组输出），可用“拆分文本”动作以换行分隔拆分。", @"summary": @"获取${type}蓝牙设备"},
            @"getCurrentApp": @{@"name": @"获取当前应用", @"desc": @"返回前台应用的标识符。", @"summary": @""},
            @"getFileContent": @{@"name": @"获取文本文件内容", @"desc": @"以文本形式获取任意系统文件的内容。", @"summary": @""},
            @"getFilesFromFolderPath": @{@"name": @"获取文件夹内容", @"desc": @"获取文件夹内所有文件/子文件夹。\n当前返回值为文本（暂不支持数组输出），可用“拆分文本”动作以换行分隔拆分。", @"summary": @""},
            @"getGlobalVariable": @{@"name": @"获取全局变量", @"desc": @"按键读取全局变量的值。", @"summary": @"获取键为 ${key} 的全局变量值"},
            @"getIsDeviceLocked": @{@"name": @"获取设备锁定状态", @"desc": @"设备已锁定返回 Yes，否则返回 No。", @"summary": @""},
            @"getNowPlayingApp": @{@"name": @"获取正在播放的应用", @"desc": @"返回正在播放媒体的应用标识符。", @"summary": @""},
            @"getPressedButtons": @{@"name": @"获取按下的按键", @"desc": @"返回当前所有被按住的按键，可用于根据按键状态构建条件。\n可能的值：电源键、音量+、音量-、Home\n当前返回值为文本（暂不支持数组输出），可用“拆分文本”动作以换行分隔拆分，或直接判断输出是否包含某值。", @"summary": @""},
            @"getWorkflowRunSource": @{@"name": @"获取运行来源", @"desc": @"返回快捷指令的运行来源。\n可能的值：ShortcutsApp、Siri、Widget、HomePod、HomescreenIcon、Automation、SpringCuts", @"summary": @""},
            @"goHome": @{@"name": @"回到主屏幕", @"desc": @"回到主屏幕。", @"summary": @""},
            @"goToHomeScreenPage": @{@"name": @"跳转主屏幕页", @"desc": @"将主屏幕滚动到指定页（从 1 开始）。", @"summary": @"跳到主屏幕第 ${pageIndex} 页"},
            @"killApp": @{@"name": @"结束应用", @"desc": @"按标识符结束已安装的应用。", @"summary": @"结束标识符为 ${bundleId} 的应用"},
            @"ldRestart": @{@"name": @"LD 重启", @"desc": @"运行 LDRestart 命令。需要 smokin1337 的 ldrestarthelper 包。", @"summary": @""},
            @"lock": @{@"name": @"锁定设备", @"desc": @"锁定设备。", @"summary": @""},
            @"openApp": @{@"name": @"打开应用", @"desc": @"按标识符打开已安装的应用。原版“打开应用”不支持传参，本动作可以。", @"summary": @"打开标识符为 ${bundleId} 的应用"},
            @"quickSwitch": @{@"name": @"快速开关", @"desc": @"编辑快捷指令时快速停用某些动作的开关。输出开(Yes)/关(No)，配合“如果”动作使用。", @"summary": @"快速开关 - ${state}"},
            @"removeNotifications": @{@"name": @"移除匹配的通知", @"desc": @"移除匹配过滤条件的通知（应用标识符或关键词）。", @"summary": @""},
            @"respring": @{@"name": @"注销", @"desc": @"注销设备（重启 SpringBoard）。", @"summary": @""},
            @"runCommand": @{@"name": @"运行命令", @"desc": @"运行系统命令。", @"summary": @""},
            @"safeMode": @{@"name": @"安全模式", @"desc": @"使设备进入安全模式。", @"summary": @""},
            @"sendDistributedNotification": @{@"name": @"发送分布式通知", @"desc": @"向 NSDistributedNotificationCenter 发送通知（开发者向）。", @"summary": @"发送名为 ${notificationName} 的分布式通知"},
            @"sendNotification": @{@"name": @"发送通知", @"desc": @"以指定应用的名义向设备发送推送通知，横幅使用该应用的图标和名称。\n需要 CokePokes 的 libnotifications 插件（BigBoss 或 https://cokepokes.github.io）。", @"summary": @""},
            @"setAppBadgeCount": @{@"name": @"设置应用角标", @"desc": @"设置指定应用的角标数。", @"summary": @"将标识符为 ${bundleId} 的应用角标设为 ${badgeCount}"},
            @"setGlobalVariable": @{@"name": @"设置全局变量", @"desc": @"为指定键的全局变量设置值。", @"summary": @"将键为 ${key} 的全局变量设为 ${value}"},
            @"showAppSwitcher": @{@"name": @"显示多任务", @"desc": @"以动画方式打开应用切换器。", @"summary": @""},
            @"uiCache": @{@"name": @"重建图标缓存", @"desc": @"运行 UICache 命令。", @"summary": @""},
            @"unlock": @{@"name": @"密码解锁", @"desc": @"使用传入的密码解锁设备。请谨慎使用，这可能存在安全风险。", @"summary": @"使用密码 ${password} 解锁设备"},
            @"wakeScreen": @{@"name": @"唤醒屏幕", @"desc": @"唤醒屏幕（模拟轻点唤醒，适合自动化或 SSH 场景）。", @"summary": @""},
        };
    });
    return t;
}

// 参数 Label/Placeholder 精确匹配替换（全局）
static NSDictionary *PCZHLabels(void) {
    static NSDictionary *t = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"Balance value": @"平衡值",
            @"File Path": @"文件路径",
            @"Device name": @"设备名称",
            @"key": @"键名",
            @"Key": @"键名",
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
        };
    });
    return t;
}

static id PCZHL10NValue(id v, NSDictionary *labels) {
    if ([v isKindOfClass:[NSString class]]) {
        NSString *cn = labels[v];
        return cn ? cn : v;
    }
    if ([v isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [(NSDictionary *)v mutableCopy];
        for (NSString *k in d.allKeys) {
            id nv = PCZHL10NValue(d[k], labels);
            if (nv != d[k]) d[k] = nv;
        }
        return d;
    }
    if ([v isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [(NSArray *)v mutableCopy];
        for (NSUInteger i = 0; i < a.count; i++) {
            id nv = PCZHL10NValue(a[i], labels);
            if (nv != a[i]) a[i] = nv;
        }
        return a;
    }
    return v;
}

static NSDictionary *PCZHL10N(NSDictionary *orig) {
    if (!orig.count) return orig;
    NSDictionary *names = PCZHNames();
    NSDictionary *labels = PCZHLabels();
    NSMutableDictionary *out = [orig mutableCopy];
    for (NSString *ident in out.allKeys) {
        NSString *shortIdent = [ident hasPrefix:@"com.anthopak.powercuts.action."]
            ? [ident substringFromIndex:@"com.anthopak.powercuts.action.".length] : ident;
        NSDictionary *tr = names[shortIdent];
        if (!tr) continue;
        NSMutableDictionary *def = [out[ident] mutableCopy];
        if (def == nil) continue;
        id nm = tr[@"name"];    if (nm)   def[@"name"] = nm;
        id ds = tr[@"desc"];    if (ds)   def[@"descriptionSummary"] = ds;
        id sm = tr[@"summary"]; if (sm && [(NSString *)sm length]) def[@"parameterSummary"] = sm;
        def[@"parameters"] = PCZHL10NValue(def[@"parameters"], labels);
        out[ident] = def;
    }
    return out;
}

#pragma mark - Hook

%hook PCSharedBucketManager
- (NSDictionary *)registeredCustomActionsCachedData {
    NSDictionary *orig = %orig;
    return PCZHL10N(orig);
}
%end
