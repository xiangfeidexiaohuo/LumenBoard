#pragma once

#import <Foundation/Foundation.h>
#include <unistd.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#include <roothide.h>
#endif

// jailbreak path -> real path (/var/jb/... on rootless, inside the random jbroot folder on roothide)
static inline NSString *LMRootPath(NSString *path) {
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
static inline NSString *LMJailbreakPath(NSString *path) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
  return rootfs(path);
#else
  NSString *root = LMRootPath(@"");
  return (root.length && [path hasPrefix:[root stringByAppendingString:@"/"]]) ? [path substringFromIndex:root.length] : path;
#endif
}

#define LMThemesDirectory LMRootPath(@"/Library/Themes")
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#define LMThemesDirectoryDisplayName @"/Library/Themes"
#else
#define LMThemesDirectoryDisplayName LMThemesDirectory
#endif

// Config.plist (app) and IconMap.plist (SpringBoard). Not in /var/mobile/Library/Preferences because
// iconservicesagent is sandboxed and can only read from the jailbreak folder.
#define LMDataDirectory LMRootPath(@"/var/mobile/Library/Lumen")
#define LMConfigPath [LMDataDirectory stringByAppendingPathComponent:@"Config.plist"]
#define LMIconMapPath [LMDataDirectory stringByAppendingPathComponent:@"IconMap.plist"]

#define LMNotifyApply "com.xsxs18.lumen/apply"
#define LMNotifyClearCache "com.xsxs18.lumen/clear-cache"
#define LMNotifyMapChanged "com.xsxs18.lumen/map-changed"
// state = (done << 32) | total, done == UINT32_MAX when SpringBoard is about to respring
#define LMNotifyProgress "com.xsxs18.lumen/progress"

// Config.plist
#define LMConfigEnabledThemes @"EnabledThemes" // theme folder names, first one wins
#define LMConfigUseSystemIconShape @"UseSystemIconShape"
#define LMConfigKeepIconsInDarkAndTinted @"KeepIconsInDarkAndTinted"

// IconMap.plist
#define LMMapVersion 2 // 2: icon paths are jailbreak paths
#define LMMapIcons @"Icons" // lowercased bundle id -> icon
#define LMIconLight @"Light"
#define LMIconDark @"Dark"
#define LMIconTinted @"Tinted"
#define LMIconToken @"Token" // changes whenever the icon or the settings change
#define LMMapAppliedConfig @"AppliedConfig"
