#import <Foundation/Foundation.h>
// libpowercuts 最小接口声明（由二进制元数据还原）
@interface PCAction : NSObject
- (NSString *)nameForIdentifier:(NSString *)identifier;
- (NSString *)descriptionSummaryForIdentifier:(NSString *)identifier;
- (id)parametersDefinitionForIdentifier:(NSString *)identifier;

- (void)performActionForIdentifier:(NSString *)identifier;
- (void)performActionForIdentifier:(NSString *)identifier withParameters:(NSDictionary *)params;
@end

@interface PowercutsManager : NSObject
+ (instancetype)sharedInstance;
- (void)registerActionWithIdentifier:(NSString *)identifier action:(id)action;
- (void)registerActionWithIdentifier:(NSString *)identifier action:(id)action writeToCache:(BOOL)writeToCache;
@end

@interface PCSharedBucketManager : NSObject
+ (instancetype)defaultManager;
- (id)dataPrefs;
@end
