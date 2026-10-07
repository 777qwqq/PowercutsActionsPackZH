// 0.1.5-probe3: dump registeredCustomActions 全量结构 + 自适应找 PCSharedBucketManager 单例
#import "pczh_api.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void mark(NSString *name, NSString *content) {
    @try {
        NSString *proc = [[NSProcessInfo processInfo] processName];
        proc = [proc stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        NSString *path = [@"/var/mobile/Documents/" stringByAppendingFormat:@"pczh15_%@_%@.txt", proc, name];
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (id e) {}
}

@interface ZHProbeAction : PCAction
@end
@implementation ZHProbeAction
-(void) performActionForIdentifier:(NSString*)identifier {}
-(NSString*) nameForIdentifier:(NSString*)identifier { return @"PCZH 探针"; }
-(NSString*) descriptionSummaryForIdentifier:(NSString*)identifier { return @"诊断用。"; }
@end

%ctor {
    @try {
        id m = [PowercutsManager sharedInstance];
        [m registerActionWithIdentifier:@"com.moss.powercuts.probe" action:[ZHProbeAction new]];
        id reg = [m registeredCustomActions];
        mark(@"registry", reg ? [NSString stringWithFormat:@"%@\n%@" , NSStringFromClass([reg class]), reg] : @"nil");
    } @catch (NSException *e) {
        mark(@"reg_FAILED", [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }
    @try {
        Class cls = objc_getClass("PCSharedBucketManager");
        NSMutableString *out = [NSMutableString string];
        for (NSString *gn in @[@"defaultManager", @"sharedInstance", @"sharedBucketManager", @"sharedManager"]) {
            SEL s = NSSelectorFromString(gn);
            BOOL ok = cls && [(id)cls respondsToSelector:s];
            [out appendFormat:@"%@ → %d\n", gn, ok];
            if (ok) {
                id inst = ((id(*)(id, SEL))objc_msgSend)((id)cls, s);
                [out appendFormat:@"实例: %@\n", inst];
                SEL dp = NSSelectorFromString(@"dataPrefs");
                if (inst && [inst respondsToSelector:dp]) {
                    id prefs = ((id(*)(id, SEL))objc_msgSend)(inst, dp);
                    [out appendFormat:@"dataPrefs(%@): %@\n", NSStringFromClass([prefs class]), prefs];
                }
                break;
            }
        }
        mark(@"bucket", out);
    } @catch (NSException *e) {
        mark(@"bucket_FAILED", [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }
}
