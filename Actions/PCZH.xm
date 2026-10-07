// 0.1.4-probe2: 每进程独立标记 + dump 共享缓存内存状态 + 枚举缓存文件候选路径
#import "pczh_api.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

static NSString *jbPrefix(void) {
    Dl_info di;
    if (dladdr((void *)jbPrefix, &di) && di.dli_fname) {
        NSString *p = [NSString stringWithUTF8String:di.dli_fname];
        NSRange r = [p rangeOfString:@".jbroot-"];
        if (r.location != NSNotFound) return [p substringToIndex:r.location + r.length];
    }
    return @"";
}

static void mark(NSString *name, NSString *content) {
    @try {
        NSString *proc = [[NSProcessInfo processInfo] processName];
        proc = [proc stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        NSString *path = [@"/var/mobile/Documents/" stringByAppendingFormat:@"pczh14_%@_%@.txt", proc, name];
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
    NSString *proc = [[NSProcessInfo processInfo] processName];
    @try {
        mark(@"loaded", [NSString stringWithFormat:@"pid=%d", getpid()]);
    } @catch (id e) {}
    @try {
        id m = [PCSharedBucketManager defaultManager];
        id prefs = [m dataPrefs];
        mark(@"dataPrefs", prefs ? [NSString stringWithFormat:@"%@\n---\n%@", NSStringFromClass([prefs class]), prefs] : @"dataPrefs=nil");
    } @catch (NSException *e) {
        mark(@"bucket_FAILED", [NSString stringWithFormat:@"%@: %@\n%@", e.name, e.reason, e.callStackSymbols]);
    }
    @try {
        id m2 = [PowercutsManager sharedInstance];
        [m2 registerActionWithIdentifier:@"com.moss.powercuts.probe" action:[ZHProbeAction new]];
        mark(@"registered", @"OK");
    } @catch (NSException *e) {
        mark(@"register_FAILED", [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }
    @try {
        NSMutableString *files = [NSMutableString string];
        NSArray *cands = @[
            @"/var/mobile/Library/Preferences/com.anthopak.powercuts.registeredActionsData.plist",
            [jbPrefix() stringByAppendingString:@"/var/mobile/Library/Preferences/com.anthopak.powercuts.registeredActionsData.plist"],
            @"/var/mobile/Library/Preferences/com.anthopak.powercuts.plist",
            [jbPrefix() stringByAppendingString:@"/var/mobile/Library/Preferences/com.anthopak.powercuts.plist"],
        ];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *p in cands) {
            BOOL ex = [fm fileExistsAtPath:p];
            [files appendFormat:@"%@ → %@\n", p, ex ? @"存在" : @"无"];
        }
        // 枚举 Preferences 里所有 powercuts 相关文件
        NSArray *all = [fm contentsOfDirectoryAtPath:@"/var/mobile/Library/Preferences" error:nil];
        for (NSString *f in all)
            if ([f.lowercaseString containsString:@"powercuts"] || [f.lowercaseString containsString:@"anthopak"])
                [files appendFormat:@"[Prefs] %@\n", f];
        mark(@"files", files);
    } @catch (id e) {}
}
