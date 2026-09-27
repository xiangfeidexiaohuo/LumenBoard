#import <UIKit/UIKit.h>

#define LMLocalized(text) NSLocalizedString(text, nil)

@interface LMAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface LMSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
