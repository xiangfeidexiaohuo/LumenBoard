#import "LMAppDelegate.h"
#import "LMThemesViewController.h"

@implementation LMAppDelegate

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
  UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
  configuration.delegateClass = [LMSceneDelegate class];
  return configuration;
}

@end

@implementation LMSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
  if (![scene isKindOfClass:[UIWindowScene class]]) return;
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:[LMThemesViewController new]];
  navigationController.navigationBar.prefersLargeTitles = YES;
  navigationController.toolbarHidden = NO;
  self.window.tintColor = [UIColor colorWithRed:0.25 green:0.56 blue:0.98 alpha:1.0];
  self.window.rootViewController = navigationController;
  [self.window makeKeyAndVisible];
}

@end
