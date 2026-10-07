// 0.3.2-probe: 多路径写标记 + 错误捕获，分辨"未注入"vs"沙盒拦截"
#import "pczh_api.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSMutableString *g_report;

static void tryWrite(NSString *path, NSString *content, NSMutableString *log) {
    NSError *err = nil;
    BOOL ok = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    [log appendFormat:@"%@ → %@%@%@%@\n", path,
        ok ? @"成功" : @"失败",
        err ? @" err: " : @"", err ? err.localizedDescription : @"",
        err ? [NSString stringWithFormat:@" [%@]", err.domain] : @""];
}

%ctor {
    g_report = [NSMutableString string];
    NSString *proc = [[NSProcessInfo processInfo] processName];
    [g_report appendFormat:@"进程=%@ pid=%d time=%@\n", proc, getpid(), [NSDate date]];

    // 沙盒内 tmp（快捷指令进程一定能写）
    tryWrite([NSTemporaryDirectory() stringByAppendingPathComponent:@"pczh32_report.txt"], g_report, g_report);
    // 常规路径
    tryWrite(@"/var/mobile/Documents/pczh32_report.txt", g_report, g_report);
    tryWrite(@"/var/mobile/Library/Preferences/com.moss.pczh.report", g_report, g_report);

    // 全类扫描（只在成功落盘的路径尽力而为）
    @try {
        NSMutableString *cls = [NSMutableString string];
        int num = objc_getClassList(NULL, 0);
        Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * num);
        objc_getClassList(classes, num);
        for (int i = 0; i < num; i++) {
            NSString *nm = NSStringFromClass(classes[i]);
            if ([nm hasPrefix:@"PC"] || [nm containsString:@"Action"]) {
                Class sp = class_getSuperclass(classes[i]);
                [cls appendFormat:@"%@ ← %@\n", nm, sp ? NSStringFromClass(sp) : @"(nil)"];
            }
        }
        free(classes);
        [g_report appendFormat:@"\n==== 类扫描 ====\n%@\n", cls];
        [g_report writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pczh32_report.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [g_report writeToFile:@"/var/mobile/Documents/pczh32_report.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (id e) {}

    @try {
        Class bucket = objc_getClass("PCSharedBucketManager");
        id inst = bucket ? ((id(*)(id, SEL))objc_msgSend)((id)bucket, sel_registerName("sharedInstance")) : nil;
        SEL ms = sel_registerName("registeredCustomActionsCachedData");
        if (inst && [inst respondsToSelector:ms]) {
            id v = ((id(*)(id, SEL))objc_msgSend)(inst, ms);
            [g_report appendFormat:@"\n==== 注册表 ====\n%@\n", v];
            [g_report writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"pczh32_report.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [g_report writeToFile:@"/var/mobile/Documents/pczh32_report.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (id e) {}
}
