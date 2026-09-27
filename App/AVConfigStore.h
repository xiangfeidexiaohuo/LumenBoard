#import "../Shared/AVShared.h"

NS_ASSUME_NONNULL_BEGIN

// Config.plist, the only thing the app writes. SpringBoard turns it into the icon map on "Apply".
@interface AVConfigStore : NSObject

+ (instancetype)sharedStore;
// theme folder names, highest priority first
@property (nonatomic, copy) NSArray<NSString *> *enabledThemes;
@property (nonatomic) BOOL useSystemIconShape;
@property (nonatomic) BOOL keepIconsInDarkAndTinted;
// changed since the last apply
@property (nonatomic, readonly) BOOL hasUnappliedChanges;

- (BOOL)save:(NSError **)error;
- (void)markApplied;

@end

NS_ASSUME_NONNULL_END
