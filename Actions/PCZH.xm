// 最小探针：与官方 ExampleActions 完全同构，验证注册链路
#import "pczh_api.h"

@interface ZHProbeAction : PCAction
@end
@implementation ZHProbeAction
-(void) performActionForIdentifier:(NSString*)identifier {
}
-(NSString*) nameForIdentifier:(NSString*)identifier {
    return @"探针动作";
}
-(NSString*) descriptionSummaryForIdentifier:(NSString*)identifier {
    return @"测试注册链路，无实际功能。";
}
@end

%ctor {
    [[PowercutsManager sharedInstance] registerActionWithIdentifier:@"com.moss.powercuts.probe" action:[ZHProbeAction new]];
}
