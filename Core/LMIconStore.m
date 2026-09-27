#import "LMIconStore.h"
#include <sys/stat.h>

@implementation LMIconStore {
  NSLock *_lock;
  BOOL _loaded;
  NSDictionary *_icons;
  BOOL _usesSystemIconShape;
  BOOL _keepsIconsInDarkAndTinted;
  // mtime and inode of the map we loaded
  struct timespec _mapModified;
  ino_t _mapInode;
  CFAbsoluteTime _lastCheck;
}

static BOOL LMStatMap(struct stat *info) {
  return stat(LMIconMapPath.fileSystemRepresentation, info) == 0;
}

static void LMMapChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  [[LMIconStore sharedStore] reload];
}

+ (instancetype)sharedStore {
  static LMIconStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    store = [self new];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMMapChanged, CFSTR(LMNotifyMapChanged), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  });
  return store;
}

- (instancetype)init {
  if ((self = [super init])) _lock = [NSLock new];
  return self;
}

// IconServices renders on several threads, everything goes through _lock
- (void)loadIfNeeded {
  if (_loaded) return;
  struct stat info;
  BOOL exists = LMStatMap(&info);
  _mapModified = exists ? info.st_mtimespec : (struct timespec){ 0, 0 };
  _mapInode = exists ? info.st_ino : 0;
  _lastCheck = CFAbsoluteTimeGetCurrent();
  NSDictionary *map = exists ? [NSDictionary dictionaryWithContentsOfFile:LMIconMapPath] : nil;
  BOOL valid = [map[@"Version"] integerValue] == LMMapVersion && [map[LMMapIcons] isKindOfClass:[NSDictionary class]];
  // the map has jailbreak paths, turn them into real ones
  NSMutableDictionary *icons = [NSMutableDictionary new];
  if (valid) [map[LMMapIcons] enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSDictionary *entry, BOOL *stop) {
    if (![entry isKindOfClass:[NSDictionary class]]) return;
    NSMutableDictionary *icon = [entry mutableCopy];
    for (NSString *slot in @[LMIconLight, LMIconDark, LMIconTinted])
      if ([entry[slot] isKindOfClass:[NSString class]]) icon[slot] = LMRootPath(entry[slot]);
    icons[bundleID] = icon;
  }];
  _icons = icons;
  _usesSystemIconShape = valid && [map[LMConfigUseSystemIconShape] boolValue];
  _keepsIconsInDarkAndTinted = valid && [map[LMConfigKeepIconsInDarkAndTinted] boolValue];
  _loaded = YES;
}

// lock held. Suspended apps miss the notification, so check the file too
- (void)checkMapWithinInterval:(CFTimeInterval)interval {
  if (!_loaded) return;
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (now - _lastCheck < interval) return;
  _lastCheck = now;
  struct stat info;
  BOOL exists = LMStatMap(&info);
  struct timespec modified = exists ? info.st_mtimespec : (struct timespec){ 0, 0 };
  if (modified.tv_sec != _mapModified.tv_sec || modified.tv_nsec != _mapModified.tv_nsec || (exists ? info.st_ino : 0) != _mapInode) _loaded = NO;
}

- (void)reloadIfMapChanged {
  [_lock lock];
  [self checkMapWithinInterval:0];
  [_lock unlock];
}

- (NSDictionary *)iconForBundleIdentifier:(NSString *)bundleIdentifier {
  if (![bundleIdentifier isKindOfClass:[NSString class]] || !bundleIdentifier.length) return nil;
  NSString *key = bundleIdentifier.lowercaseString;
  [_lock lock];
  [self checkMapWithinInterval:1.0];
  [self loadIfNeeded];
  NSDictionary *icon = _icons[key];
  [_lock unlock];
  return ([icon isKindOfClass:[NSDictionary class]] && icon[LMIconLight] && icon[LMIconToken]) ? icon : nil;
}

- (NSUInteger)themedIconCount {
  [_lock lock];
  [self loadIfNeeded];
  NSUInteger count = _icons.count;
  [_lock unlock];
  return count;
}

- (BOOL)usesSystemIconShape {
  [_lock lock];
  [self loadIfNeeded];
  BOOL value = _usesSystemIconShape;
  [_lock unlock];
  return value;
}

- (BOOL)keepsIconsInDarkAndTinted {
  [_lock lock];
  [self loadIfNeeded];
  BOOL value = _keepsIconsInDarkAndTinted;
  [_lock unlock];
  return value;
}

- (void)reload {
  [_lock lock];
  _loaded = NO;
  _icons = nil;
  [_lock unlock];
}

@end
