#import "AVThemeLibrary.h"
#include <os/lock.h>
#include <sys/utsname.h>

// What a file name tells about an icon, e.g. "com.apple.MobileSMS-large@3x~iphone.png".
typedef struct {
  NSInteger appearance; // 0 light, 1 dark, 2 tinted
  NSInteger rank;       // higher wins: matching device, then "-large", then scale
} AVIconFileTraits;

static BOOL AVDeviceIsPad(void) {
  static BOOL pad;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    struct utsname name;
    uname(&name);
    pad = strncmp(name.machine, "iPad", 4) == 0;
  });
  return pad;
}

static NSRegularExpression *AVTrailingSuffix(void) {
  static NSRegularExpression *expression;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    expression = [NSRegularExpression regularExpressionWithPattern:@"(?:-large|-dark|-tinted|@[123]x|~iphone|~ipad)$" options:NSRegularExpressionCaseInsensitive error:nil];
  });
  return expression;
}

// Returns the lowercased icon name (bundle identifier or app name), or nil if the file isn't an icon.
static NSString *AVIconNameForFile(NSString *file, AVIconFileTraits *traits) {
  if ([file.pathExtension caseInsensitiveCompare:@"png"] != NSOrderedSame) return nil;
  NSString *name = file.stringByDeletingPathExtension;
  NSInteger scale = 1, device = 1, large = 0, appearance = 0;
  BOOL pad = AVDeviceIsPad();
  for (;;) {
    NSTextCheckingResult *match = [AVTrailingSuffix() firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    if (!match || match.range.location == 0) break;
    NSString *suffix = [name substringWithRange:match.range].lowercaseString;
    if ([suffix isEqualToString:@"-large"]) large = 1;
    else if ([suffix isEqualToString:@"-dark"]) appearance = 1;
    else if ([suffix isEqualToString:@"-tinted"]) appearance = 2;
    else if ([suffix isEqualToString:@"~iphone"]) device = pad ? 0 : 2;
    else if ([suffix isEqualToString:@"~ipad"]) device = pad ? 2 : 0;
    else scale = [suffix characterAtIndex:1] - '0';
    name = [name substringToIndex:match.range.location];
  }
  if (!name.length) return nil;
  traits->appearance = appearance;
  traits->rank = device * 1000 + large * 100 + scale;
  return name.lowercaseString;
}

static os_unfair_lock AVLibraryLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary *AVFolderCache; // "<theme>/<folder>" -> parsed icons

@implementation AVThemeLibrary

+ (NSArray<NSString *> *)installedThemes {
  NSMutableArray *themes = [NSMutableArray new];
  for (NSString *folder in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:AVThemesDirectory error:nil]) {
    if ([folder hasPrefix:@"."]) continue;
    BOOL isDirectory = NO;
    NSString *path = [AVThemesDirectory stringByAppendingPathComponent:folder];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) [themes addObject:folder];
  }
  [themes sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    return [[self displayNameForTheme:a] localizedCaseInsensitiveCompare:[self displayNameForTheme:b]];
  }];
  return themes;
}

+ (NSString *)displayNameForTheme:(NSString *)theme {
  return [theme.pathExtension caseInsensitiveCompare:@"theme"] == NSOrderedSame ? theme.stringByDeletingPathExtension : theme;
}

+ (NSDictionary<NSString *, NSDictionary *> *)iconsInFolder:(NSString *)folder ofTheme:(NSString *)theme {
  if (!theme.length) return @{};
  NSString *cacheKey = [theme stringByAppendingPathComponent:folder];
  os_unfair_lock_lock(&AVLibraryLock);
  NSDictionary *cached = AVFolderCache[cacheKey];
  os_unfair_lock_unlock(&AVLibraryLock);
  if (cached) return cached;

  NSString *directory = [[AVThemesDirectory stringByAppendingPathComponent:theme] stringByAppendingPathComponent:folder];
  NSMutableDictionary *icons = [NSMutableDictionary new];
  NSMutableDictionary *ranks = [NSMutableDictionary new];
  for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil]) {
    AVIconFileTraits traits;
    NSString *name = AVIconNameForFile(file, &traits);
    if (!name) continue;
    NSString *slot = @[AVIconLight, AVIconDark, AVIconTinted][traits.appearance];
    NSString *rankKey = [NSString stringWithFormat:@"%@\n%@", name, slot];
    NSNumber *best = ranks[rankKey];
    if (best && best.integerValue >= traits.rank) continue;
    ranks[rankKey] = @(traits.rank);
    NSMutableDictionary *icon = icons[name] ? : (icons[name] = [NSMutableDictionary new]);
    icon[slot] = [directory stringByAppendingPathComponent:file];
  }
  // dark/tinted artwork without a normal icon isn't usable on its own
  for (NSString *name in icons.allKeys) if (!icons[name][AVIconLight]) [icons removeObjectForKey:name];

  NSDictionary *result = [icons copy];
  os_unfair_lock_lock(&AVLibraryLock);
  if (!AVFolderCache) AVFolderCache = [NSMutableDictionary new];
  AVFolderCache[cacheKey] = result;
  os_unfair_lock_unlock(&AVLibraryLock);
  return result;
}

+ (NSDictionary<NSString *, NSDictionary *> *)iconsInTheme:(NSString *)theme {
  return [self iconsInFolder:@"IconBundles" ofTheme:theme];
}

+ (NSDictionary<NSString *, NSDictionary *> *)iconsByAppNameInTheme:(NSString *)theme {
  return [self iconsInFolder:@"Icons" ofTheme:theme];
}

+ (NSDictionary<NSString *, NSDictionary *> *)resolvedIconsForThemes:(NSArray<NSString *> *)themes appNames:(NSDictionary<NSString *, NSArray<NSString *> *> *)appNames {
  NSMutableDictionary *resolved = [NSMutableDictionary new];
  for (NSString *theme in themes) {
    if (![theme isKindOfClass:[NSString class]]) continue;
    [[self iconsInTheme:theme] enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSDictionary *icon, BOOL *stop) {
      if (!resolved[bundleID]) resolved[bundleID] = icon;
    }];
    if (!appNames.count) continue;
    [[self iconsByAppNameInTheme:theme] enumerateKeysAndObjectsUsingBlock:^(NSString *appName, NSDictionary *icon, BOOL *stop) {
      for (NSString *bundleID in appNames[appName]) if (!resolved[bundleID]) resolved[bundleID] = icon;
    }];
  }
  return resolved;
}

+ (void)invalidate {
  os_unfair_lock_lock(&AVLibraryLock);
  [AVFolderCache removeAllObjects];
  os_unfair_lock_unlock(&AVLibraryLock);
}

@end
