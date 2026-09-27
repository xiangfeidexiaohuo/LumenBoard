#import "AVAppDelegate.h"

// Sheet shown while SpringBoard pre-renders the theme icons and resprings.
@interface AVApplyViewController : UIViewController
- (instancetype)initWithClearingIconCache:(BOOL)clearIconCache;
@end
