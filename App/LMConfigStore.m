#import "LMConfigStore.h"
#include <sys/stat.h>

@implementation LMConfigStore {
  NSDictionary *_appliedConfig;
}

+ (instancetype)sharedStore {
  static LMConfigStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    store = [self new];
  });
  return store;
}

- (instancetype)init {
  if ((self = [super init])) {
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:LMConfigPath] ? : @{};
    NSArray *themes = config[LMConfigEnabledThemes];
    _enabledThemes = [themes isKindOfClass:[NSArray class]] ? [themes copy] : @[];
    _useSystemIconShape = [config[LMConfigUseSystemIconShape] boolValue];
    _keepIconsInDarkAndTinted = [config[LMConfigKeepIconsInDarkAndTinted] boolValue];
    // what SpringBoard last applied, so the app knows about pending changes even after a restart
    NSDictionary *applied = [NSDictionary dictionaryWithContentsOfFile:LMIconMapPath][LMMapAppliedConfig];
    _appliedConfig = [applied isKindOfClass:[NSDictionary class]] ? applied : [self dictionaryRepresentation];
  }
  return self;
}

- (NSDictionary *)dictionaryRepresentation {
  return @{
    LMConfigEnabledThemes : _enabledThemes ? : @[],
    LMConfigUseSystemIconShape : @(_useSystemIconShape),
    LMConfigKeepIconsInDarkAndTinted : @(_keepIconsInDarkAndTinted)
  };
}

- (BOOL)hasUnappliedChanges {
  return ![[self dictionaryRepresentation] isEqual:_appliedConfig];
}

- (BOOL)save:(NSError **)error {
  if (![[NSFileManager defaultManager] createDirectoryAtPath:LMDataDirectory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:[self dictionaryRepresentation] format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
  if (!data || ![data writeToFile:LMConfigPath options:NSDataWritingAtomic error:error]) return NO;
  chmod(LMConfigPath.fileSystemRepresentation, 0644);
  return YES;
}

- (void)markApplied {
  _appliedConfig = [self dictionaryRepresentation];
}

@end
