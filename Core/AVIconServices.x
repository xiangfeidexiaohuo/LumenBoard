// App icon theming for iOS 17 – 26.
//
// Every app icon on the system (home screen, App Library, Spotlight, Settings, notifications, share sheets) is an
// IconServices icon: [[ISIcon alloc] initWithBundleIdentifier:] creates an ISBundleIdentifierIcon whose `digest` is the
// key into the shared icon cache. On a cache miss iconservicesagent renders the icon: it asks the icon for a resource
// provider and composites the provider's artwork with a recipe (ISiOSAppRecipe: plate, squircle mask, dark/tint effects).
//
// Avalanche:
//  1. derives a different digest for themed icons in every process, from the stock digest and the icon's token.
//     Themed icons live in their own cache entries: stock icons cached before can't show up, and once rendered a
//     themed icon loads instantly. A new theme or setting changes the token, so nothing stale is ever reused.
//  2. gives iconservicesagent a provider with the theme artwork when it renders such an icon.
//  3. optionally renders theme icons with their own shape and transparency (a recipe without plate and mask).

#import "AVIconStore.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>

@interface ISConcreteIcon : NSObject
- (NSUUID *)digest;
@end

@interface ISBundleIdentifierIcon : ISConcreteIcon
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
- (NSString *)bundleIdentifier;
@end

@interface ISBundleIcon : ISConcreteIcon
- (instancetype)initWithBundleURL:(NSURL *)url type:(NSString *)type tag:(NSString *)tag tagClass:(NSString *)tagClass;
- (NSURL *)url;
@end

@interface ISApplicationIdentityIcon : ISConcreteIcon
- (instancetype)initWithApplicationIdentity:(id)identity;
- (NSString *)identityString;
@end

@interface ISResourceProvider : NSObject
- (instancetype)initWithResource:(id)resource templateResource:(id)templateResource;
- (void)setResourceType:(unsigned long long)resourceType;
- (void)setAllowNonDefaultAppearances:(BOOL)allow;
- (void)setAllowAlterationsToResourceArt:(BOOL)allow;
- (void)setIconResource:(id)resource;
- (void)setSuggestedRecipe:(id)recipe;
@end

@interface IFImage : NSObject
- (instancetype)initWithCGImage:(CGImageRef)image scale:(double)scale;
@end

@interface IFImageBag : NSObject
- (instancetype)initWithImages:(NSArray *)images;
@end

@interface LSApplicationRecord : NSObject
- (instancetype)initWithURL:(NSURL *)url allowPlaceholder:(BOOL)allowPlaceholder error:(NSError **)error;
- (NSString *)bundleIdentifier;
@end

@interface LSApplicationIdentity : NSObject
- (instancetype)initWithIdentityString:(NSString *)identityString;
- (NSString *)bundleIdentifier;
@end

static BOOL AVHooksInstalled;
static Ivar AVDigestIvar;
static Class AVProviderClass;
static Class AVRecipeClass;
static NSCache *AVImageBags;
static NSCache *AVAppURLIdentifiers;
static char AVIconEntryKey;

#pragma mark - Digests

static NSUUID *AVThemedDigest(NSUUID *stockDigest, NSString *token) {
  uuid_t bytes;
  [stockDigest getUUIDBytes:bytes];
  NSData *tokenData = [token dataUsingEncoding:NSUTF8StringEncoding];
  CC_SHA256_CTX context;
  CC_SHA256_Init(&context);
  CC_SHA256_Update(&context, "avalanche-theme-icon", 20);
  CC_SHA256_Update(&context, bytes, sizeof(bytes));
  CC_SHA256_Update(&context, tokenData.bytes, (CC_LONG)tokenData.length);
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(hash, &context);
  // shaped like a name-based (v5) UUID
  hash[6] = (hash[6] & 0x0F) | 0x50;
  hash[8] = (hash[8] & 0x3F) | 0x80;
  return [[NSUUID alloc] initWithUUIDBytes:hash];
}

static void AVMarkThemed(ISConcreteIcon *icon, NSString *bundleIdentifier) {
  if (!icon) return;
  NSDictionary *entry = [[AVIconStore sharedStore] iconForBundleIdentifier:bundleIdentifier];
  if (!entry) return;
  id stockDigest = object_getIvar(icon, AVDigestIvar);
  if (![stockDigest isKindOfClass:[NSUUID class]]) return;
  object_setIvarWithStrongDefault(icon, AVDigestIvar, AVThemedDigest(stockDigest, entry[AVIconToken]));
}

static NSString *AVBundleIdentifierForAppURL(NSURL *url) {
  if (!url.isFileURL || [url.pathExtension caseInsensitiveCompare:@"app"] != NSOrderedSame) return nil;
  NSString *cached = [AVAppURLIdentifiers objectForKey:url.path];
  if (cached) return cached.length ? cached : nil;
  NSString *bundleIdentifier = nil;
  Class recordClass = objc_getClass("LSApplicationRecord");
  if ([recordClass instancesRespondToSelector:@selector(initWithURL:allowPlaceholder:error:)])
    bundleIdentifier = [[[recordClass alloc] initWithURL:url allowPlaceholder:YES error:nil] bundleIdentifier];
  if (!bundleIdentifier) bundleIdentifier = [NSBundle bundleWithURL:url].bundleIdentifier;
  [AVAppURLIdentifiers setObject:(bundleIdentifier ? : @"") forKey:url.path];
  return bundleIdentifier;
}

static NSString *AVBundleIdentifierForIdentity(id identity) {
  return [identity respondsToSelector:@selector(bundleIdentifier)] ? [identity bundleIdentifier] : nil;
}

#pragma mark - Artwork

static id AVImageBag(NSString *path) {
  if (!path.length) return nil;
  id bag = [AVImageBags objectForKey:path];
  if (bag) return bag;

  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path isDirectory:NO], NULL);
  CGImageRef image = (source && CGImageSourceGetCount(source)) ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
  if (source) CFRelease(source);
  if (!image) return nil;

  NSString *name = path.lastPathComponent.lowercaseString;
  double scale = [name containsString:@"@3x"] ? 3.0 : ([name containsString:@"@2x"] ? 2.0 : 1.0);
  IFImage *artwork = (CGImageGetWidth(image) && CGImageGetHeight(image)) ? [[objc_getClass("IFImage") alloc] initWithCGImage:image scale:scale] : nil;
  CGImageRelease(image);
  if (!artwork) return nil;

  bag = [[objc_getClass("IFImageBag") alloc] initWithImages:@[artwork]];
  if (bag) [AVImageBags setObject:bag forKey:path];
  return bag;
}

// AVThemeIconProvider -configureProviderFromDescriptor: picks the theme's dark/tinted artwork for those appearances
static void AVProviderConfigure(ISResourceProvider *self, SEL _cmd, id descriptor) {
  NSDictionary *entry = objc_getAssociatedObject(self, &AVIconEntryKey);
  long long appearance = [descriptor respondsToSelector:@selector(appearance)] ? ((long long (*)(id, SEL))objc_msgSend)(descriptor, @selector(appearance)) : 0;
  NSString *variant = (appearance == 1) ? entry[AVIconDark] : ((appearance == 2) ? entry[AVIconTinted] : nil);
  id bag = AVImageBag(variant);
  if (bag) {
    [self setIconResource:bag];
    // the theme drew this appearance itself, don't let iOS derive it again
    if ([self respondsToSelector:@selector(setAllowAlterationsToResourceArt:)]) [self setAllowAlterationsToResourceArt:NO];
  }
  struct objc_super superclass = { self, class_getSuperclass(AVProviderClass) };
  ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&superclass, _cmd, descriptor);
}

// AVThemeIconRecipe: the iOS app icon recipe without the squircle mask...
static BOOL AVRecipeShouldApplyMask(id self, SEL _cmd) {
  return NO;
}

// ...and without the white (dark/tinted: black) plate iOS puts under every icon, which would fill transparent corners
static id AVRecipePrimaryEffect(id self, SEL _cmd, id __autoreleasing *backgroundContent) {
  struct objc_super superclass = { self, class_getSuperclass(AVRecipeClass) };
  id effect = ((id (*)(struct objc_super *, SEL, id __autoreleasing *))objc_msgSendSuper)(&superclass, _cmd, backgroundContent);
  if (backgroundContent) *backgroundContent = nil;
  return effect;
}

static ISResourceProvider *AVMakeProvider(NSDictionary *entry) {
  id bag = AVImageBag(entry[AVIconLight]);
  if (!bag || !AVProviderClass) return nil;
  ISResourceProvider *provider = [[AVProviderClass alloc] initWithResource:bag templateResource:nil];
  if (!provider) return nil;
  objc_setAssociatedObject(provider, &AVIconEntryKey, entry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  AVIconStore *store = [AVIconStore sharedStore];
  // 1 = app icon: sized and composited like any app icon, dark/tinted derived like for apps without such artwork
  if ([provider respondsToSelector:@selector(setResourceType:)]) [provider setResourceType:1];
  if ([provider respondsToSelector:@selector(setAllowNonDefaultAppearances:)]) [provider setAllowNonDefaultAppearances:!store.keepsIconsInDarkAndTinted];
  if ([provider respondsToSelector:@selector(setAllowAlterationsToResourceArt:)]) [provider setAllowAlterationsToResourceArt:YES];
  // used for plain descriptors (SpringBoard, Settings...); explicit shapes (circles, app clips) keep Apple's recipe
  if (!store.usesSystemIconShape && AVRecipeClass && [provider respondsToSelector:@selector(setSuggestedRecipe:)]) [provider setSuggestedRecipe:[AVRecipeClass new]];
  return provider;
}

// Theme the icon only if the requesting process asked for the themed digest. A process without Avalanche asked for
// the stock icon and must get it, otherwise the stock cache entry would end up holding the theme icon.
static ISResourceProvider *AVProviderForRequest(ISConcreteIcon *request, NSString *bundleIdentifier, ISConcreteIcon *(^themedTwin)(void)) {
  if (!bundleIdentifier) return nil;
  // SpringBoard writes the map before anyone uses its tokens: with the newest map on disk we never know less than
  // the process that asked, so a themed request is never answered with the stock icon.
  [[AVIconStore sharedStore] reloadIfMapChanged];
  NSDictionary *entry = [[AVIconStore sharedStore] iconForBundleIdentifier:bundleIdentifier];
  if (!entry) return nil;
  NSUUID *expected = [themedTwin() digest];
  if (!expected || ![expected isEqual:[request digest]]) return nil;
  return AVMakeProvider(entry);
}

#pragma mark - Hooks

%group Icons

%hook ISBundleIdentifierIcon

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier {
  self = %orig;
  AVMarkThemed(self, bundleIdentifier);
  return self;
}

// allowFallback is NO for -makeSymbolResourceProvider (the app's SF symbol), which stays stock
- (id)_makeResourceProviderAllowIconResourceFallback:(BOOL)allowFallback {
  if (allowFallback) {
    NSString *bundleIdentifier = [self bundleIdentifier];
    ISResourceProvider *provider = AVProviderForRequest(self, bundleIdentifier, ^ISConcreteIcon *{
      return [[%c(ISBundleIdentifierIcon) alloc] initWithBundleIdentifier:bundleIdentifier];
    });
    if (provider) return provider;
  }
  return %orig;
}

%end

%hook ISBundleIcon

- (instancetype)initWithBundleURL:(NSURL *)url type:(NSString *)type tag:(NSString *)tag tagClass:(NSString *)tagClass {
  self = %orig;
  // without a type or tag this is the bundle's app icon (same test as -[ISBundleIcon makeResourceProvider])
  if (!type && !(tag && tagClass)) AVMarkThemed(self, AVBundleIdentifierForAppURL(url));
  return self;
}

- (id)_makeAppResourceProvider {
  NSURL *url = [self url];
  ISResourceProvider *provider = AVProviderForRequest(self, AVBundleIdentifierForAppURL(url), ^ISConcreteIcon *{
    return [[%c(ISBundleIcon) alloc] initWithBundleURL:url type:nil tag:nil tagClass:nil];
  });
  return provider ? : %orig;
}

%end

%hook ISApplicationIdentityIcon

- (instancetype)initWithApplicationIdentity:(id)identity {
  self = %orig;
  AVMarkThemed(self, AVBundleIdentifierForIdentity(identity));
  return self;
}

- (id)_makeResourceProviderAllowIconResourceFallback:(BOOL)allowFallback {
  Class identityClass = objc_getClass("LSApplicationIdentity");
  NSString *identityString = [self identityString];
  if (allowFallback && identityString && [identityClass instancesRespondToSelector:@selector(initWithIdentityString:)]) {
    id identity = [[identityClass alloc] initWithIdentityString:identityString];
    ISResourceProvider *provider = AVProviderForRequest(self, AVBundleIdentifierForIdentity(identity), ^ISConcreteIcon *{
      return [[%c(ISApplicationIdentityIcon) alloc] initWithApplicationIdentity:identity];
    });
    if (provider) return provider;
  }
  return %orig;
}

%end

%end

#pragma mark - Setup

static Class AVSubclass(Class base, const char *name) {
  Class existing = objc_getClass(name);
  if (existing) return existing;
  Class subclass = base ? objc_allocateClassPair(base, name, 0) : Nil;
  return subclass;
}

static void AVInstallIconHooks(void) {
  if (AVHooksInstalled) return;
  Class concreteIcon = objc_getClass("ISConcreteIcon");
  Class providerBase = objc_getClass("ISResourceProvider");
  if (!concreteIcon || !providerBase || !objc_getClass("ISBundleIdentifierIcon") || !objc_getClass("IFImage") || !objc_getClass("IFImageBag")) return;
  // the digest is the cache key; without it themed and stock icons would share cache entries
  Ivar digest = class_getInstanceVariable(concreteIcon, "_digest");
  if (!digest || ![providerBase instancesRespondToSelector:@selector(initWithResource:templateResource:)]) return;
  AVHooksInstalled = YES;
  AVDigestIvar = digest;
  AVImageBags = [NSCache new];
  AVImageBags.countLimit = 300;
  AVAppURLIdentifiers = [NSCache new];

  Class provider = AVSubclass(providerBase, "AVThemeIconProvider");
  if (provider && !objc_getClass("AVThemeIconProvider")) {
    class_addMethod(provider, @selector(configureProviderFromDescriptor:), (IMP)AVProviderConfigure, "v@:@");
    objc_registerClassPair(provider);
  }
  AVProviderClass = provider;

  Class appRecipe = objc_getClass("ISiOSAppRecipe");
  Class recipe = AVSubclass(appRecipe, "AVThemeIconRecipe");
  if (recipe && !objc_getClass("AVThemeIconRecipe")) {
    class_addMethod(recipe, @selector(shouldApplyMask), (IMP)AVRecipeShouldApplyMask, "B@:");
    SEL primaryEffect = @selector(primaryResourceEffectReturningBackgroundContentOverride:);
    if (class_getInstanceMethod(appRecipe, primaryEffect)) class_addMethod(recipe, primaryEffect, (IMP)AVRecipePrimaryEffect, "@@:^@");
    objc_registerClassPair(recipe);
  }
  AVRecipeClass = recipe;

  %init(Icons);
}

static void AVImageAdded(const struct mach_header *header, intptr_t slide) {
  if (AVHooksInstalled) return;
  Dl_info info;
  if (!dladdr(header, &info) || !info.dli_fname || !strstr(info.dli_fname, "/IconServices.framework/")) return;
  // IconServices was loaded after us; its classes are usable once dyld is done with it
  dispatch_async(dispatch_get_main_queue(), ^{ AVInstallIconHooks(); });
}

%ctor {
  @autoreleasepool {
    if (![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){17, 0, 0}]) return;
    AVInstallIconHooks();
    if (!AVHooksInstalled) _dyld_register_func_for_add_image(AVImageAdded);
  }
}
