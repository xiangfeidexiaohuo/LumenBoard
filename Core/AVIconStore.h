#import "../Shared/AVShared.h"

NS_ASSUME_NONNULL_BEGIN

// The icon map SpringBoard resolved from the enabled themes (IconMap.plist), loaded lazily and shared by all threads.
@interface AVIconStore : NSObject

+ (instancetype)sharedStore;
// nil when the app isn't themed
- (nullable NSDictionary *)iconForBundleIdentifier:(nullable NSString *)bundleIdentifier;
@property (nonatomic, readonly) NSUInteger themedIconCount;
@property (nonatomic, readonly) BOOL usesSystemIconShape;
@property (nonatomic, readonly) BOOL keepsIconsInDarkAndTinted;
// re-read IconMap.plist on next use
- (void)reload;
// reload right away if IconMap.plist was replaced since it was read (one stat() call)
- (void)reloadIfMapChanged;

@end

NS_ASSUME_NONNULL_END
