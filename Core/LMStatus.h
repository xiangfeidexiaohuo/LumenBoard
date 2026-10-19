#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// What the icon hooks did in this process. SpringBoard and iconservicesagent save it to Status-<process>.plist
// (a few seconds after the last change) for the diagnostics page in the app.
typedef NS_ENUM(NSUInteger, LMCounter) {
  LMCounterThemedIcons,      // icons that got a themed digest
  LMCounterProvidersMade,    // theme artwork handed to IconServices
  LMCounterDigestMismatches, // requests for a themed app whose digest isn't ours
  LMCounterUnreadableImages, // theme png that couldn't be loaded
  LMCounterAgentThemed,      // theme icons iconservicesagent rendered with the theme
  LMCounterAgentStock,       // theme icons iconservicesagent rendered without it
  LMCounterLocalRendered,    // theme icons rendered in this process instead
  LMCounterLocalFailed,
  LMCounterCount,
};

void LMStatusCount(LMCounter counter);
uint64_t LMStatusCounterValue(LMCounter counter);
void LMStatusSet(NSString *key, id value);
void LMStatusEvent(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
