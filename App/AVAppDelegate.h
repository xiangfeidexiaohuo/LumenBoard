#import <UIKit/UIKit.h>

#define AVLocalized(text) NSLocalizedString(text, nil)

@interface AVAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface AVSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
