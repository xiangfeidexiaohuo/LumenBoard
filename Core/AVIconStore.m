#import "AVIconStore.h"
#include <sys/stat.h>

@implementation AVIconStore {
  NSLock *_lock;
  BOOL _loaded;
  NSDictionary *_icons;
  BOOL _usesSystemIconShape;
  BOOL _keepsIconsInDarkAndTinted;
  // identity of the IconMap.plist that was read (it's replaced atomically, so the inode changes too)
  struct timespec _mapModified;
  ino_t _mapInode;
  CFAbsoluteTime _lastCheck;
}

static BOOL AVStatMap(struct stat *info) {
  return stat(AVIconMapPath.fileSystemRepresentation, info) == 0;
}

static void AVMapChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  [[AVIconStore sharedStore] reload];
}

+ (instancetype)sharedStore {
  static AVIconStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    store = [self new];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AVMapChanged, CFSTR(AVNotifyMapChanged), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  });
  return store;
}

- (instancetype)init {
  if ((self = [super init])) _lock = [NSLock new];
  return self;
}

// Everything is read under one lock: IconServices renders many icons in parallel and none of them may see a half
// loaded map (a stock icon would end up cached under a themed key).
- (void)loadIfNeeded {
  if (_loaded) return;
  struct stat info;
  BOOL exists = AVStatMap(&info);
  _mapModified = exists ? info.st_mtimespec : (struct timespec){ 0, 0 };
  _mapInode = exists ? info.st_ino : 0;
  _lastCheck = CFAbsoluteTimeGetCurrent();
  NSDictionary *map = exists ? [NSDictionary dictionaryWithContentsOfFile:AVIconMapPath] : nil;
  BOOL valid = [map[@"Version"] integerValue] == AVMapVersion && [map[AVMapIcons] isKindOfClass:[NSDictionary class]];
  _icons = valid ? map[AVMapIcons] : @{};
  _usesSystemIconShape = valid && [map[AVConfigUseSystemIconShape] boolValue];
  _keepsIconsInDarkAndTinted = valid && [map[AVConfigKeepIconsInDarkAndTinted] boolValue];
  _loaded = YES;
}

// Called with the lock held. Processes can miss the darwin notification (suspended apps), so every process also
// notices a new map on its own, at most once per second.
- (void)checkMapWithinInterval:(CFTimeInterval)interval {
  if (!_loaded) return;
  CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
  if (now - _lastCheck < interval) return;
  _lastCheck = now;
  struct stat info;
  BOOL exists = AVStatMap(&info);
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
  return ([icon isKindOfClass:[NSDictionary class]] && icon[AVIconLight] && icon[AVIconToken]) ? icon : nil;
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
