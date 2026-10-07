// 0.3.0-probe: 官方 ActionsPack 汉化前侦察。只读不写不 hook，绝不崩
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void mark(NSString *name, NSString *content) {
    @try {
        NSString *proc = [[NSProcessInfo processInfo] processName];
        proc = [proc stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        NSString *path = [@"/var/mobile/Documents/" stringByAppendingFormat:@"pczh30_%@_%@.txt", proc, name];
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (id e) {}
}

%ctor {
    @try {
        // 1. 官方包动作类清单（PCAction 子类）
        NSMutableString *cls = [NSMutableString string];
        int num = objc_getClassList(NULL, 0);
        if (num > 0) {
            Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * num);
            objc_getClassList(classes, num);
            Class pcAction = objc_getClass("PCAction");
            for (int i = 0; i < num; i++) {
                if (classes[i] && pcAction && class_getSuperclass(classes[i]) == pcAction) {
                    [cls appendFormat:@"%@\n", NSStringFromClass(classes[i])];
                }
            }
            free(classes);
        }
        mark(@"subclasses", cls);
    } @catch (id e) {}
    @try {
        // 2. 注册表内容
        id m = [PowercutsManager sharedInstance];
        id reg = [m registeredCustomActions];
        mark(@"registry", reg ? [NSString stringWithFormat:@"%@", reg] : @"nil");
    } @catch (NSException *e) {
        mark(@"reg_FAILED", [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }
}
