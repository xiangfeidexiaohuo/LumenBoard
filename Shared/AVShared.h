// Avalanche – constants shared by the tweak, the SpringBoard part and the app.
#pragma once

#import <Foundation/Foundation.h>
#include <unistd.h>

// Rootless jailbreaks install everything under /var/jb (resolved at runtime, so a rootful install works too).
static inline NSString *AVJailbreakRoot(void) {
  static NSString *root;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    root = (access("/var/jb", F_OK) == 0) ? @"/var/jb" : @"";
  });
  return root;
}

static inline NSString *AVRootPath(NSString *path) {
  return [AVJailbreakRoot() stringByAppendingString:path];
}

// Themes live where every theme engine expects them.
#define AVThemesDirectory AVRootPath(@"/Library/Themes")

// Written by the app (Config.plist) and SpringBoard (IconMap.plist). It is inside the jailbreak root on purpose:
// sandboxed processes like iconservicesagent can read it there, but not /var/mobile/Library/Preferences.
#define AVDataDirectory AVRootPath(@"/var/mobile/Library/Avalanche")
#define AVConfigPath [AVDataDirectory stringByAppendingPathComponent:@"Config.plist"]
#define AVIconMapPath [AVDataDirectory stringByAppendingPathComponent:@"IconMap.plist"]

// app -> SpringBoard
#define AVNotifyApply "com.xsxs18.avalanche/apply"
#define AVNotifyClearCache "com.xsxs18.avalanche/clear-cache"
// SpringBoard -> every process with the tweak
#define AVNotifyMapChanged "com.xsxs18.avalanche/map-changed"
// SpringBoard -> app; notify state = (done << 32) | total, done == UINT32_MAX means "respringing"
#define AVNotifyProgress "com.xsxs18.avalanche/progress"

// Config.plist
#define AVConfigEnabledThemes @"EnabledThemes"           // NSArray of theme folder names, highest priority first
#define AVConfigUseSystemIconShape @"UseSystemIconShape" // NO: theme icons keep their own shape and transparency
#define AVConfigKeepIconsInDarkAndTinted @"KeepIconsInDarkAndTinted" // YES: don't let iOS darken/tint theme icons

// IconMap.plist
#define AVMapVersion 1
#define AVMapIcons @"Icons"   // lowercased bundle identifier -> icon entry
#define AVIconLight @"Light"  // path of the icon
#define AVIconDark @"Dark"    // optional "-dark" variant
#define AVIconTinted @"Tinted" // optional "-tinted" variant
#define AVIconToken @"Token"  // changes whenever the icon or its settings change
#define AVMapAppliedConfig @"AppliedConfig" // the Config.plist contents this map was built from
