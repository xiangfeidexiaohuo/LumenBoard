#import "AVThemesViewController.h"
#import "AVSettingsViewController.h"
#import "AVApplyViewController.h"
#import "AVConfigStore.h"
#import "../Shared/AVThemeLibrary.h"

typedef NS_ENUM(NSInteger, AVThemeSection) {
  AVThemeSectionActive,
  AVThemeSectionInstalled,
};

// shown in the theme previews when the theme has them
static NSArray<NSString *> *AVPreviewApps(void) {
  return @[@"com.apple.mobilesafari", @"com.apple.mobilesms", @"com.apple.mobilephone", @"com.apple.camera",
           @"com.apple.mobileslideshow", @"com.apple.preferences", @"com.apple.appstore", @"com.apple.mobilemail"];
}

static UIImage *AVRenderPreview(NSArray<NSString *> *paths) {
  if (!paths.count) return nil;
  const CGFloat side = 44, gap = 3;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    NSUInteger count = MIN(paths.count, (NSUInteger)4);
    CGFloat tile = (count == 1) ? side : (side - gap) / 2;
    for (NSUInteger index = 0; index < count; index++) {
      UIImage *icon = [[UIImage imageWithContentsOfFile:paths[index]] imageByPreparingThumbnailOfSize:CGSizeMake(tile * 3, tile * 3)];
      if (!icon) continue;
      CGRect rect = (count == 1) ? CGRectMake(0, 0, side, side) : CGRectMake((index % 2) * (tile + gap), (index / 2) * (tile + gap), tile, tile);
      CGContextSaveGState(context.CGContext);
      [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:tile * 0.225] addClip];
      [icon drawInRect:rect];
      CGContextRestoreGState(context.CGContext);
    }
  }];
}

@implementation AVThemesViewController {
  NSMutableArray<NSString *> *_active;
  NSMutableArray<NSString *> *_installed;
  NSMutableDictionary<NSString *, UIImage *> *_previews;
  NSMutableDictionary<NSString *, NSNumber *> *_iconCounts;
  NSMutableSet<NSString *> *_loading;
  UIButton *_applyButton;
}

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Avalanche";
  _previews = [NSMutableDictionary new];
  _iconCounts = [NSMutableDictionary new];
  _loading = [NSMutableSet new];
  self.tableView.rowHeight = 64;
  self.tableView.allowsSelectionDuringEditing = YES;

  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"] style:UIBarButtonItemStylePlain target:self action:@selector(showSettings)];
  self.navigationItem.rightBarButtonItem = self.editButtonItem;

  __weak typeof(self) weakSelf = self;
  UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
  configuration.title = AVLocalized(@"Apply");
  configuration.image = [UIImage systemImageNamed:@"snowflake"];
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
  [self.refreshControl addTarget:self action:@selector(reloadThemes) forControlEvents:UIControlEventValueChanged];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadThemes) name:UIApplicationWillEnterForegroundNotification object:nil];
  [self reloadThemes];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:NO animated:animated];
  [self updateApplyButton];
}

#pragma mark - Data

- (void)reloadThemes {
  [AVThemeLibrary invalidate];
  NSArray *installed = [AVThemeLibrary installedThemes];
  NSMutableArray *active = [NSMutableArray new];
  for (NSString *theme in [AVConfigStore sharedStore].enabledThemes)
    if ([theme isKindOfClass:[NSString class]] && [installed containsObject:theme] && ![active containsObject:theme]) [active addObject:theme];
  _active = active;
  _installed = [installed mutableCopy];
  [_installed removeObjectsInArray:active];
  [_previews removeAllObjects];
  [_iconCounts removeAllObjects];
  [_loading removeAllObjects];
  // themes that were uninstalled drop out of the configuration
  if (![active isEqualToArray:[AVConfigStore sharedStore].enabledThemes]) [self saveActiveThemes];

  [self.refreshControl endRefreshing];
  [self.tableView reloadData];
  [self updateEmptyState];
  [self updateApplyButton];
}

- (NSString *)themeAtIndexPath:(NSIndexPath *)indexPath {
  NSArray *themes = (indexPath.section == AVThemeSectionActive) ? _active : _installed;
  return (indexPath.row < (NSInteger)themes.count) ? themes[indexPath.row] : nil;
}

- (BOOL)saveActiveThemes {
  [AVConfigStore sharedStore].enabledThemes = _active;
  NSError *error;
  if ([[AVConfigStore sharedStore] save:&error]) {
    [self updateApplyButton];
    return YES;
  }
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:AVLocalized(@"Couldn't save") message:[NSString stringWithFormat:AVLocalized(@"%@\n\nAvalanche has to be installed as a package (not as an IPA) so it can write its settings."), error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:AVLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
  return NO;
}

- (void)loadDetailsForTheme:(NSString *)theme {
  if ([_loading containsObject:theme]) return;
  [_loading addObject:theme];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSDictionary *icons = [AVThemeLibrary iconsInTheme:theme];
    NSMutableArray *paths = [NSMutableArray new];
    for (NSString *bundleID in AVPreviewApps()) {
      NSString *path = icons[bundleID][AVIconLight];
      if (path && paths.count < 4) [paths addObject:path];
    }
    for (NSString *bundleID in [icons.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
      if (paths.count >= 4) break;
      NSString *path = icons[bundleID][AVIconLight];
      if (path && ![paths containsObject:path]) [paths addObject:path];
    }
    UIImage *preview = AVRenderPreview(paths);
    NSUInteger count = icons.count + [AVThemeLibrary iconsByAppNameInTheme:theme].count;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (preview) self->_previews[theme] = preview;
      self->_iconCounts[theme] = @(count);
      NSMutableArray *indexPaths = [NSMutableArray new];
      for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows)
        if ([[self themeAtIndexPath:indexPath] isEqualToString:theme]) [indexPaths addObject:indexPath];
      if (indexPaths.count) [self.tableView reconfigureRowsAtIndexPaths:indexPaths];
    });
  });
}

#pragma mark - UI state

- (void)updateEmptyState {
  if (_active.count + _installed.count) {
    self.tableView.backgroundView = nil;
    return;
  }
  UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"snowflake" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightLight]]];
  image.tintColor = [UIColor tertiaryLabelColor];
  UILabel *title = [UILabel new];
  title.text = AVLocalized(@"No themes installed");
  title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
  UILabel *detail = [UILabel new];
  detail.text = [NSString stringWithFormat:AVLocalized(@"Install themes from your package manager. They are stored in %@."), AVThemesDirectoryDisplayName];
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
  configuration.subtitle = [AVConfigStore sharedStore].hasUnappliedChanges ? AVLocalized(@"Changes not applied yet") : nil;
  _applyButton.configuration = configuration;
  [_applyButton sizeToFit];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
  [super setEditing:editing animated:animated];
  [self.tableView setEditing:editing animated:animated];
}

#pragma mark - Actions

- (void)showSettings {
  [self.navigationController pushViewController:[AVSettingsViewController new] animated:YES];
}

- (void)apply {
  if (![self saveActiveThemes]) return;
  [self presentViewController:[[AVApplyViewController alloc] initWithClearingIconCache:NO] animated:YES completion:^{
    [self updateApplyButton];
  }];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return (_active.count + _installed.count) ? 2 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return (section == AVThemeSectionActive) ? _active.count : _installed.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  return (section == AVThemeSectionActive) ? AVLocalized(@"Active") : AVLocalized(@"Installed");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  if (section == AVThemeSectionActive)
    return _active.count ? AVLocalized(@"When several themes have an icon for the same app, the one higher up wins. Tap Edit to change the order.") : AVLocalized(@"Tap a theme below to activate it.");
  return _installed.count ? nil : AVLocalized(@"All installed themes are active.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Theme"] ? : [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Theme"];
  NSString *theme = [self themeAtIndexPath:indexPath];
  NSNumber *count = _iconCounts[theme];
  if (!count || !_previews[theme]) [self loadDetailsForTheme:theme];

  UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
  content.text = [AVThemeLibrary displayNameForTheme:theme];
  content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  content.secondaryText = count ? [NSString localizedStringWithFormat:AVLocalized(@"%lu icons"), (unsigned long)count.unsignedIntegerValue] : @" ";
  content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  content.image = _previews[theme] ? : [UIImage systemImageNamed:@"square.grid.2x2"];
  content.imageProperties.maximumSize = CGSizeMake(44, 44);
  content.imageProperties.reservedLayoutSize = CGSizeMake(44, 44);
  content.imageProperties.tintColor = [UIColor tertiaryLabelColor];
  cell.contentConfiguration = content;
  cell.accessoryType = (indexPath.section == AVThemeSectionActive) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
  cell.showsReorderControl = YES;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSString *theme = [self themeAtIndexPath:indexPath];
  if (!theme) return;
  NSIndexPath *destination;
  if (indexPath.section == AVThemeSectionActive) {
    [_active removeObjectAtIndex:indexPath.row];
    NSUInteger position = [_installed indexOfObject:theme inSortedRange:NSMakeRange(0, _installed.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(NSString *a, NSString *b) {
      return [[AVThemeLibrary displayNameForTheme:a] localizedCaseInsensitiveCompare:[AVThemeLibrary displayNameForTheme:b]];
    }];
    [_installed insertObject:theme atIndex:position];
    destination = [NSIndexPath indexPathForRow:position inSection:AVThemeSectionInstalled];
  } else {
    [_installed removeObjectAtIndex:indexPath.row];
    [_active addObject:theme];
    destination = [NSIndexPath indexPathForRow:_active.count - 1 inSection:AVThemeSectionActive];
  }
  [tableView performBatchUpdates:^{
    [tableView moveRowAtIndexPath:indexPath toIndexPath:destination];
  } completion:^(BOOL finished) {
    [tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationNone];
  }];
  [self saveActiveThemes];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
  return indexPath.section == AVThemeSectionActive;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
  if (proposed.section == AVThemeSectionActive) return proposed;
  return [NSIndexPath indexPathForRow:(_active.count ? _active.count - 1 : 0) inSection:AVThemeSectionActive];
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
