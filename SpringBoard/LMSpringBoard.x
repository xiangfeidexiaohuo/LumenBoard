// SpringBoard: builds IconMap.plist from Config.plist and handles Apply (pre-render icons, respring)

#import "../Shared/LMThemeLibrary.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(NSUInteger)options targetURL:(NSURL *)url;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

@interface ISIcon : NSObject
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
- (void)prepareImagesForImageDescriptors:(NSArray *)descriptors;
- (id)imageForDescriptor:(id)descriptor;
@end

@interface ISImageDescriptor : NSObject
- (instancetype)initWithSize:(CGSize)size scale:(double)scale;
- (void)setShouldApplyMask:(BOOL)shouldApplyMask;
@end

#pragma mark - Helpers

static void LMRun(NSString *tool, NSArray<NSString *> *arguments) {
  NSString *path = LMRootPath(tool);
  if (access(path.fileSystemRepresentation, X_OK) != 0) path = tool;
  const char *argv[arguments.count + 2];
  argv[0] = path.lastPathComponent.fileSystemRepresentation;
  for (NSUInteger i = 0; i < arguments.count; i++) argv[i + 1] = arguments[i].UTF8String;
  argv[arguments.count + 1] = NULL;
  pid_t pid;
  if (posix_spawn(&pid, path.fileSystemRepresentation, NULL, NULL, (char * const *)argv, NULL) == 0) {
    int status;
    waitpid(pid, &status, 0);
  }
}

// a fresh agent has the new map and no old artwork in memory
static void LMRestartIconAgent(void) {
  LMRun(@"/usr/bin/killall", @[@"-9", @"iconservicesagent"]);
}

static NSString *LMHash(NSString *string) {
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
  NSMutableString *hex = [NSMutableString stringWithCapacity:20];
  for (int i = 0; i < 10; i++) [hex appendFormat:@"%02x", hash[i]];
  return hex;
}

static NSString *LMFileStamp(NSString *path) {
  struct stat info;
  if (!path || stat(path.fileSystemRepresentation, &info) != 0) return @"-";
  return [NSString stringWithFormat:@"%lld.%ld/%lld", (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec, (long long)info.st_size];
}

static void LMReloadStoreInThisProcess(void) {
  Class store = objc_getClass("LMIconStore");
  if (![store respondsToSelector:@selector(sharedStore)]) return;
  id shared = ((id (*)(Class, SEL))objc_msgSend)(store, @selector(sharedStore));
  ((void (*)(id, SEL))objc_msgSend)(shared, @selector(reload));
}

#pragma mark - Icon map

// app name -> bundle ids, for Icons/<App Name>.png
static NSDictionary *LMInstalledAppNames(void) {
  NSMutableDictionary *names = [NSMutableDictionary new];
  for (LSApplicationProxy *app in [[objc_getClass("LSApplicationWorkspace") defaultWorkspace] allInstalledApplications]) {
    NSString *name = app.localizedName.lowercaseString, *bundleID = app.applicationIdentifier.lowercaseString;
    if (!name.length || !bundleID.length) continue;
    NSMutableArray *bundleIDs = names[name] ? : (names[name] = [NSMutableArray new]);
    [bundleIDs addObject:bundleID];
  }
  return names;
}

// YES if the map changed
static BOOL LMWriteIconMap(void) {
  NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:LMConfigPath] ? : @{};
  NSArray *themes = [config[LMConfigEnabledThemes] isKindOfClass:[NSArray class]] ? config[LMConfigEnabledThemes] : @[];
  BOOL systemShape = [config[LMConfigUseSystemIconShape] boolValue];
  BOOL keepAppearance = [config[LMConfigKeepIconsInDarkAndTinted] boolValue];

  [LMThemeLibrary invalidate];
  BOOL usesAppNames = NO;
  for (NSString *theme in themes) usesAppNames = usesAppNames || ([theme isKindOfClass:[NSString class]] && [LMThemeLibrary iconsByAppNameInTheme:theme].count);
  NSDictionary *icons = [LMThemeLibrary resolvedIconsForThemes:themes appNames:(usesAppNames ? LMInstalledAppNames() : nil)];

  NSDictionary *appliedConfig = @{ LMConfigEnabledThemes : themes, LMConfigUseSystemIconShape : @(systemShape), LMConfigKeepIconsInDarkAndTinted : @(keepAppearance) };

  // hash everything that changes how an icon looks. Paths are saved as jailbreak paths (roothide renames the jbroot).
  NSString *style = [NSString stringWithFormat:@"v%d shape=%d keep=%d", LMMapVersion, systemShape, keepAppearance];
  NSMutableDictionary *entries = [NSMutableDictionary new], *materials = [NSMutableDictionary new];
  NSMutableString *content = [NSMutableString stringWithFormat:@"%@\n%@\n", style, [themes componentsJoinedByString:@"/"]];
  for (NSString *bundleID in [icons.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    NSDictionary *icon = icons[bundleID];
    NSMutableDictionary *entry = [NSMutableDictionary new];
    NSMutableString *material = [bundleID mutableCopy];
    for (NSString *slot in @[LMIconLight, LMIconDark, LMIconTinted]) {
      if (icon[slot]) entry[slot] = LMJailbreakPath(icon[slot]);
      [material appendFormat:@"|%@@%@", entry[slot] ? : @"", LMFileStamp(icon[slot])];
    }
    [material appendFormat:@"|%@", style];
    entries[bundleID] = entry;
    materials[bundleID] = material;
    [content appendFormat:@"%@\n", material];
  }
  NSString *contentHash = LMHash(content);

  NSDictionary *previous = [NSDictionary dictionaryWithContentsOfFile:LMIconMapPath];
  if ([previous[@"Version"] integerValue] == LMMapVersion && [previous[@"ContentHash"] isEqual:contentHash]) return NO;

  // new generation on every change, so tokens (icon cache keys) are never reused
  NSString *generation = [NSUUID UUID].UUIDString;
  [entries enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSMutableDictionary *entry, BOOL *stop) {
    entry[LMIconToken] = LMHash([materials[bundleID] stringByAppendingFormat:@"|%@", generation]);
  }];
  NSDictionary *map = @{
    @"Version" : @(LMMapVersion),
    @"ContentHash" : contentHash,
    @"Generation" : generation,
    LMConfigUseSystemIconShape : @(systemShape),
    LMConfigKeepIconsInDarkAndTinted : @(keepAppearance),
    LMMapAppliedConfig : appliedConfig,
    LMMapIcons : entries
  };

  [[NSFileManager defaultManager] createDirectoryAtPath:LMDataDirectory withIntermediateDirectories:YES attributes:nil error:nil];
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:map format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
  if (![data writeToFile:LMIconMapPath options:NSDataWritingAtomic error:nil]) {
    NSLog(@"[Lumen] can't write %@", LMIconMapPath);
    return NO;
  }
  chmod(LMIconMapPath.fileSystemRepresentation, 0644);
  return YES;
}

#pragma mark - Apply

// progress for the app: notify state = (done << 32) | total
static void LMReportProgress(uint32_t done, uint32_t total) {
  static int token;
  static BOOL registered;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    registered = notify_register_check(LMNotifyProgress, &token) == NOTIFY_STATUS_OK;
  });
  if (!registered) return;
  notify_set_state(token, ((uint64_t)done << 32) | total);
  notify_post(LMNotifyProgress);
}

static void LMClearSystemIconCache(void) {
  for (NSString *path in @[
    @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches/com.apple.IconsCache",
    @"/var/mobile/Library/Caches/com.apple.IconsCache",
    @"/var/mobile/Library/Caches/MappedImageCache/Persistent"
  ]) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

// the descriptors SpringBoard uses for home screen icons, main thread only
static NSArray *LMHomeScreenDescriptors(void) {
  BOOL pad = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad;
  CGFloat longestSide = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
  CGSize size = pad ? ((longestSide >= 1366) ? CGSizeMake(83.5, 83.5) : CGSizeMake(76, 76)) : CGSizeMake(60, 60);
  CGFloat scale = [UIScreen mainScreen].scale;
  UITraitCollection *traits = [UIScreen mainScreen].traitCollection;

  typedef id (*DescriptorFunction)(UITraitCollection *traitCollection, BOOL unmasked, double width, double height, double scale);
  DescriptorFunction springBoardDescriptor = (DescriptorFunction)dlsym(RTLD_DEFAULT, "SBHImageDescriptorWithTraitCollection");
  Class descriptorClass = objc_getClass("ISImageDescriptor");
  NSMutableArray *descriptors = [NSMutableArray new];
  for (NSNumber *unmasked in @[@YES, @NO]) {
    id descriptor = springBoardDescriptor ? springBoardDescriptor(traits, unmasked.boolValue, size.width, size.height, scale) : nil;
    if (!descriptor && [descriptorClass instancesRespondToSelector:@selector(initWithSize:scale:)]) {
      descriptor = [[descriptorClass alloc] initWithSize:size scale:scale];
      if ([descriptor respondsToSelector:@selector(setShouldApplyMask:)]) [descriptor setShouldApplyMask:!unmasked.boolValue];
    }
    if (descriptor) [descriptors addObject:descriptor];
  }
  return descriptors;
}

// apps whose icon changed, nil maps = all apps
static NSArray<NSString *> *LMAppsToRender(NSDictionary *before, NSDictionary *after) {
  NSMutableArray *bundleIDs = [NSMutableArray new];
  for (LSApplicationProxy *app in [[objc_getClass("LSApplicationWorkspace") defaultWorkspace] allInstalledApplications]) {
    NSString *bundleID = app.applicationIdentifier;
    NSString *key = bundleID.lowercaseString;
    if (!key.length) continue;
    NSDictionary *previous = before[key], *current = after[key];
    BOOL everyApp = !before && !after;
    if (everyApp || ((previous || current) && ![previous isEqual:current])) [bundleIDs addObject:bundleID];
  }
  return bundleIDs;
}

static BOOL LMIconIsCached(ISIcon *icon, NSArray *descriptors) {
  for (id descriptor in descriptors) {
    id image = [icon imageForDescriptor:descriptor];
    // IFImage -placeholder: still rendering, or the cached image is outdated
    if (!image || ([image respondsToSelector:@selector(placeholder)] && ((BOOL (*)(id, SEL))objc_msgSend)(image, @selector(placeholder)))) return NO;
  }
  return YES;
}

// render the icons now so they don't pop in one by one after the respring
static void LMPrerenderIcons(NSArray<NSString *> *bundleIDs, NSArray *descriptors) {
  Class iconClass = objc_getClass("ISIcon");
  if (!descriptors.count || ![iconClass instancesRespondToSelector:@selector(prepareImagesForImageDescriptors:)] || ![iconClass instancesRespondToSelector:@selector(imageForDescriptor:)]) return;
  NSMutableArray *pending = [NSMutableArray new];
  for (NSString *bundleID in bundleIDs) {
    @autoreleasepool {
      ISIcon *icon = [[iconClass alloc] initWithBundleIdentifier:bundleID];
      if (!icon) continue;
      [icon prepareImagesForImageDescriptors:descriptors];
      [pending addObject:icon];
    }
  }
  uint32_t total = (uint32_t)pending.count, done = 0;
  LMReportProgress(0, total);
  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent(), lastProgress = start;
  // max 60s, or 10s without progress
  while (pending.count && CFAbsoluteTimeGetCurrent() - start < 60 && CFAbsoluteTimeGetCurrent() - lastProgress < 10) {
    usleep(150 * 1000);
    NSIndexSet *cached = [pending indexesOfObjectsPassingTest:^BOOL(ISIcon *icon, NSUInteger index, BOOL *stop) {
      return LMIconIsCached(icon, descriptors);
    }];
    if (!cached.count) continue;
    [pending removeObjectsAtIndexes:cached];
    done += (uint32_t)cached.count;
    lastProgress = CFAbsoluteTimeGetCurrent();
    LMReportProgress(done, total);
  }
}

static void LMRespring(void) {
  Class relaunchAction = objc_getClass("SBSRelaunchAction");
  Class systemService = objc_getClass("FBSSystemService");
  if (relaunchAction && systemService) {
    id action = [relaunchAction actionWithReason:@"LumenApply" options:4 targetURL:nil]; // 4: restart render server
    [[systemService sharedService] sendActions:[NSSet setWithObject:action] withResult:nil];
    return;
  }
  LMRun(@"/usr/bin/killall", @[@"-9", @"SpringBoard"]);
}

static void LMApply(BOOL clearCache) {
  static BOOL applying;
  if (applying) return;
  applying = YES;

  NSDictionary *before = [NSDictionary dictionaryWithContentsOfFile:LMIconMapPath][LMMapIcons] ? : @{};
  if (clearCache) LMClearSystemIconCache();
  LMWriteIconMap();
  // reload here now, the other processes get the notification
  LMReloadStoreInThisProcess();
  notify_post(LMNotifyMapChanged);
  NSArray *descriptors = LMHomeScreenDescriptors();

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    LMRestartIconAgent();
    usleep(300 * 1000);
    NSDictionary *after = [NSDictionary dictionaryWithContentsOfFile:LMIconMapPath][LMMapIcons] ? : @{};
    // cache was wiped, render everything
    NSArray *apps = clearCache ? LMAppsToRender(nil, nil) : LMAppsToRender(before, after);
    LMPrerenderIcons(apps, descriptors);
    LMReportProgress(UINT32_MAX, UINT32_MAX);
    dispatch_async(dispatch_get_main_queue(), ^{ LMRespring(); });
  });
}

static void LMApplyNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  BOOL clearCache = CFEqual(name, CFSTR(LMNotifyClearCache));
  dispatch_async(dispatch_get_main_queue(), ^{ LMApply(clearCache); });
}

%ctor {
  @autoreleasepool {
    if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}]) return;
    // themes might have been updated by the package manager
    if (LMWriteIconMap()) {
      LMReloadStoreInThisProcess();
      LMRestartIconAgent();
      notify_post(LMNotifyMapChanged);
    }
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center, NULL, LMApplyNotification, CFSTR(LMNotifyApply), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, LMApplyNotification, CFSTR(LMNotifyClearCache), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  }
}
