#import "LMAppDelegate.h"
#include <sys/resource.h>

int main(int argc, char *argv[]) {
  @autoreleasepool {
    // apps start with 256 open files, reading lots of themes needs more headroom
    struct rlimit limit;
    if (getrlimit(RLIMIT_NOFILE, &limit) == 0 && limit.rlim_cur < 4096) {
      limit.rlim_cur = MIN((rlim_t)4096, limit.rlim_max);
      setrlimit(RLIMIT_NOFILE, &limit);
    }
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([LMAppDelegate class]));
  }
}
