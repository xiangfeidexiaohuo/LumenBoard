#import "LMStatus.h"
#import "LMIconStore.h"
#include <os/lock.h>
#include <stdatomic.h>
#include <unistd.h>

static NSString *const LMCounterNames[LMCounterCount] = {
  @"ThemedIcons", @"ProvidersMade", @"DigestMismatches", @"UnreadableImages",
  @"AgentThemed", @"AgentStock", @"LocalRendered", @"LocalFailed",
};

static _Atomic uint64_t LMCounters[LMCounterCount];
static atomic_bool LMWritePending;
static os_unfair_lock LMStatusLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary *LMValues;
static NSMutableArray<NSString *> *LMEvents;

// only SpringBoard and iconservicesagent report, apps would write over each other
static NSString *LMStatusFile(void) {
  static NSString *path;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *process = [NSProcessInfo processInfo].processName;
    if ([process isEqualToString:@"SpringBoard"] || [process isEqualToString:@"iconservicesagent"]) path = LMStatusPath(process);
  });
  return path;
}

static void LMStatusWrite(void) {
  NSMutableDictionary *counters = [NSMutableDictionary new];
  for (NSUInteger index = 0; index < LMCounterCount; index++) counters[LMCounterNames[index]] = @(atomic_load(&LMCounters[index]));
  os_unfair_lock_lock(&LMStatusLock);
  NSMutableDictionary *status = [LMValues mutableCopy] ? : [NSMutableDictionary new];
  status[LMStatusEvents] = [LMEvents copy] ? : @[];
  os_unfair_lock_unlock(&LMStatusLock);
  status[@"Process"] = [NSProcessInfo processInfo].processName;
  status[@"PID"] = @(getpid());
  status[LMStatusUpdated] = [NSDate date];
  status[LMStatusCounters] = counters;
  status[LMStatusMapIcons] = @([LMIconStore sharedStore].themedIconCount);
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:status format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
  // iconservicesagent may not be allowed to write here, the page then says so
  [data writeToFile:LMStatusFile() options:NSDataWritingAtomic error:nil];
}

static void LMStatusChanged(void) {
  if (!LMStatusFile() || atomic_exchange(&LMWritePending, true)) return;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    atomic_store(&LMWritePending, false);
    @autoreleasepool {
      LMStatusWrite();
    }
  });
}

void LMStatusCount(LMCounter counter) {
  if (counter >= LMCounterCount) return;
  atomic_fetch_add(&LMCounters[counter], 1);
  LMStatusChanged();
}

uint64_t LMStatusCounterValue(LMCounter counter) {
  return (counter < LMCounterCount) ? atomic_load(&LMCounters[counter]) : 0;
}

void LMStatusSet(NSString *key, id value) {
  os_unfair_lock_lock(&LMStatusLock);
  if (!LMValues) LMValues = [NSMutableDictionary new];
  LMValues[key] = value;
  os_unfair_lock_unlock(&LMStatusLock);
  LMStatusChanged();
}

void LMStatusEvent(NSString *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  NSLog(@"[LumenBoard] %@", message);

  static NSDateFormatter *formatter;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss";
  });
  NSString *line = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:[NSDate date]], message];
  os_unfair_lock_lock(&LMStatusLock);
  if (!LMEvents) LMEvents = [NSMutableArray new];
  [LMEvents addObject:line];
  if (LMEvents.count > 30) [LMEvents removeObjectAtIndex:0];
  os_unfair_lock_unlock(&LMStatusLock);
  LMStatusChanged();
}
