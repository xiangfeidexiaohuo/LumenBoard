#import "AVShared.h"

NS_ASSUME_NONNULL_BEGIN

// Reads theme folders in the formats SnowBoard, Anemone and WinterBoard use:
//   Theme.theme/IconBundles/<bundle id>[-large][-dark|-tinted][@2x|@3x][~iphone|~ipad].png
//   Theme.theme/Icons/<App Name>.png
@interface AVThemeLibrary : NSObject

// folder names in /Library/Themes, sorted by display name
+ (NSArray<NSString *> *)installedThemes;
// "Viola.theme" -> "Viola"
+ (NSString *)displayNameForTheme:(NSString *)theme;
// lowercased bundle identifier -> @{ AVIconLight: path, AVIconDark: path, AVIconTinted: path }
+ (NSDictionary<NSString *, NSDictionary *> *)iconsInTheme:(NSString *)theme;
// same, keyed by lowercased app name ("Icons" folder)
+ (NSDictionary<NSString *, NSDictionary *> *)iconsByAppNameInTheme:(NSString *)theme;
// The icon every app gets from the enabled themes: the first theme (highest priority) that has one wins,
// IconBundles before Icons. appNames: lowercased app name -> lowercased bundle identifiers.
+ (NSDictionary<NSString *, NSDictionary *> *)resolvedIconsForThemes:(NSArray<NSString *> *)themes appNames:(nullable NSDictionary<NSString *, NSArray<NSString *> *> *)appNames;
// forget cached folder listings (after themes were installed or removed)
+ (void)invalidate;

@end

NS_ASSUME_NONNULL_END
