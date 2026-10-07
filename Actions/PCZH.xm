// 0.1.3-probe: 全链路文件探针。绝不崩 SpringBoard（全程 try/catch，不依赖 libpowercuts 存活）
#import "pczh_api.h"
#import <Foundation/Foundation.h>

static NSString *markerPath(NSString *name) {
    return [@"/var/mobile/Documents/" stringByAppendingFormat:@"pczh_%@.txt", name];
}
static void mark(NSString *name, NSString *content) {
    @try {
        [content writeToFile:markerPath(name) atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    mark(@"1_loaded", [NSString stringWithFormat:@"pid=%d process=%@ time=%@", getpid(), [[NSProcessInfo processInfo] processName], [NSDate date]]);

    @try {
        id m = [PowercutsManager sharedInstance];
        mark(@"2_manager", m ? [NSString stringWithFormat:@"manager=%@ class=%@", m, NSStringFromClass([m class])] : @"manager=nil");
        [[PowercutsManager sharedInstance] registerActionWithIdentifier:@"com.moss.powercuts.probe" action:[ZHProbeAction new]];
        mark(@"3_registered", @"register 成功返回");
    } @catch (NSException *e) {
        mark(@"3_register_FAILED", [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }

    // 缓存文件是否被 libpowercuts 写出
    NSString *cache = @"/var/mobile/Library/Preferences/com.anthopak.powercuts.registeredActionsData.plist";
    mark(@"4_cache", [[NSFileManager defaultManager] fileExistsAtPath:cache] ? @"缓存文件存在" : @"缓存文件不存在");
}
