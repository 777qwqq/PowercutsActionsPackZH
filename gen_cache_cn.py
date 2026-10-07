#!/usr/bin/env python3
# 生成中文版 Powercuts 动作缓存 plist
import json, plistlib

raw = json.load(open('/tmp/raw_actions.json'))

# identifier短名 → 中文名
NAMES = {
 'audioBalance':'音量平衡','autoTouchRunFile':'运行 LUA 文件','connectToBluetoothDevice':'连接/断开蓝牙设备',
 'deleteGlobalVariable':'删除全局变量','dismissSiri':'关闭 Siri','donate':'支持开发者',
 'getAllInstalledApps':'获取全部已装应用','getAppBadgeCount':'获取应用角标数','getAppNameFromIdentifier':'获取应用信息',
 'getBluetoothDeviceBattery':'获取蓝牙设备电量','getBluetoothDevices':'获取蓝牙设备','getCurrentApp':'获取当前应用',
 'getFileContent':'获取文本文件内容','getFilesFromFolderPath':'获取文件夹内容','getGlobalVariable':'获取全局变量',
 'getIsDeviceLocked':'获取设备锁定状态','getNowPlayingApp':'获取正在播放的应用','getPressedButtons':'获取按下的按键',
 'getWorkflowRunSource':'获取运行来源','goHome':'回到主屏幕','goToHomeScreenPage':'跳转主屏幕页',
 'killApp':'结束应用','ldRestart':'LD 重启','lock':'锁定设备','openApp':'打开应用','quickSwitch':'快速开关',
 'removeNotifications':'移除匹配的通知','respring':'注销','runCommand':'运行命令','safeMode':'安全模式',
 'sendDistributedNotification':'发送分布式通知','sendNotification':'发送通知','setAppBadgeCount':'设置应用角标',
 'setGlobalVariable':'设置全局变量','showAppSwitcher':'显示多任务','uiCache':'重建图标缓存',
 'unlock':'密码解锁','wakeScreen':'唤醒屏幕',
}
DESCS = {
 'audioBalance':'设置左右声道音量平衡。左为 -1，右为 1。默认 0。',
 'autoTouchRunFile':'运行 AutoTouch 的 LUA 脚本。',
 'connectToBluetoothDevice':'连接或断开指定名称的蓝牙设备。',
 'deleteGlobalVariable':'删除指定键的全局变量值。',
 'dismissSiri':'关闭 Siri 界面。适合配合 Siri 使用的快捷指令：先关闭 Siri 再执行其他动作。',
 'donate':'运行我！运行我！',
 'getAllInstalledApps':'返回设备上所有已安装应用的标识符。\n当前返回值为文本（暂不支持数组输出），可用“拆分文本”按换行拆分。',
 'getAppBadgeCount':'获取指定应用当前的角标数。',
 'getAppNameFromIdentifier':'根据标识符返回应用信息。',
 'getBluetoothDeviceBattery':'返回指定名称蓝牙设备的电量。',
 'getBluetoothDevices':'返回已连接或已配对的蓝牙设备列表。\n当前返回值为文本，可用“拆分文本”按换行拆分。',
 'getCurrentApp':'返回前台应用标识符。',
 'getFileContent':'以文本形式获取任意文件的内容。',
 'getFilesFromFolderPath':'获取文件夹内的所有文件和子文件夹。\n当前返回值为文本，可用“拆分文本”按换行拆分。',
 'getGlobalVariable':'按键读取全局变量的值。',
 'getIsDeviceLocked':'设备已锁定返回 Yes，未锁定返回 No。',
 'getNowPlayingApp':'返回正在播放媒体的应用标识符。',
 'getPressedButtons':'返回当前被按住的按键，可配合“如果”构建条件。\n可能的值：电源键、音量+、音量-。\n当前返回值为文本。',
 'getWorkflowRunSource':'返回快捷指令的运行来源。\n可能的值：快捷指令 App、Siri、小组件、主屏幕图标、自动化等。',
 'goHome':'回到主屏幕。',
 'goToHomeScreenPage':'将主屏幕滚动到指定页（从 1 开始）。',
 'killApp':'按标识符结束已安装的应用。',
 'ldRestart':'运行 LDRestart 命令。需要 smokin1337 的 ldrestarthelper 包。',
 'lock':'锁定设备。',
 'openApp':'按标识符打开已安装的应用。',
 'quickSwitch':'创建快捷指令时快速开关某些动作。输出 开(Yes)/关(No)，配合“如果”使用。',
 'removeNotifications':'移除匹配过滤条件（应用标识符或关键词）的通知。',
 'respring':'注销设备（重启 SpringBoard）。',
 'runCommand':'运行系统命令。',
 'safeMode':'使设备进入安全模式。',
 'sendDistributedNotification':'向 NSDistributedNotificationCenter 发送通知（开发者用）。',
 'sendNotification':'以指定应用的名义发送推送通知，横幅使用该应用的图标和名称。\n需要 CokePokes 的 libnotifications 插件。',
 'setAppBadgeCount':'设置指定应用的角标数。',
 'setGlobalVariable':'为指定键的全局变量设置值。',
 'showAppSwitcher':'以动画方式打开应用切换器。',
 'uiCache':'运行 UICache 命令。',
 'unlock':'使用传入的密码解锁设备。请谨慎使用，这可能带来安全风险。',
 'wakeScreen':'唤醒屏幕（模拟轻点唤醒，适合自动化或 SSH 场景）。',
}
SUMMARIES = {
 'audioBalance':'音量平衡设为 ${balanceValue}',
 'connectToBluetoothDevice':'${connect}名为 ${deviceName} 的蓝牙设备',
 'deleteGlobalVariable':'删除键为 ${key} 的全局变量',
 'getAppBadgeCount':'获取标识符为 ${bundleId} 的应用角标数',
 'getAppNameFromIdentifier':'获取标识符为 ${bundleId} 的应用的 ${informationType}',
 'getBluetoothDeviceBattery':'获取名为 ${deviceName} 的蓝牙设备电量',
 'getGlobalVariable':'获取键为 ${key} 的全局变量值',
 'goToHomeScreenPage':'跳到主屏幕第 ${pageIndex} 页',
 'killApp':'结束标识符为 ${bundleId} 的应用',
 'openApp':'打开标识符为 ${bundleId} 的应用',
 'setAppBadgeCount':'将标识符为 ${bundleId} 的应用角标设为 ${badgeCount}',
 'setGlobalVariable':'将键为 ${key} 的全局变量设为 ${value}',
 'unlock':'使用密码 ${password} 解锁设备',
}
LABELS = {
 'Balance value':'平衡值','File Path':'文件路径','Device name':'设备名称','key':'键名',
 'bundleId':'应用标识符','informationType':'信息类型','type':'类型','pageIndex':'页码',
 'badgeCount':'角标数','value':'值','state':'状态','notificationName':'通知名称',
 'password':'密码','connect':'操作',
}

out_actions = {}
for ident, a in raw.items():
    short = ident.split('.')[-1]
    d = {}
    if a['name'] is not None:
        d['name'] = NAMES.get(short, a['name'])
    if a['desc'] is not None:
        d['descriptionSummary'] = DESCS.get(short, a['desc'])
    if a['summary']:
        d['parameterSummary'] = SUMMARIES.get(short, a['summary'])
    # 参数 Label/Placeholder 中文化
    if a['params']:
        np = []
        for p in a['params']:
            p = dict(p)
            if p.get('Label') in LABELS: p['Label'] = LABELS[p['Label']]
            np.append(p)
        d['parameters'] = np
    out_actions[ident] = d

# dataPrefs 顶层结构：{"registeredActionsData.plist": <动作字典>}
dataPrefs = {'registeredActionsData.plist': out_actions}
plistlib.dump(dataPrefs, open('/tmp/pczh_cache_cn.plist', 'wb'), fmt=plistlib.FMT_BINARY)
print('生成完成，动作数:', len(out_actions))
