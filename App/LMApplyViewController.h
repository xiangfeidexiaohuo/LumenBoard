#import "LMAppDelegate.h"

// Sheet shown while SpringBoard pre-renders the theme icons and resprings.
@interface LMApplyViewController : UIViewController
- (instancetype)initWithClearingIconCache:(BOOL)clearIconCache;
@end
