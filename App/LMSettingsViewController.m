#import "LMSettingsViewController.h"
#import "LMApplyViewController.h"
#import "LMConfigStore.h"

typedef NS_ENUM(NSInteger, LMSettingsSection) {
  LMSettingsSectionIconStyle,
  LMSettingsSectionIconCache,
  LMSettingsSectionAbout,
  LMSettingsSectionCount,
};

@implementation LMSettingsViewController

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = LMLocalized(@"Settings");
  self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.navigationController setToolbarHidden:YES animated:animated];
}

- (UISwitch *)switchWithValue:(BOOL)value action:(SEL)action {
  UISwitch *toggle = [UISwitch new];
  toggle.on = value;
  [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
  return toggle;
}

- (void)save {
  NSError *error;
  if ([[LMConfigStore sharedStore] save:&error]) return;
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Couldn't save") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)systemShapeChanged:(UISwitch *)toggle {
  [LMConfigStore sharedStore].useSystemIconShape = toggle.on;
  [self save];
}

- (void)keepAppearanceChanged:(UISwitch *)toggle {
  [LMConfigStore sharedStore].keepIconsInDarkAndTinted = toggle.on;
  [self save];
}

- (void)confirmClearIconCache {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:LMLocalized(@"Clear icon cache?") message:LMLocalized(@"All app icons are rendered again, then SpringBoard restarts. This can take a minute.") preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:LMLocalized(@"Clear & Respring") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
    [self save];
    [self presentViewController:[[LMApplyViewController alloc] initWithClearingIconCache:YES] animated:YES completion:nil];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return LMSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case LMSettingsSectionIconStyle: return 2;
    case LMSettingsSectionIconCache: return 1;
    case LMSettingsSectionAbout: return 2;
  }
  return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  switch (section) {
    case LMSettingsSectionIconStyle: return LMLocalized(@"Theme icons");
    case LMSettingsSectionIconCache: return LMLocalized(@"Icon cache");
    case LMSettingsSectionAbout: return LMLocalized(@"About");
  }
  return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  switch (section) {
    case LMSettingsSectionIconStyle: return LMLocalized(@"Theme icons keep their own shape unless \"iOS icon shape\" is on. Tap Apply afterwards.");
    case LMSettingsSectionIconCache: return LMLocalized(@"Renders every app icon again. Use it if icons still look wrong after installing or updating themes.");
  }
  return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
  LMConfigStore *config = [LMConfigStore sharedStore];
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  if (indexPath.section == LMSettingsSectionIconStyle && indexPath.row == 0) {
    content.text = LMLocalized(@"iOS icon shape");
    content.image = [UIImage systemImageNamed:@"app"];
    cell.accessoryView = [self switchWithValue:config.useSystemIconShape action:@selector(systemShapeChanged:)];
  } else if (indexPath.section == LMSettingsSectionIconStyle) {
    content.text = LMLocalized(@"Keep in dark & tinted mode");
    content.image = [UIImage systemImageNamed:@"circle.lefthalf.filled"];
    cell.accessoryView = [self switchWithValue:config.keepIconsInDarkAndTinted action:@selector(keepAppearanceChanged:)];
  } else if (indexPath.section == LMSettingsSectionIconCache) {
    content.text = LMLocalized(@"Clear icon cache & respring");
    content.textProperties.color = self.view.tintColor;
    content.image = [UIImage systemImageNamed:@"arrow.clockwise"];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (indexPath.row == 0) {
    content = [UIListContentConfiguration valueCellConfiguration];
    content.text = LMLocalized(@"Version");
    content.secondaryText = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
  } else {
    content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = LMLocalized(@"Themes folder");
    content.secondaryText = LMThemesDirectoryDisplayName;
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  }
  cell.contentConfiguration = content;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (indexPath.section == LMSettingsSectionIconCache) [self confirmClearIconCache];
}

@end
