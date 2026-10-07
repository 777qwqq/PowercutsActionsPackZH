#!/usr/bin/env python3
# 重建 PCZH.xm 完整 38 条映射表
import re

P='/home/z/my-project/pczh_actions/Actions/PCZH.xm'
s=open(P).read()

# identifier短名 → [中文名, 中文描述, 中文参数摘要]
T={
 'audioBalance':['音量平衡','设置左右声道音量平衡。左为 -1，右为 1。默认 0。','音量平衡设为 ${balanceValue}'],
 'autoTouchRunFile':['运行 LUA 文件','运行 AutoTouch 的 LUA 脚本。',''],
 'connectToBluetoothDevice':['连接/断开蓝牙设备','连接或断开指定名称的蓝牙设备。','${connect}名为 ${deviceName} 的蓝牙设备'],
 'deleteGlobalVariable':['删除全局变量','删除指定键的全局变量值。','删除键为 ${key} 的全局变量'],
 'dismissSiri':['关闭 Siri','关闭 Siri 界面。适用于配合 Siri 使用的快捷指令：先关闭 Siri 再执行其他动作。',''],
 'donate':['支持开发者','运行我！运行我！',''],
 'getAllInstalledApps':['获取全部已装应用','返回设备上所有已安装应用的标识符。当前返回值为文本（暂不支持数组输出），可用"拆分文本"以换行分隔拆分。',''],
 'getAppBadgeCount':['获取应用角标数','获取指定应用当前的角标数。','获取标识符为 ${bundleId} 的应用角标数'],
 'getAppNameFromIdentifier':['获取应用信息','根据标识符返回已安装应用的信息。','获取标识符为 ${bundleId} 的应用的 ${informationType}'],
 'getBluetoothDeviceBattery':['获取蓝牙设备电量','返回指定名称蓝牙设备的电量。','获取名为 ${deviceName} 的蓝牙设备电量'],
 'getBluetoothDevices':['获取蓝牙设备','返回已连接或已配对的蓝牙设备。当前返回值为文本（暂不支持数组输出），可用"拆分文本"以换行分隔拆分。','获取${type}的蓝牙设备'],
 'getCurrentApp':['获取当前应用','返回当前前台应用的标识符。',''],
 'getFileContent':['获取文本文件内容','以文本形式获取任意文件的内容。',''],
 'getFilesFromFolderPath':['获取文件夹内容','获取文件夹内的所有文件与子文件夹。当前返回值为文本（暂不支持数组输出）。',''],
 'getGlobalVariable':['获取全局变量','按键读取全局变量的值。','获取键为 ${key} 的全局变量值'],
 'getIsDeviceLocked':['获取设备锁定状态','设备已锁定时返回"是"，否则返回"否"。',''],
 'getNowPlayingApp':['获取正在播放的应用','返回正在播放媒体的应用标识符。',''],
 'getPressedButtons':['获取按下的按键','返回当前所有被按住的按键，可用于构建条件。可能的值：电源键、音量+、音量-。当前返回值为文本。',''],
 'getWorkflowRunSource':['获取运行来源','返回快捷指令的运行来源。可能的值：快捷指令 App、Siri、小组件、主屏幕图标、自动化等。',''],
 'goHome':['回到主屏幕','返回主屏幕。',''],
 'goToHomeScreenPage':['跳转主屏幕页','将主屏幕滚动到指定页（从 1 开始）。','跳到主屏幕第 ${pageIndex} 页'],
 'killApp':['结束应用','按标识符结束已安装的应用。','结束标识符为 ${bundleId} 的应用'],
 'ldRestart':['LD 重启','运行 LDRestart 命令。需要 ldrestarthelper 包。',''],
 'lock':['锁定设备','锁定设备。',''],
 'openApp':['打开应用','按标识符打开已安装的应用。','打开标识符为 ${bundleId} 的应用'],
 'quickSwitch':['快速开关','创建快捷指令时快速停用某些动作的开关。输出开（是）/关（否），配合"如果"动作使用。','快速开关 - ${state}'],
 'removeNotifications':['移除匹配的通知','移除匹配过滤条件（应用标识符或关键词）的通知。',''],
 'respring':['注销','注销设备（重启 SpringBoard）。',''],
 'runCommand':['运行命令','以 root 身份运行系统命令。',''],
 'safeMode':['安全模式','使设备进入安全模式。',''],
 'sendDistributedNotification':['发送分布式通知','向 NSDistributedNotificationCenter 发送通知（面向开发者）。','发送名为 ${notificationName} 的分布式通知'],
 'sendNotification':['发送通知','以指定应用的名义向设备发送推送通知，横幅使用该应用的图标和名称。需要 libnotifications 插件。',''],
 'setAppBadgeCount':['设置应用角标','设置指定应用的角标数。','将标识符为 ${bundleId} 的应用角标设为 ${badgeCount}'],
 'setGlobalVariable':['设置全局变量','为指定键的全局变量设置值。','将键为 ${key} 的全局变量设为 ${value}'],
 'showAppSwitcher':['显示多任务','以动画方式打开应用切换器。',''],
 'uiCache':['重建图标缓存','运行 UICache 命令。',''],
 'unlock':['密码解锁','使用传入的密码解锁设备。请谨慎使用，这可能带来安全风险。','使用密码 ${password} 解锁设备'],
 'wakeScreen':['唤醒屏幕','唤醒屏幕（模拟轻点唤醒，适合自动化或 SSH 场景）。',''],
}

def oc(x): return '@"'+x.replace('\\','\\\\').replace('"','\\"')+'"'
lines=[]
for k,(n,d,su) in T.items():
    full='com.anthopak.powercuts.action.'+k
    lines.append(f'            @"{full}": @{{ @"n": {oc(n)}, @"d": {oc(d)}, @"s": {oc(su)} }},')
block='g_tr = @{\n'+'\n'.join(lines)+'\n        };'

# 替换 g_tr = @{ ... }; 块
m=re.search(r'g_tr = @\{.*?\n        \};', s, re.S)
assert m, 'g_tr block not found'
s=s[:m.start()]+block+s[m.end():]

# 参数 Label 映射（若 g_lab 块缺失或不全则重建）
lab={'Balance value':'平衡值','File Path':'文件路径','Device name':'设备名称','key':'键名','bundleId':'应用标识符',
     'informationType':'信息类型','type':'类型','pageIndex':'页码','badgeCount':'角标数','value':'值',
     'state':'状态','notificationName':'通知名称','password':'密码','connect':'操作',
     'Label':'标签','Name':'名称','Password':'密码','Filter':'过滤条件'}
lablines=[f'            {oc(k)}: {oc(v)},' for k,v in lab.items()]
labblock='g_lab = @{\n'+'\n'.join(lablines)+'\n        };'
m=re.search(r'g_lab = @\{.*?\n        \};', s, re.S)
if m: s=s[:m.start()]+labblock+s[m.end():]
else:
    s=s.replace('g_tr = @{', labblock+';\n        g_tr = @{',1) if False else s
    # g_lab 可能以其他形式存在，直接在 g_tr 后插入
    s=s.replace(block, block.replace('};','};',1),1)
open(P,'w').write(s)
print('table rebuilt:',len(T),'entries')
