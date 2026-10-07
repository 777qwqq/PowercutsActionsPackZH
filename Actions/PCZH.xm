// Powercuts Actions Pack 中文仿编版 Phase 1 — 设备控制类
// identifier 与原版一致，替换官方 Actions Pack 后已有快捷指令绑定不受影响
#import "pczh_api.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>
#import <spawn.h>
#import <signal.h>
#import <unistd.h>

extern char **environ;

#pragma mark - 工具

static void pczh_run(NSString *cmd) {
    if (!cmd.length) return;
    pid_t pid;
    char *argv[] = { (char *)"/bin/sh", (char *)"-c", (char *)cmd.UTF8String, NULL };
    posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, environ);
}

static NSString *jbrootPath(NSString *rel) {
    Dl_info di;
    if (dladdr((void *)jbrootPath, &di) && di.dli_fname) {
        NSString *p = [NSString stringWithUTF8String:di.dli_fname];
        NSRange r = [p rangeOfString:@".jbroot-"];
        if (r.location != NSNotFound) {
            NSString *rest = [p substringFromIndex:r.location + r.length];
            NSRange slash = [rest rangeOfString:@"/"];
            if (slash.location != NSNotFound) {
                NSString *jb = [p substringToIndex:r.location + r.length + slash.location];
                return [jb stringByAppendingString:rel];
            }
        }
    }
    return [@"/var/jb" stringByAppendingString:rel];
}

static id sbSharedInstance(NSString *className) {
    Class c = objc_getClass(className.UTF8String);
    if (!c) return nil;
    SEL s = NSSelectorFromString(@"sharedInstance");
    if (![c respondsToSelector:s]) return nil;
    return ((id(*)(id, SEL))objc_msgSend)(c, s);
}

// ===== Respring 注销 =====
@interface ZHRespringAction : PCAction
@end
@implementation ZHRespringAction
- (void)performActionForIdentifier:(NSString *)identifier {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RespringUT" object:nil];
    sleep(1);
    exit(0);
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"注销"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"注销设备（重启 SpringBoard）。"; }
@end

// ===== Reboot 重启 =====
@interface ZHRebootAction : PCAction
@end
@implementation ZHRebootAction
- (void)performActionForIdentifier:(NSString *)identifier {
    pczh_run(@"/usr/sbin/reboot");
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"重启"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"重启设备。"; }
@end

// ===== GoHome 回主屏幕 =====
@interface ZHGoHomeAction : PCAction
@end
@implementation ZHGoHomeAction
- (void)performActionForIdentifier:(NSString *)identifier {
    id inst = sbSharedInstance(@"SBUIController");
    SEL s = NSSelectorFromString(@"simulateHomeButtonClick");
    if (inst && [inst respondsToSelector:s]) ((void(*)(id, SEL))objc_msgSend)(inst, s);
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"回主屏幕"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"返回主屏幕。"; }
@end

// ===== ShowAppSwitcher 显示多任务 =====
@interface ZHShowAppSwitcherAction : PCAction
@end
@implementation ZHShowAppSwitcherAction
- (void)performActionForIdentifier:(NSString *)identifier {
    id inst = sbSharedInstance(@"SBUIController");
    SEL s = NSSelectorFromString(@"showAppSwitcher:");
    if (inst && [inst respondsToSelector:s]) ((void(*)(id, SEL, BOOL))objc_msgSend)(inst, s, YES);
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"显示多任务"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"显示多任务界面。"; }
@end

// ===== OpenApp 打开应用（带 bundleId 参数） =====
@interface ZHOpenAppAction : PCAction
@end
@implementation ZHOpenAppAction
- (id)parametersDefinitionForIdentifier:(NSString *)identifier {
    return @[ @{ @"key": @"bundleId",
        @"label": @"应用标识符",
        @"type": @"text",
        @"placeholder": @"com.apple.Preferences" } ];
}
- (void)performActionForIdentifier:(NSString *)identifier withParameters:(NSDictionary *)params {
    NSString *bid = params[@"bundleId"];
    if (![bid isKindOfClass:[NSString class]] || bid.length == 0) return;
    id inst = sbSharedInstance(@"SBApplicationController");
    SEL s = NSSelectorFromString(@"launchApplicationWithIdentifier:display:");
    if (inst && [inst respondsToSelector:s]) {
        ((void(*)(id, SEL, id, BOOL))objc_msgSend)(inst, s, bid, NO);
    } else {
        pczh_run([NSString stringWithFormat:@"'%@' -b '%@' >/dev/null 2>&1 &", jbrootPath(@"/usr/bin/uiopen"), bid]);
    }
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"打开应用"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"通过应用标识符打开应用。"; }
@end

// ===== KillApp 结束应用（带 bundleId 参数） =====
@interface ZHKillAppAction : PCAction
@end
@implementation ZHKillAppAction
- (id)parametersDefinitionForIdentifier:(NSString *)identifier {
    return @[ @{ @"key": @"bundleId",
        @"label": @"应用标识符",
        @"type": @"text",
        @"placeholder": @"com.apple.Preferences" } ];
}
- (void)performActionForIdentifier:(NSString *)identifier withParameters:(NSDictionary *)params {
    NSString *bid = params[@"bundleId"];
    if (![bid isKindOfClass:[NSString class]] || bid.length == 0) return;
    id inst = sbSharedInstance(@"FBProcessManager");
    SEL s = NSSelectorFromString(@"terminateApplicationWithBundleID:");
    if (inst && [inst respondsToSelector:s]) {
        ((void(*)(id, SEL, id))objc_msgSend)(inst, s, bid);
        return;
    }
    id ac = sbSharedInstance(@"SBApplicationController");
    SEL gs = NSSelectorFromString(@"applicationWithDisplayIdentifier:");
    if (ac && [ac respondsToSelector:gs]) {
        id app = ((id(*)(id, SEL, id))objc_msgSend)(ac, gs, bid);
        SEL ps = NSSelectorFromString(@"pid");
        if (app && [app respondsToSelector:ps]) {
            pid_t pid = ((int(*)(id, SEL))objc_msgSend)(app, ps);
            if (pid > 0) kill(pid, SIGKILL);
        }
    }
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"结束应用"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"结束指定标识符的应用。"; }
@end

// ===== UICache 重建图标缓存 =====
@interface ZHUICacheAction : PCAction
@end
@implementation ZHUICacheAction
- (void)performActionForIdentifier:(NSString *)identifier {
    pczh_run([NSString stringWithFormat:@"'%@' -a >/dev/null 2>&1 &", jbrootPath(@"/usr/bin/uicache")]);
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"重建图标缓存"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"运行 uicache 重建图标缓存。"; }
@end

// ===== WakeScreen 唤醒屏幕 =====
@interface ZHWakeScreenAction : PCAction
@end
@implementation ZHWakeScreenAction
- (void)performActionForIdentifier:(NSString *)identifier {
    Class c = objc_getClass("BKSDisplayManager");
    if (!c) return;
    SEL si = NSSelectorFromString(@"sharedInstance");
    if (![c respondsToSelector:si]) return;
    id inst = ((id(*)(id, SEL))objc_msgSend)(c, si);
    SEL wake = NSSelectorFromString(@"wake");
    if ([inst respondsToSelector:wake]) ((void(*)(id, SEL))objc_msgSend)(inst, wake);
}
- (NSString *)nameForIdentifier:(NSString *)identifier { return @"唤醒"; }
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier { return @"唤醒屏幕。"; }
@end

#pragma mark - 注册

%ctor {
    @autoreleasepool {
        PowercutsManager *m = [PowercutsManager sharedInstance];
               [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.respring" action:[ZHRespringAction new]];
               [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.reboot" action:[ZHRebootAction new]];
        [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.goHome" action:[ZHGoHomeAction new]];
        [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.showAppSwitcher" action:[ZHShowAppSwitcherAction new]];
        [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.openApp" action:[ZHOpenAppAction new]];
        [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.killApp" action:[ZHKillAppAction new]];
        [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.uiCache" action:[ZHUICacheAction new]];
        [m registerActionWithIdentifier:@"com.anthopak.powercuts.action.wakeScreen" action:[ZHWakeScreenAction new]];
    }
}
