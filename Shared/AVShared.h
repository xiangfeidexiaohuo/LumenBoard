#pragma once

#import <Foundation/Foundation.h>
#include <unistd.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#include <roothide.h>
#endif

// jailbreak path -> real path (/var/jb/... on rootless, inside the random jbroot folder on roothide)
static inline NSString *AVRootPath(NSString *path) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
  return jbroot(path);
#else
  static NSString *root;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    root = (access("/var/jb", F_OK) == 0) ? @"/var/jb" : @"";
  });
  return [root stringByAppendingString:path];
#endif
}

// real path -> jailbreak path. Used for paths we save, roothide renames the jbroot folder on every jailbreak.
static inline NSString *AVJailbreakPath(NSString *path) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
  return rootfs(path);
#else
  NSString *root = AVRootPath(@"");
  return (root.length && [path hasPrefix:[root stringByAppendingString:@"/"]]) ? [path substringFromIndex:root.length] : path;
#endif
}

#define AVThemesDirectory AVRootPath(@"/Library/Themes")
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#define AVThemesDirectoryDisplayName @"/Library/Themes"
#else
#define AVThemesDirectoryDisplayName AVThemesDirectory
#endif

// Config.plist (app) and IconMap.plist (SpringBoard). Not in /var/mobile/Library/Preferences because
// iconservicesagent is sandboxed and can only read from the jailbreak folder.
#define AVDataDirectory AVRootPath(@"/var/mobile/Library/Avalanche")
#define AVConfigPath [AVDataDirectory stringByAppendingPathComponent:@"Config.plist"]
#define AVIconMapPath [AVDataDirectory stringByAppendingPathComponent:@"IconMap.plist"]

#define AVNotifyApply "com.xsxs18.avalanche/apply"
#define AVNotifyClearCache "com.xsxs18.avalanche/clear-cache"
#define AVNotifyMapChanged "com.xsxs18.avalanche/map-changed"
// state = (done << 32) | total, done == UINT32_MAX when SpringBoard is about to respring
#define AVNotifyProgress "com.xsxs18.avalanche/progress"

// Config.plist
#define AVConfigEnabledThemes @"EnabledThemes" // theme folder names, first one wins
#define AVConfigUseSystemIconShape @"UseSystemIconShape"
#define AVConfigKeepIconsInDarkAndTinted @"KeepIconsInDarkAndTinted"

// IconMap.plist
#define AVMapVersion 2 // 2: icon paths are jailbreak paths
#define AVMapIcons @"Icons" // lowercased bundle id -> icon
#define AVIconLight @"Light"
#define AVIconDark @"Dark"
#define AVIconTinted @"Tinted"
#define AVIconToken @"Token" // changes whenever the icon or the settings change
#define AVMapAppliedConfig @"AppliedConfig"
