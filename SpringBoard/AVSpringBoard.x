// SpringBoard side of Avalanche: turns Config.plist (written by the app) into IconMap.plist, which every process
// reads, and handles "Apply": pre-render the theme icons into the system icon cache, then respring.

#import "../Shared/AVThemeLibrary.h"
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

static void AVRun(NSString *tool, NSArray<NSString *> *arguments) {
  NSString *path = AVRootPath(tool);
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

// iconservicesagent renders the icons; a fresh one only knows the current map and has no decoded artwork cached
static void AVRestartIconAgent(void) {
  AVRun(@"/usr/bin/killall", @[@"-9", @"iconservicesagent"]);
}

static NSString *AVHash(NSString *string) {
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
  NSMutableString *hex = [NSMutableString stringWithCapacity:20];
  for (int i = 0; i < 10; i++) [hex appendFormat:@"%02x", hash[i]];
  return hex;
}

static NSString *AVFileStamp(NSString *path) {
  struct stat info;
  if (!path || stat(path.fileSystemRepresentation, &info) != 0) return @"-";
  return [NSString stringWithFormat:@"%lld.%ld/%lld", (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec, (long long)info.st_size];
}

static void AVReloadStoreInThisProcess(void) {
  Class store = objc_getClass("AVIconStore");
  if (![store respondsToSelector:@selector(sharedStore)]) return;
  id shared = ((id (*)(Class, SEL))objc_msgSend)(store, @selector(sharedStore));
  ((void (*)(id, SEL))objc_msgSend)(shared, @selector(reload));
}

#pragma mark - Icon map

// lowercased app name -> lowercased bundle ids, only needed for WinterBoard style "Icons/<App Name>.png" themes
static NSDictionary *AVInstalledAppNames(void) {
  NSMutableDictionary *names = [NSMutableDictionary new];
  for (LSApplicationProxy *app in [[objc_getClass("LSApplicationWorkspace") defaultWorkspace] allInstalledApplications]) {
    NSString *name = app.localizedName.lowercaseString, *bundleID = app.applicationIdentifier.lowercaseString;
    if (!name.length || !bundleID.length) continue;
    NSMutableArray *bundleIDs = names[name] ? : (names[name] = [NSMutableArray new]);
    [bundleIDs addObject:bundleID];
  }
  return names;
}

// Resolves the enabled themes into IconMap.plist. Returns YES if the map changed.
static BOOL AVWriteIconMap(void) {
  NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:AVConfigPath] ? : @{};
  NSArray *themes = [config[AVConfigEnabledThemes] isKindOfClass:[NSArray class]] ? config[AVConfigEnabledThemes] : @[];
  BOOL systemShape = [config[AVConfigUseSystemIconShape] boolValue];
  BOOL keepAppearance = [config[AVConfigKeepIconsInDarkAndTinted] boolValue];

  [AVThemeLibrary invalidate];
  BOOL usesAppNames = NO;
  for (NSString *theme in themes) usesAppNames = usesAppNames || ([theme isKindOfClass:[NSString class]] && [AVThemeLibrary iconsByAppNameInTheme:theme].count);
  NSDictionary *icons = [AVThemeLibrary resolvedIconsForThemes:themes appNames:(usesAppNames ? AVInstalledAppNames() : nil)];

  NSDictionary *appliedConfig = @{ AVConfigEnabledThemes : themes, AVConfigUseSystemIconShape : @(systemShape), AVConfigKeepIconsInDarkAndTinted : @(keepAppearance) };

  // everything that changes how an icon renders: its files and the icon style settings
  NSString *style = [NSString stringWithFormat:@"v%d shape=%d keep=%d", AVMapVersion, systemShape, keepAppearance];
  NSMutableDictionary *materials = [NSMutableDictionary new];
  NSMutableString *content = [NSMutableString stringWithFormat:@"%@\n%@\n", style, [themes componentsJoinedByString:@"/"]];
  for (NSString *bundleID in [icons.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    NSDictionary *icon = icons[bundleID];
    NSString *material = [NSString stringWithFormat:@"%@|%@@%@|%@@%@|%@@%@|%@", bundleID,
      icon[AVIconLight], AVFileStamp(icon[AVIconLight]), icon[AVIconDark] ? : @"", AVFileStamp(icon[AVIconDark]),
      icon[AVIconTinted] ? : @"", AVFileStamp(icon[AVIconTinted]), style];
    materials[bundleID] = material;
    [content appendFormat:@"%@\n", material];
  }
  NSString *contentHash = AVHash(content);

  NSDictionary *previous = [NSDictionary dictionaryWithContentsOfFile:AVIconMapPath];
  if ([previous[@"Version"] integerValue] == AVMapVersion && [previous[@"ContentHash"] isEqual:contentHash]) return NO;

  // A new generation on every change: tokens (and so icon cache keys) never repeat, a cache entry written while
  // processes were switching over is never picked up again later.
  NSString *generation = [NSUUID UUID].UUIDString;
  NSMutableDictionary *mapIcons = [NSMutableDictionary dictionaryWithCapacity:icons.count];
  [icons enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSDictionary *icon, BOOL *stop) {
    NSMutableDictionary *entry = [icon mutableCopy];
    entry[AVIconToken] = AVHash([materials[bundleID] stringByAppendingFormat:@"|%@", generation]);
    mapIcons[bundleID] = entry;
  }];
  NSDictionary *map = @{
    @"Version" : @(AVMapVersion),
    @"ContentHash" : contentHash,
    @"Generation" : generation,
    AVConfigUseSystemIconShape : @(systemShape),
    AVConfigKeepIconsInDarkAndTinted : @(keepAppearance),
    AVMapAppliedConfig : appliedConfig,
    AVMapIcons : mapIcons
  };

  [[NSFileManager defaultManager] createDirectoryAtPath:AVDataDirectory withIntermediateDirectories:YES attributes:nil error:nil];
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:map format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
  if (![data writeToFile:AVIconMapPath options:NSDataWritingAtomic error:nil]) {
    NSLog(@"[Avalanche] can't write %@", AVIconMapPath);
    return NO;
  }
  chmod(AVIconMapPath.fileSystemRepresentation, 0644);
  return YES;
}

#pragma mark - Apply

// progress for the app: notify state = (done << 32) | total
static void AVReportProgress(uint32_t done, uint32_t total) {
  static int token;
  static BOOL registered;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    registered = notify_register_check(AVNotifyProgress, &token) == NOTIFY_STATUS_OK;
  });
  if (!registered) return;
  notify_set_state(token, ((uint64_t)done << 32) | total);
  notify_post(AVNotifyProgress);
}

static void AVClearSystemIconCache(void) {
  for (NSString *path in @[
    @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches/com.apple.IconsCache",
    @"/var/mobile/Library/Caches/com.apple.IconsCache",
    @"/var/mobile/Library/Caches/MappedImageCache/Persistent"
  ]) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

// The image descriptors SpringBoard uses for home screen icons (masked and unmasked), so the pre-rendered icons are
// exactly the cache entries it asks for after the respring. Main thread only (UIScreen).
static NSArray *AVHomeScreenDescriptors(void) {
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

// Installed apps whose icon changes: themed now, themed differently, or back to stock. nil maps = every app.
static NSArray<NSString *> *AVAppsToRender(NSDictionary *before, NSDictionary *after) {
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

static BOOL AVIconIsCached(ISIcon *icon, NSArray *descriptors) {
  for (id descriptor in descriptors) {
    id image = [icon imageForDescriptor:descriptor];
    // IFImage -placeholder: still rendering, or the cached image is outdated
    if (!image || ([image respondsToSelector:@selector(placeholder)] && ((BOOL (*)(id, SEL))objc_msgSend)(image, @selector(placeholder)))) return NO;
  }
  return YES;
}

// Asks iconservicesagent for every changed icon and waits until they're cached, like SnowBoard's icon cache rebuild:
// after the respring the home screen shows the theme at once instead of icons popping in one by one.
static void AVPrerenderIcons(NSArray<NSString *> *bundleIDs, NSArray *descriptors) {
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
  AVReportProgress(0, total);
  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent(), lastProgress = start;
  // SpringBoard renders whatever is left on demand; don't hold the respring forever
  while (pending.count && CFAbsoluteTimeGetCurrent() - start < 60 && CFAbsoluteTimeGetCurrent() - lastProgress < 10) {
    usleep(150 * 1000);
    NSIndexSet *cached = [pending indexesOfObjectsPassingTest:^BOOL(ISIcon *icon, NSUInteger index, BOOL *stop) {
      return AVIconIsCached(icon, descriptors);
    }];
    if (!cached.count) continue;
    [pending removeObjectsAtIndexes:cached];
    done += (uint32_t)cached.count;
    lastProgress = CFAbsoluteTimeGetCurrent();
    AVReportProgress(done, total);
  }
}

static void AVRespring(void) {
  Class relaunchAction = objc_getClass("SBSRelaunchAction");
  Class systemService = objc_getClass("FBSSystemService");
  if (relaunchAction && systemService) {
    id action = [relaunchAction actionWithReason:@"AvalancheApply" options:4 targetURL:nil]; // 4: restart render server
    [[systemService sharedService] sendActions:[NSSet setWithObject:action] withResult:nil];
    return;
  }
  AVRun(@"/usr/bin/killall", @[@"-9", @"SpringBoard"]);
}

static void AVApply(BOOL clearCache) {
  static BOOL applying;
  if (applying) return;
  applying = YES;

  NSDictionary *before = [NSDictionary dictionaryWithContentsOfFile:AVIconMapPath][AVMapIcons] ? : @{};
  if (clearCache) AVClearSystemIconCache();
  AVWriteIconMap();
  // SpringBoard's own icons use the new tokens right away, everyone else reloads on the notification
  AVReloadStoreInThisProcess();
  notify_post(AVNotifyMapChanged);
  NSArray *descriptors = AVHomeScreenDescriptors();

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    AVRestartIconAgent();
    usleep(300 * 1000);
    NSDictionary *after = [NSDictionary dictionaryWithContentsOfFile:AVIconMapPath][AVMapIcons] ? : @{};
    // after a cache wipe every icon has to be rendered again, not just the changed ones
    NSArray *apps = clearCache ? AVAppsToRender(nil, nil) : AVAppsToRender(before, after);
    AVPrerenderIcons(apps, descriptors);
    AVReportProgress(UINT32_MAX, UINT32_MAX);
    dispatch_async(dispatch_get_main_queue(), ^{ AVRespring(); });
  });
}

static void AVApplyNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  BOOL clearCache = CFEqual(name, CFSTR(AVNotifyClearCache));
  dispatch_async(dispatch_get_main_queue(), ^{ AVApply(clearCache); });
}

%ctor {
  @autoreleasepool {
    if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}]) return;
    // themes can be installed or updated by the package manager without going through the app
    if (AVWriteIconMap()) {
      AVReloadStoreInThisProcess();
      AVRestartIconAgent();
      notify_post(AVNotifyMapChanged);
    }
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center, NULL, AVApplyNotification, CFSTR(AVNotifyApply), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, AVApplyNotification, CFSTR(AVNotifyClearCache), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  }
}
