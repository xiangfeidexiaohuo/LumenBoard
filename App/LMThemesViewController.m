#import "LMThemesViewController.h"
#import "LMSettingsViewController.h"
#import "LMApplyViewController.h"
#import "LMConfigStore.h"
#import "../Shared/LMThemeLibrary.h"
#import <ImageIO/ImageIO.h>
#include <sys/stat.h>

typedef NS_ENUM(NSInteger, LMThemeSection) {
  LMThemeSectionActive,
  LMThemeSectionInstalled,
};

// shown in the theme previews when the theme has them
static NSArray<NSString *> *LMPreviewApps(void) {
  return @[@"com.apple.mobilesafari", @"com.apple.mobilesms", @"com.apple.mobilephone", @"com.apple.camera",
           @"com.apple.mobileslideshow", @"com.apple.preferences", @"com.apple.appstore", @"com.apple.mobilemail"];
}

// decodes only what the preview needs, theme icons are often 1024 px
static UIImage *LMThumbnail(NSString *path, CGFloat pixels) {
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path isDirectory:NO], NULL);
  if (!source) return nil;
  NSDictionary *options = @{
    (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
    (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
    (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(pixels),
  };
  CGImageRef image = CGImageSourceGetCount(source) ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options) : NULL;
  CFRelease(source);
  if (!image) return nil;
  UIImage *thumbnail = [UIImage imageWithCGImage:image];
  CGImageRelease(image);
  return thumbnail;
}

// changes when the theme is reinstalled or icons are added or removed
static NSString *LMThemeStamp(NSString *theme) {
  NSString *directory = [LMThemesDirectory stringByAppendingPathComponent:theme];
  NSMutableString *stamp = [NSMutableString new];
  for (NSString *folder in @[@"", @"IconBundles", @"Icons"]) {
    struct stat info;
    if (stat([directory stringByAppendingPathComponent:folder].fileSystemRepresentation, &info) == 0) [stamp appendFormat:@"%lld.%ld/", (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
    else [stamp appendString:@"-/"];
  }
  return stamp;
}

static UIImage *LMRenderPreview(NSArray<NSString *> *paths) {
  const CGFloat side = 44, gap = 3;
  NSUInteger count = MIN(paths.count, (NSUInteger)4);
  CGFloat tile = (count == 1) ? side : (side - gap) / 2;
  NSMutableArray<UIImage *> *icons = [NSMutableArray new];
  for (NSUInteger index = 0; index < count; index++) {
    UIImage *icon = LMThumbnail(paths[index], tile * 3);
    if (icon) [icons addObject:icon];
  }
  if (!icons.count) return nil;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    for (NSUInteger index = 0; index < icons.count; index++) {
      UIImage *icon = icons[index];
      CGRect rect = (count == 1) ? CGRectMake(0, 0, side, side) : CGRectMake((index % 2) * (tile + gap), (index / 2) * (tile + gap), tile, tile);
      CGContextSaveGState(context.CGContext);
      [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:tile * 0.225] addClip];
      [icon drawInRect:rect];
      CGContextRestoreGState(context.CGContext);
    }
  }];
}

@implementation LMThemesViewController {
  NSMutableArray<NSString *> *_active;
  NSMutableArray<NSString *> *_installed;
  // theme -> preview, icon count and the stamp they were loaded with
  NSMutableDictionary<NSString *, NSDictionary *> *_details;
  NSMutableSet<NSString *> *_loading;
  dispatch_queue_t _detailsQueue;
  NSTimer *_changeTimer;
  UIButton *_applyButton;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"LumenBoard";
  _details = [NSMutableDictionary new];
  _loading = [NSMutableSet new];
  // one theme at a time, so the visible ones are done first
  _detailsQueue = dispatch_queue_create("com.xsxs18.lumenboard.theme-details", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
  [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Theme"];
  self.tableView.rowHeight = 64;
  self.tableView.allowsSelectionDuringEditing = YES;

  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(showSettings)];
  self.navigationItem.rightBarButtonItem = self.editButtonItem;

  __weak typeof(self) weakSelf = self;
  UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
  configuration.title = LMLocalized(@"Apply");
  configuration.image = [UIImage systemImageNamed:@"square.grid.2x2"];
  configuration.imagePadding = 8;
  configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
  configuration.buttonSize = UIButtonConfigurationSizeLarge;
  configuration.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
  _applyButton = [UIButton buttonWithConfiguration:configuration primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
    [weakSelf apply];
  }]];
  UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
  self.toolbarItems = @[space, [[UIBarButtonItem alloc] initWithCustomView:_applyButton], space];

  self.refreshControl = [UIRefreshControl new];
  [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadThemes) name:UIApplicationWillEnterForegroundNotification object:nil];
  [self reloadThemes];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  // the package manager may still be installing themes in the background
  [_changeTimer invalidate];
  __weak typeof(self) weakSelf = self;
  _changeTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
    [weakSelf checkForThemeChanges];
  }];
}

- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  [_changeTimer invalidate];
  _changeTimer = nil;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:NO animated:animated];
  [self updateApplyButton];
}

#pragma mark - Data

- (void)reloadThemes {
  [LMThemeLibrary invalidate];
  NSArray *installed = [LMThemeLibrary installedThemes];
  NSMutableArray *active = [NSMutableArray new];
  for (NSString *theme in [LMConfigStore sharedStore].enabledThemes)
    if ([theme isKindOfClass:[NSString class]] && [installed containsObject:theme] && ![active containsObject:theme]) [active addObject:theme];
  _active = active;
  _installed = [installed mutableCopy];
  [_installed removeObjectsInArray:active];
  // keep the previews of themes whose files didn't change, try the ones that couldn't be read again
  for (NSString *theme in _details.allKeys)
    if (![installed containsObject:theme] || _details[theme][@"Error"] || ![_details[theme][@"Stamp"] isEqualToString:LMThemeStamp(theme)]) [_details removeObjectForKey:theme];
  // themes that were uninstalled drop out of the configuration
  if (![active isEqualToArray:[LMConfigStore sharedStore].enabledThemes]) [self saveActiveThemes];

  [self.refreshControl endRefreshing];
  [self.tableView reloadData];
  [self updateEmptyState];
  [self updateApplyButton];
}

// pull to refresh: read every theme again
- (void)refresh {
  [_details removeAllObjects];
  [self reloadThemes];
}

- (void)checkForThemeChanges {
  if (self.tableView.isEditing) return;
  NSMutableSet *known = [NSMutableSet setWithArray:_active];
  [known addObjectsFromArray:_installed];
  if (![[NSSet setWithArray:[LMThemeLibrary installedThemes]] isEqualToSet:known]) {
    [self reloadThemes];
    return;
  }
  // icons added or removed since the preview was made
  for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
    NSString *theme = [self themeAtIndexPath:indexPath];
    NSDictionary *details = theme ? _details[theme] : nil;
    if (!details || [details[@"Stamp"] isEqualToString:LMThemeStamp(theme)]) continue;
    [_details removeObjectForKey:theme];
    [LMThemeLibrary invalidateTheme:theme];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (cell) [self configureCell:cell atIndexPath:indexPath];
  }
}

- (NSString *)themeAtIndexPath:(NSIndexPath *)indexPath {
  NSArray *themes = (indexPath.section == LMThemeSectionActive) ? _active : _installed;
  return (indexPath.row < (NSInteger)themes.count) ? themes[indexPath.row] : nil;
}

- (BOOL)saveActiveThemes {
  [LMConfigStore sharedStore].enabledThemes = _active;
  NSError *error;
  if ([[LMConfigStore sharedStore] save:&error]) {
    [self updateApplyButton];
    return YES;
  }
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't save") message:[NSString stringWithFormat:LMLocalized(@"%@\n\nLumenBoard has to be installed as a package (not as an IPA) so it can write its settings."), error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
  return NO;
}

- (void)loadDetailsForTheme:(NSString *)theme {
  if (!theme || [_loading containsObject:theme]) return;
  [_loading addObject:theme];
  dispatch_async(_detailsQueue, ^{
    NSString *stamp = LMThemeStamp(theme);
    NSDictionary *icons = [LMThemeLibrary iconsInTheme:theme];
    NSMutableArray *paths = [NSMutableArray new];
    for (NSString *bundleID in LMPreviewApps()) {
      NSString *path = icons[bundleID][LMIconLight];
      if (path && paths.count < 4) [paths addObject:path];
    }
    for (NSString *bundleID in [icons.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
      if (paths.count >= 4) break;
      NSString *path = icons[bundleID][LMIconLight];
      if (path && ![paths containsObject:path]) [paths addObject:path];
    }
    NSMutableDictionary *details = [NSMutableDictionary new];
    details[@"Stamp"] = stamp;
    details[@"Count"] = @(icons.count + [LMThemeLibrary iconsByAppNameInTheme:theme].count);
    details[@"Error"] = [LMThemeLibrary readErrorForTheme:theme];
    details[@"Preview"] = LMRenderPreview(paths);
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_loading removeObject:theme];
      self->_details[theme] = details;
      // update the cell on screen itself, a dequeued cell would be a different one
      for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        if (![[self themeAtIndexPath:indexPath] isEqualToString:theme]) continue;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        if (cell) [self configureCell:cell atIndexPath:indexPath];
      }
    });
  });
}

#pragma mark - UI state

- (void)updateEmptyState {
  if (_active.count + _installed.count) {
    self.tableView.backgroundView = nil;
    return;
  }
  UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.grid.2x2" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightLight]]];
  image.tintColor = [UIColor tertiaryLabelColor];
  UILabel *title = [UILabel new];
  title.text = LMLocalized(@"No themes installed");
  title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
  UILabel *detail = [UILabel new];
  detail.text = [NSString stringWithFormat:LMLocalized(@"Install themes from your package manager. They are stored in %@."), LMThemesDirectoryDisplayName];
  detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
  detail.textColor = [UIColor secondaryLabelColor];
  detail.numberOfLines = 0;
  detail.textAlignment = NSTextAlignmentCenter;
  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[image, title, detail]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 10;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  UIView *background = [UIView new];
  [background addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.centerYAnchor constraintEqualToAnchor:background.centerYAnchor constant:-40],
    [stack.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:32],
    [stack.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-32],
  ]];
  self.tableView.backgroundView = background;
}

- (void)updateApplyButton {
  UIButtonConfiguration *configuration = _applyButton.configuration;
  configuration.subtitle = [LMConfigStore sharedStore].hasUnappliedChanges ? LMLocalized(@"Changes not applied yet") : nil;
  _applyButton.configuration = configuration;
  [_applyButton sizeToFit];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
  [super setEditing:editing animated:animated];
  [self.tableView setEditing:editing animated:animated];
}

#pragma mark - Actions

- (void)showSettings {
  [self.navigationController pushViewController:[LMSettingsViewController new] animated:YES];
}

- (void)apply {
  if (![self saveActiveThemes]) return;
  [self presentViewController:[[LMApplyViewController alloc] initWithClearingIconCache:NO] animated:YES completion:^{
    [self updateApplyButton];
  }];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return (_active.count + _installed.count) ? 2 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return (section == LMThemeSectionActive) ? _active.count : _installed.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  return (section == LMThemeSectionActive) ? LMLocalized(@"Active") : LMLocalized(@"Installed");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  if (section == LMThemeSectionActive)
    return _active.count ? LMLocalized(@"When several themes have an icon for the same app, the one higher up wins. Tap Edit to change the order.") : LMLocalized(@"Tap a theme below to activate it.");
  return _installed.count ? nil : LMLocalized(@"All installed themes are active.");
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
  NSString *theme = [self themeAtIndexPath:indexPath];
  NSDictionary *details = theme ? _details[theme] : nil;
  if (!details) [self loadDetailsForTheme:theme];

  UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
  content.text = theme ? [LMThemeLibrary displayNameForTheme:theme] : nil;
  content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  if (details[@"Error"]) content.secondaryText = LMLocalized(@"Couldn't read this theme, pull down to try again");
  else if (details) content.secondaryText = [NSString localizedStringWithFormat:LMLocalized(@"%lu icons"), (unsigned long)[details[@"Count"] unsignedIntegerValue]];
  else content.secondaryText = LMLocalized(@"Loading…");
  content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  content.image = details[@"Preview"] ? : [UIImage systemImageNamed:@"square.grid.2x2"];
  content.imageProperties.maximumSize = CGSizeMake(44, 44);
  content.imageProperties.reservedLayoutSize = CGSizeMake(44, 44);
  content.imageProperties.tintColor = [UIColor tertiaryLabelColor];
  cell.contentConfiguration = content;
  cell.accessoryType = (indexPath.section == LMThemeSectionActive) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
  cell.showsReorderControl = YES;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Theme" forIndexPath:indexPath];
  [self configureCell:cell atIndexPath:indexPath];
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSString *theme = [self themeAtIndexPath:indexPath];
  if (!theme) return;
  NSIndexPath *destination;
  if (indexPath.section == LMThemeSectionActive) {
    [_active removeObjectAtIndex:indexPath.row];
    NSUInteger position = [_installed indexOfObject:theme inSortedRange:NSMakeRange(0, _installed.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(NSString *a, NSString *b) {
      return [[LMThemeLibrary displayNameForTheme:a] localizedCaseInsensitiveCompare:[LMThemeLibrary displayNameForTheme:b]];
    }];
    [_installed insertObject:theme atIndex:position];
    destination = [NSIndexPath indexPathForRow:position inSection:LMThemeSectionInstalled];
  } else {
    [_installed removeObjectAtIndex:indexPath.row];
    [_active addObject:theme];
    destination = [NSIndexPath indexPathForRow:_active.count - 1 inSection:LMThemeSectionActive];
  }
  [tableView performBatchUpdates:^{
    [tableView moveRowAtIndexPath:indexPath toIndexPath:destination];
  } completion:^(BOOL finished) {
    [tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationNone];
  }];
  [self saveActiveThemes];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
  return indexPath.section == LMThemeSectionActive;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
  if (proposed.section == LMThemeSectionActive) return proposed;
  return [NSIndexPath indexPathForRow:(_active.count ? _active.count - 1 : 0) inSection:LMThemeSectionActive];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
  NSString *theme = _active[source.row];
  [_active removeObjectAtIndex:source.row];
  [_active insertObject:theme atIndex:destination.row];
  [self saveActiveThemes];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
  return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
  return NO;
}

@end
