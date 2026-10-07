// PCZH SB 执行器 v2.0 — 驻留 SpringBoard，响应 TrollCuts 动作的 Darwin 通知
// 与 libpowercuts 完全解耦：纯通知监听，零注册，零崩溃风险
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

static id sbShared(NSString *cls) {
    Class c = objc_getClass(cls.UTF8String);
    if (!c) return nil;
    SEL s = sel_registerName("sharedInstance");
    if (!((id)c respondsToSelector:s)) return nil;
    return ((id(*)(id, SEL))objc_msgSend)((id)c, s);
}

static void runCommand(int code) {
    @try {
        if (code == 1) {
            // 回主屏幕
            id c = sbShared("SBUIController");
            SEL s = NSSelectorFromString(@"simulateHomeButtonClick");
            if (c && [c respondsToSelector:s]) ((void(*)(id,SEL))objc_msgSend)(c, s);
        } else if (code == 2) {
            // 显示多任务
            id c = sbShared("SBUIController");
            SEL s = NSSelectorFromString(@"showAppSwitcher:");
            if (c && [c respondsToSelector:s]) ((void(*)(id,SEL,BOOL))objc_msgSend)(c, s, YES);
        } else if (code == 3) {
            // 结束应用: bundleId 从命令文件读
            NSString *bid = [NSString stringWithContentsOfFile:@"/var/mobile/Documents/pczh_cmd.txt" encoding:NSUTF8StringEncoding error:nil];
            if (!bid.length) return;
            id pm = sbShared("FBProcessManager");
            SEL s = NSSelectorFromString(@"terminateApplicationWithBundleID:");
            if (pm && [pm respondsToSelector:s]) {
                ((void(*)(id,SEL,id))objc_msgSend)(pm, s, bid);
                return;
            }
            id ac = sbShared("SBApplicationController");
            SEL gs = NSSelectorFromString(@"applicationWithDisplayIdentifier:");
            if (ac && [ac respondsToSelector:gs]) {
                id app = ((id(*)(id,SEL,id))objc_msgSend)(ac, gs, bid);
                SEL ps = NSSelectorFromString(@"pid");
                if (app && [app respondsToSelector:ps]) {
                    pid_t pid = ((pid_t(*)(id,SEL))objc_msgSend)(app, ps);
                    if (pid > 0) kill(pid, SIGKILL);
                }
            }
        }
    } @catch (id e) {}
}

static void pczh_cb(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *n = (__bridge NSString *)name;
    if ([n isEqualToString:@"com.moss.pczh.home"]) runCommand(1);
    else if ([n isEqualToString:@"com.moss.pczh.appswitcher"]) runCommand(2);
    else if ([n isEqualToString:@"com.moss.pczh.kill"]) runCommand(3);
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, pczh_cb,
        CFSTR("com.moss.pczh.home"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, pczh_cb,
        CFSTR("com.moss.pczh.appswitcher"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, pczh_cb,
        CFSTR("com.moss.pczh.kill"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
