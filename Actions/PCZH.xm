// PCZHHook — Powercuts 汉化（0.4.49 清理版）
// 有效部件：列表(PCM getter/-name/PCAction) + 详情(dsummary/desc) + 画布(缓存层 ZHCacheTr)
// 探针（设置页调查中）：Preferences/Powercuts 进程的 nav/present/loadSpecifiers
#import "pczh_api.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <mach-o/dyld.h>

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

#pragma mark - 列表数据翻译（PCM getter 层）

static NSDictionary *PCZHL10N(NSDictionary *orig) {
    if (!orig || !orig.count) return orig;
    NSMutableDictionary *out = [orig mutableCopy];
    for (NSString *ident in out.allKeys) {
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

static NSString *ZHLogDir(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *g = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.is.workflow.shortcuts"];
        dir = g ? g.path : @"/var/mobile/Documents";
    });
    return dir;
}

#pragma mark - Shortcuts 显示链 hooks

// PCM getter：翻译后记忆化（0.4.20 卡顿根因修复：固定返回同一对象避免 KVO 死循环）
static IMP g_origGet = NULL;
static NSMutableDictionary *g_getterCache = nil;
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
                    NSDictionary *tr = ZHTr(ident);
                    if (tr) {
                        NSMutableDictionary *q = [item mutableCopy];
                        if (tr[@"n"]) q[@"name"] = tr[@"n"];
                        if (tr[@"d"]) q[@"descriptionSummary"] = tr[@"d"];
                        if (tr[@"s"] && [(NSString *)tr[@"s"] length]) q[@"parameterSummary"] = tr[@"s"];
                        [out addObject:q];
                        continue;
                    }
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

// WFCustomAction -name（列表标题）
static IMP g_origWCName = NULL;
static NSString *ZH_wcname_imp(id self, SEL _cmd) {
    @try {
        NSString *ident = [self valueForKey:@"identifier"];
        if ([ident isKindOfClass:[NSString class]] && [ident hasPrefix:@"com.anthopak.powercuts.action."]) {
            NSDictionary *tr = ZHTr(ident);
            if (tr && tr[@"n"]) return tr[@"n"];
        }
    } @catch (id e) {}
    return ((NSString *(*)(id, SEL))g_origWCName)(self, _cmd);
}

// 详情页 descriptionSummary / description
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

// PCAction 按 identifier 查询（画布/列表数据源，0.4.37 实锤有效）
static IMP g_origPCName = NULL, g_origPCDesc = NULL, g_origPCSum = NULL;
static NSString *ZH_pcname_imp(id self, SEL _cmd, NSString *ident) {
    @try {
        NSDictionary *tr = ZHTr(ident);
        if (tr && tr[@"n"]) return tr[@"n"];
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

#pragma mark - 画布缓存层（0.4.39 收官方案）

static void ZHDeepTr(NSMutableDictionary *def, NSDictionary *tr) {
    if (!tr) return;
    for (NSString *k in [def copy]) {
        id v = def[k];
        if ([v isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *vd = [(NSDictionary *)v mutableCopy];
            ZHDeepTr(vd, tr);
            def[k] = vd;
        } else if ([v isKindOfClass:[NSArray class]]) {
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
                        id aid = nit[@"ActionIdentifier"] ?: k;
                        id tr = ZHTr([aid isKindOfClass:[NSString class]] ? aid : @"");
                        if (!tr) {
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

static IMP g_origCacheGet = NULL;
static id ZH_cacheget_imp(id self, SEL _cmd) {
    id orig = ((id(*)(id, SEL))g_origCacheGet)(self, _cmd);
    @try { return ZHCacheTr(orig); } @catch (id e) { return orig; }
}

#pragma mark - 设置页映射（0.4.51：1.0.0 表 + 截图表 + typo 变体 + 长文本）
static NSDictionary *g_setMap = nil;
static void PCZHInitSettingsMap(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_setMap = @{
            @"HOW IT WORKS": @"工作原理",
            @"USEFUL ADDITIONS": @"实用增强",
            @"USEFUL LINKS FOR POWERCUTS": @"Powercuts 实用链接",
            @"Disable Automation notifications": @"禁用自动化通知",
            @"Automations without confirmation": @"自动化无需确认",
            @"Allow import/export Shortcuts as files": @"允许以文件方式导入/导出快捷指令",
            @"Allow running sensitive actions unauthenticated": @"敏感动作无需解锁验证",
            @"Allow running sensistive actions unauthenticated": @"敏感动作无需解锁验证",
            @"Hide top progress banner": @"隐藏顶部进度横幅",
            @"Respring": @"注销",
            @"Enabled (respring required)": @"启用（需注销）",
            @"Download pre-made workflows": @"下载现成快捷指令",
            @"Available packs & actions": @"可用动作包与动作",
            @"Developer documentation": @"开发者文档",
            @"Powercuts is a library for the iOS Shortcuts app, which brings the ability to add new actions to the app which can be used in your Shortcuts and Personal Automations. If you haven't already, install some actions packs by searching for \"Powercuts\" in your package manager. You'll then find those actions in the Shortcut editor, in Apps>Powercuts.": @"Powercuts 是 iOS「快捷指令」App 的功能扩展库，可为快捷指令和自动化新增操作。若尚未安装动作包，可在软件源搜索 \"Powercuts\" 安装。安装后，这些操作会出现在快捷指令编辑器的 App>Powercuts 分组中。"
        };
    });
}
static NSString *ZHMap(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return nil;
    NSString *m = g_setMap[s];
    if (m) return m;
    if (s.length >= 30) {
        for (NSString *k in g_setMap) {
            if (k.length >= 30 && [s hasPrefix:k]) return g_setMap[k];
        }
    }
    if ([s hasPrefix:@"- Disable Automation notifications:"]) return @"- 禁用自动化通知：自动化运行时不再发送通知\n- 自动化无需确认：所有触发器均可免确认直接运行自动化（注意：邮件和信息触发器不支持）\n- 允许以文件方式导入/导出快捷指令：以文件（.shortcuts 或 .wflow）而非 iCloud 链接导入/导出\n- 敏感动作无需解锁验证：部分操作运行前不再要求解锁。适合在锁屏可运行的自动化中使用。并非对所有敏感操作生效。\n- 隐藏顶部进度横幅：隐藏从主屏图标、辅助触控等运行快捷指令时顶部的进度横幅";
    return nil;
}

// 0.4.51：PSSpecifier 渲染期翻译 + PCSPrefsListController 后处理
static IMP g_origSpecName = NULL, g_origSpecProp = NULL, g_origSetSpecs2 = NULL;
static NSString *ZH_specname_imp(id self, SEL _cmd) {
    @try {
        NSString *o = ((NSString *(*)(id, SEL))g_origSpecName)(self, _cmd);
        NSString *m = ZHMap(o);
        return m ?: o;
    } @catch (id e) { return ((NSString *(*)(id, SEL))g_origSpecName)(self, _cmd); }
}
static id ZH_specprop_imp(id self, SEL _cmd, NSString *key) {
    @try {
        id v = ((id(*)(id, SEL, NSString *))g_origSpecProp)(self, _cmd, key);
        if ([v isKindOfClass:[NSString class]]) {
            NSString *m = ZHMap(v);
            if (m) return m;
        }
        return v;
    } @catch (id e) { return ((id(*)(id, SEL, NSString *))g_origSpecProp)(self, _cmd, key); }
}
static void ZH_setspecs2_imp(id self, SEL _cmd, NSArray *specs) {
    ((void(*)(id, SEL, NSArray *))g_origSetSpecs2)(self, _cmd, specs);
    @try {
        for (id spec in specs) {
            if (![spec isKindOfClass:objc_getClass("PSSpecifier")]) continue;
            for (NSString *key in @[@"name", @"header", @"footerText", @"title", @"label"]) {
                @try {
                    NSString *raw = [spec propertyForKey:key];
                    if (![raw isKindOfClass:[NSString class]]) continue;
                    NSString *m = ZHMap(raw);
                    if (m) {
                        Method mm = class_getInstanceMethod([spec class], sel_registerName("setProperty:forKey:"));
                        if (mm) {
                            void (*sp)(id, SEL, id, NSString *) = (void (*)(id, SEL, id, NSString *))method_getImplementation(mm);
                            sp(spec, sel_registerName("setProperty:forKey:"), m, key);
                        }
                    }
                } @catch (id e) {}
            }
        }
    } @catch (id e) {}
}

#pragma mark - SpringBoard 稳定性层 + 关闭Siri 修复（0.5.3）
static void ZHSBLog(NSString *line) {
    @try {
        NSMutableString *lg = [NSMutableString stringWithContentsOfFile:@"/var/mobile/pczh76_sb.txt" encoding:NSUTF8StringEncoding error:nil] ?: [NSMutableString new];
        [lg appendString:line];
        [lg writeToFile:@"/var/mobile/pczh76_sb.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (id e) {}
}
// 关闭Siri 的 iOS 16.3 可用实现（级联回退）
static void ZHSBDismissSiri(void) {
    Class sac = objc_getClass("SBAssistantController");
    if (!sac) { ZHSBLog(@"[关闭Siri] SBAssistantController 不存在\n"); return; }
    id inst = nil;
    @try { inst = ((id(*)(id, SEL))objc_msgSend)(sac, sel_registerName("sharedInstance")); } @catch (id e) {}
    if (!inst) { ZHSBLog(@"[关闭Siri] sharedInstance 为空\n"); return; }
    for (NSString *selName in @[@"dismissSiri", @"_dismissSiri", @"dismissSiriAnimated:", @"dismissAnimated:", @"dismiss"]) {
        @try {
            SEL ds = sel_registerName(selName.UTF8String);
            if ([inst respondsToSelector:ds]) {
                ((void(*)(id, SEL))objc_msgSend)(inst, ds);
                ZHSBLog([NSString stringWithFormat:@"[关闭Siri] %@ ✓\n", selName]);
                return;
            } else {
                ZHSBLog([NSString stringWithFormat:@"[关闭Siri] %@ 不响应\n", selName]);
            }
        } @catch (id e) { ZHSBLog([NSString stringWithFormat:@"[关闭Siri] %@ 异常: %@\n", selName, e]); }
    }
    ZHSBLog(@"[关闭Siri] 候选选择器全部失败\n");
}
static void ZHSBWrapAndLog(NSString *ident, NSException *e) {
    ZHSBLog([NSString stringWithFormat:@"[捕获] ident=%@ 异常=%@\n", ident, e]);
    if ([ident isKindOfClass:[NSString class]] && [ident containsString:@"dismissSiri"]) ZHSBDismissSiri();
}
// 三种 perform 签名的包装器（逐类捕获原始 IMP）
static void ZHSBHookClass(Class cls, NSString *name) {
    // 1 参
    Method m1 = class_getInstanceMethod(cls, sel_registerName("performActionForIdentifier:"));
    if (m1) {
        IMP orig = method_getImplementation(m1);
        id blk = ^(id slf, id ident) {
            @try { return ((id(*)(id, SEL, id))orig)(slf, sel_registerName("performActionForIdentifier:"), ident); }
            @catch (NSException *e) { ZHSBWrapAndLog(ident, e); return (id)nil; }
        };
        method_setImplementation(m1, imp_implementationWithBlock(blk));
    }
    // 2 参
    Method m2 = class_getInstanceMethod(cls, sel_registerName("performActionForIdentifier:withParameters:"));
    if (m2) {
        IMP orig = method_getImplementation(m2);
        id blk = ^(id slf, id ident, id params) {
            @try { return ((id(*)(id, SEL, id, id))orig)(slf, sel_registerName("performActionForIdentifier:withParameters:"), ident, params); }
            @catch (NSException *e) { ZHSBWrapAndLog(ident, e); return (id)nil; }
        };
        method_setImplementation(m2, imp_implementationWithBlock(blk));
    }
    // 4 参
    Method m4 = class_getInstanceMethod(cls, sel_registerName("performActionForIdentifier:withParameters:success:fail:"));
    if (m4) {
        IMP orig = method_getImplementation(m4);
        id blk = ^(id slf, id ident, id params, id success, id fail) {
            @try { return ((id(*)(id, SEL, id, id, id, id))orig)(slf, sel_registerName("performActionForIdentifier:withParameters:success:fail:"), ident, params, success, fail); }
            @catch (NSException *e) { ZHSBWrapAndLog(ident, e); return (id)nil; }
        };
        method_setImplementation(m4, imp_implementationWithBlock(blk));
    }
}
static void PCZHSBInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            const char *img = NULL;
            for (uint32_t i = 0; i < _dyld_image_count(); i++) {
                const char *n = _dyld_get_image_name(i);
                if (n && strstr(n, "PowercutsActionsPack.dylib")) { img = n; break; }
            }
            if (!img) { ZHSBLog(@"PowercutsActionsPack 镜像未找到\n"); return; }
            unsigned int count = 0;
            const char **names = objc_copyClassNamesForImage(img, &count);
            int hooked = 0;
            for (unsigned int i = 0; i < count; i++) {
                Class cls = objc_getClass(names[i]);
                if (!cls) continue;
                NSString *nm = [NSString stringWithUTF8String:names[i]];
                BOOL isDismiss = [nm.lowercaseString containsString:@"siri"];
                // 只包装 perform 重载的类（全部包装会拖慢无关类）
                if (class_getInstanceMethod(cls, sel_registerName("performActionForIdentifier:withParameters:")) ||
                    class_getInstanceMethod(cls, sel_registerName("performActionForIdentifier:")) ||
                    class_getInstanceMethod(cls, sel_registerName("performActionForIdentifier:withParameters:success:fail:"))) {
                    ZHSBHookClass(cls, nm);
                    hooked++;
                    if (isDismiss) ZHSBLog([NSString stringWithFormat:@"[Siri 类] %@\n", nm]);
                }
            }
            Class sac = objc_getClass("SBAssistantController");
            if (sac) {
                unsigned int mc = 0;
                Method *ml = class_copyMethodList(sac, &mc);
                NSMutableString *ms = [NSMutableString stringWithFormat:@"[SBAssistantController 方法 %u]:", mc];
                for (unsigned int x = 0; x < mc && x < 60; x++) [ms appendFormat:@" %s;", sel_getName(method_getName(ml[x]))];
                if (ml) free(ml);
                ZHSBLog(ms); ZHSBLog(@"\n");
            } else { ZHSBLog(@"[SBAssistantController] 类不存在\n"); }
            ZHSBLog([NSString stringWithFormat:@"== SB 稳定性层就绪: 类 %u, hook %d ==\n", count, hooked]);
        } @catch (id e) {}
    });
}

#pragma mark - 主入口

static void PCZHPrefsInit(void) {
    @try {
        PCZHInitSettingsMap();
        Class pss = objc_getClass("PSSpecifier");
        if (pss) {
            Method nm = class_getInstanceMethod(pss, sel_registerName("name"));
            if (nm && !g_origSpecName) { g_origSpecName = method_getImplementation(nm); method_setImplementation(nm, (IMP)ZH_specname_imp); }
            Method pm = class_getInstanceMethod(pss, sel_registerName("propertyForKey:"));
            if (pm && !g_origSpecProp) { g_origSpecProp = method_getImplementation(pm); method_setImplementation(pm, (IMP)ZH_specprop_imp); }
        }
        Class pcsp = objc_getClass("PCSPrefsListController");
        if (pcsp) {
            Method ms2 = class_getInstanceMethod(pcsp, sel_registerName("setSpecifiers:"));
            if (ms2 && !g_origSetSpecs2) { g_origSetSpecs2 = method_getImplementation(ms2); method_setImplementation(ms2, (IMP)ZH_setspecs2_imp); }
        }
    } @catch (id e) {}
}

#pragma mark - 显示层翻译（UILabel setText，g_lab 精确匹配）
static IMP g_origSetText = NULL;
static void ZH_settext_imp(id self, SEL _cmd, NSString *text) {
    @try {
        if ([text isKindOfClass:[NSString class]] && text.length > 1 && text.length < 40) {
            NSString *m = g_lab[text];
            if ([m isKindOfClass:[NSString class]]) text = m;
        }
    } @catch (id e) {}
    ((void(*)(id, SEL, NSString *))g_origSetText)(self, _cmd, text);
}

static void PCZHDelayedInit(void) {
    NSString *procName = [NSProcessInfo processInfo].processName;
    @try {
        PCZHInitTables();
    } @catch (id e) { return; }

    if ([procName isEqualToString:@"SpringBoard"]) {
        PCZHSBInit();
        return;
    }
    if ([procName isEqualToString:@"Preferences"] || [procName isEqualToString:@"Powercuts"]) {
        PCZHPrefsInit();
        return;
    }
    if (![procName isEqualToString:@"Shortcuts"]) {
        return;
    }

    @try {
        // WFCustomAction：name/descriptionSummary/description（列表+详情）
        Class wcc = objc_getClass("WFCustomAction");
        if (wcc) {
            Method m = class_getInstanceMethod(wcc, sel_registerName("name"));
            if (m && !g_origWCName) { g_origWCName = method_getImplementation(m); method_setImplementation(m, (IMP)ZH_wcname_imp); }
            Method md = class_getInstanceMethod(wcc, sel_registerName("descriptionSummary"));
            if (md && !g_origWCDs) { g_origWCDs = method_getImplementation(md); method_setImplementation(md, (IMP)ZH_dsummary_imp); }
            Method mdd = class_getInstanceMethod(wcc, sel_registerName("description"));
            if (mdd && !g_origWCDesc) { g_origWCDesc = method_getImplementation(mdd); method_setImplementation(mdd, (IMP)ZH_desc_imp); }
        }
        // PCSharedBucketManager 缓存 getter（画布数据源，深度翻译）
        Class pcm = objc_getClass("PCSharedBucketManager");
        if (pcm) {
            Method mg = class_getInstanceMethod(pcm, sel_registerName("registeredCustomActionsCachedData"));
            if (!mg) mg = class_getClassMethod(pcm, sel_registerName("registeredCustomActionsCachedData"));
            if (mg && !g_origCacheGet) { g_origCacheGet = method_getImplementation(mg); method_setImplementation(mg, (IMP)ZH_cacheget_imp); }
        }
        // PCAction 显示接口（名称/描述/摘要）
        Class pss2 = objc_getClass("PCAction");
        if (pss2) {
            const char *pcsels[3] = {"nameForIdentifier:", "descriptionSummaryForIdentifier:", "parameterSummaryForIdentifier:"};
            IMP *imps[3] = {&g_origPCName, &g_origPCDesc, &g_origPCSum};
            IMP imps2[3] = {(IMP)ZH_pcname_imp, (IMP)ZH_pcdesc_imp, (IMP)ZH_pcsum_imp};
            for (int pi = 0; pi < 3; pi++) {
                Method cm = class_getInstanceMethod(pss2, sel_registerName(pcsels[pi]));
                if (!cm) cm = class_getClassMethod(pss2, sel_registerName(pcsels[pi]));
                if (cm && !*imps[pi]) {
                    *imps[pi] = method_getImplementation(cm);
                    method_setImplementation(cm, imps2[pi]);
                }
            }
        }
        // UILabel 显示层兜底（参数标签）
        Class ul = objc_getClass("UILabel");
        if (ul) {
            Method us = class_getInstanceMethod(ul, sel_registerName("setText:"));
            if (us && !g_origSetText) { g_origSetText = method_getImplementation(us); method_setImplementation(us, (IMP)ZH_settext_imp); }
        }
    } @catch (id e) {}
}

%ctor {
    @autoreleasepool {
        PCZHDelayedInit();
    }
}
