#import "AVSettingsViewController.h"
#import "AVApplyViewController.h"
#import "AVConfigStore.h"

typedef NS_ENUM(NSInteger, AVSettingsSection) {
  AVSettingsSectionIconStyle,
  AVSettingsSectionIconCache,
  AVSettingsSectionAbout,
  AVSettingsSectionCount,
};

@implementation AVSettingsViewController

- (instancetype)init {
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = AVLocalized(@"Settings");
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
  if ([[AVConfigStore sharedStore] save:&error]) return;
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:AVLocalized(@"Couldn't save") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:AVLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)systemShapeChanged:(UISwitch *)toggle {
  [AVConfigStore sharedStore].useSystemIconShape = toggle.on;
  [self save];
}

- (void)keepAppearanceChanged:(UISwitch *)toggle {
  [AVConfigStore sharedStore].keepIconsInDarkAndTinted = toggle.on;
  [self save];
}

- (void)confirmClearIconCache {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:AVLocalized(@"Clear icon cache?") message:AVLocalized(@"All app icons are rendered again, then SpringBoard restarts. This can take a minute.") preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:AVLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:AVLocalized(@"Clear & Respring") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
    [self save];
    [self presentViewController:[[AVApplyViewController alloc] initWithClearingIconCache:YES] animated:YES completion:nil];
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return AVSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case AVSettingsSectionIconStyle: return 2;
    case AVSettingsSectionIconCache: return 1;
    case AVSettingsSectionAbout: return 2;
  }
  return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
  switch (section) {
    case AVSettingsSectionIconStyle: return AVLocalized(@"Theme icons");
    case AVSettingsSectionIconCache: return AVLocalized(@"Icon cache");
    case AVSettingsSectionAbout: return AVLocalized(@"About");
  }
  return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
  switch (section) {
    case AVSettingsSectionIconStyle: return AVLocalized(@"Theme icons keep their own shape and transparency unless \"iOS icon shape\" is on. \"Keep in dark & tinted mode\" shows them unchanged instead of letting iOS darken or tint them; themes can also ship -dark and -tinted icons. Tap Apply afterwards.");
    case AVSettingsSectionIconCache: return AVLocalized(@"Renders every app icon again. Use it if icons still look wrong after installing or updating themes.");
  }
  return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
  AVConfigStore *config = [AVConfigStore sharedStore];
  cell.selectionStyle = UITableViewCellSelectionStyleNone;

  if (indexPath.section == AVSettingsSectionIconStyle && indexPath.row == 0) {
    content.text = AVLocalized(@"iOS icon shape");
    content.image = [UIImage systemImageNamed:@"app"];
    cell.accessoryView = [self switchWithValue:config.useSystemIconShape action:@selector(systemShapeChanged:)];
  } else if (indexPath.section == AVSettingsSectionIconStyle) {
    content.text = AVLocalized(@"Keep in dark & tinted mode");
    content.image = [UIImage systemImageNamed:@"circle.lefthalf.filled"];
    cell.accessoryView = [self switchWithValue:config.keepIconsInDarkAndTinted action:@selector(keepAppearanceChanged:)];
  } else if (indexPath.section == AVSettingsSectionIconCache) {
    content.text = AVLocalized(@"Clear icon cache & respring");
    content.textProperties.color = self.view.tintColor;
    content.image = [UIImage systemImageNamed:@"arrow.clockwise"];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  } else if (indexPath.row == 0) {
    content = [UIListContentConfiguration valueCellConfiguration];
    content.text = AVLocalized(@"Version");
    content.secondaryText = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
  } else {
    content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = AVLocalized(@"Themes folder");
    content.secondaryText = AVThemesDirectory;
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
  }
  cell.contentConfiguration = content;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (indexPath.section == AVSettingsSectionIconCache) [self confirmClearIconCache];
}

@end
