// 0.3.1-probe: 修正归属 + 深扫子类 + 自适应找 Bucket 单例
#import "pczh_api.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void mark(NSString *name, NSString *content) {
    @try {
        NSString *proc = [[NSProcessInfo processInfo] processName];
        proc = [proc stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        NSString *path = [@"/var/mobile/Documents/" stringByAppendingFormat:@"pczh31_%@_%@.txt", proc, name];
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (id e) {}
}

%ctor {
    // 1. 全类扫描: 所有名字含 Action 的类及其父类链
    @try {
        NSMutableString *cls = [NSMutableString string];
        int num = objc_getClassList(NULL, 0);
        Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * num);
        objc_getClassList(classes, num);
        for (int i = 0; i < num; i++) {
            NSString *nm = NSStringFromClass(classes[i]);
            if ([nm hasPrefix:@"PC"] || [nm containsString:@"Action"]) {
                Class superCls = class_getSuperclass(classes[i]);
                [cls appendFormat:@"%@  ←  %@\n", nm, superCls ? NSStringFromClass(superCls) : @"(nil)"];
            }
        }
        free(classes);
        mark(@"classes", cls);
    } @catch (id e) {}
    // 2. Bucket 单例自适应 + 注册表
    @try {
        Class bucket = objc_getClass("PCSharedBucketManager");
        NSMutableString *out = [NSMutableString string];
        for (NSString *gn in @[@"sharedBucketManager", @"defaultManager", @"sharedInstance", @"sharedManager"]) {
            SEL s = NSSelectorFromString(gn);
            if (bucket && [(id)bucket respondsToSelector:s]) {
                id inst = ((id(*)(id, SEL))objc_msgSend)((id)bucket, s);
                [out appendFormat:@"单例方法: %@ → %@\n", gn, inst];
                for (NSString *mn in @[@"registeredCustomActions", @"registeredCustomActionsCachedData", @"dataPrefs"]) {
                    SEL ms = NSSelectorFromString(mn);
                    if (inst && [inst respondsToSelector:ms]) {
                        id v = ((id(*)(id, SEL))objc_msgSend)(inst, ms);
                        [out appendFormat:@"\n[%@]:\n%@\n", mn, v];
                    } else {
                        [out appendFormat:@"[%@] 无此方法\n", mn];
                    }
                }
                break;
            } else {
                [out appendFormat:@"%@ 不可用\n", gn];
            }
        }
        mark(@"bucket", out);
    } @catch (NSException *e) {
        mark(@"bucket_FAILED", [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }
}
