// 0.3.5-probe: 进程名独立标记，沙盒 tmp 优先落盘
#import "pczh_api.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSMutableString *g_report;

static void flushReport(void) {
    NSString *proc = [[NSProcessInfo processInfo] processName];
    proc = [proc stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *name = [NSString stringWithFormat:@"pczh33_%@_report.txt", proc];
    @try { [g_report writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil]; } @catch (id e) {}
    @try { [g_report writeToFile:[@"/var/mobile/Documents/" stringByAppendingString:name] atomically:YES encoding:NSUTF8StringEncoding error:nil]; } @catch (id e) {}
}

%ctor {
    g_report = [NSMutableString string];
    NSString *proc = [[NSProcessInfo processInfo] processName];
    [g_report appendFormat:@"进程=%@ pid=%d bundle=%@ time=%@\n", proc, getpid(), [NSBundle mainBundle].bundleIdentifier, [NSDate date]];

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
    } @catch (id e) {}

    @try {
        Class bucket = objc_getClass("PCSharedBucketManager");
        id inst = bucket ? ((id(*)(id, SEL))objc_msgSend)((id)bucket, sel_registerName("sharedInstance")) : nil;
        SEL ms = sel_registerName("registeredCustomActionsCachedData");
        if (inst && [inst respondsToSelector:ms]) {
            id v = ((id(*)(id, SEL))objc_msgSend)(inst, ms);
            [g_report appendFormat:@"\n==== 注册表 ====\n%@\n", v];
        } else {
            [g_report appendFormat:@"\n==== 注册表 ====\nsharedInstance=%@ 方法不可用\n", inst];
        }
    } @catch (NSException *e) {
        [g_report appendFormat:@"\n==== 注册表异常 ====\n%@\n", e.reason];
    }

    flushReport();
    // 注册表可能延迟，延迟 3 秒再刷一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
        @try {
            id inst = ((id(*)(id, SEL))objc_msgSend)(objc_getClass("PCSharedBucketManager"), sel_registerName("sharedInstance"));
            id v = ((id(*)(id, SEL))objc_msgSend)(inst, sel_registerName("registeredCustomActionsCachedData"));
            [g_report appendFormat:@"\n==== 注册表(3秒后) ====\n%@\n", v];
        } @catch (id e) {}
        flushReport();
    });
}
