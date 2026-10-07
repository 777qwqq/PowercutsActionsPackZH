#import <Foundation/Foundation.h>
@interface PCAction : NSObject
@end
@interface PowercutsManager : NSObject
+ (instancetype)sharedInstance;
- (NSDictionary *)registeredCustomActions;
@end
