#import "AVConfigStore.h"
#include <sys/stat.h>

@implementation AVConfigStore {
  NSDictionary *_appliedConfig;
}

+ (instancetype)sharedStore {
  static AVConfigStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    store = [self new];
  });
  return store;
}

- (instancetype)init {
  if ((self = [super init])) {
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:AVConfigPath] ? : @{};
    NSArray *themes = config[AVConfigEnabledThemes];
    _enabledThemes = [themes isKindOfClass:[NSArray class]] ? [themes copy] : @[];
    _useSystemIconShape = [config[AVConfigUseSystemIconShape] boolValue];
    _keepIconsInDarkAndTinted = [config[AVConfigKeepIconsInDarkAndTinted] boolValue];
    // what SpringBoard last applied, so the app knows about pending changes even after a restart
    NSDictionary *applied = [NSDictionary dictionaryWithContentsOfFile:AVIconMapPath][AVMapAppliedConfig];
    _appliedConfig = [applied isKindOfClass:[NSDictionary class]] ? applied : [self dictionaryRepresentation];
  }
  return self;
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    AVConfigEnabledThemes : _enabledThemes ? : @[],
    AVConfigUseSystemIconShape : @(_useSystemIconShape),
    AVConfigKeepIconsInDarkAndTinted : @(_keepIconsInDarkAndTinted)
  };
}

- (BOOL)hasUnappliedChanges {
  return ![[self dictionaryRepresentation] isEqual:_appliedConfig];
}

- (BOOL)save:(NSError **)error {
  if (![[NSFileManager defaultManager] createDirectoryAtPath:AVDataDirectory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:[self dictionaryRepresentation] format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
  if (!data || ![data writeToFile:AVConfigPath options:NSDataWritingAtomic error:error]) return NO;
  chmod(AVConfigPath.fileSystemRepresentation, 0644);
  return YES;
}

- (void)markApplied {
  _appliedConfig = [self dictionaryRepresentation];
}

@end
