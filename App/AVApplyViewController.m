#import "AVApplyViewController.h"
#import "AVConfigStore.h"
#import <notify.h>

@implementation AVApplyViewController {
  BOOL _clearIconCache;
  BOOL _springBoardAnswered;
  int _progressToken;
  UIImageView *_symbol;
  UILabel *_titleLabel;
  UILabel *_statusLabel;
  UIProgressView *_progressView;
  UIButton *_closeButton;
}

- (instancetype)initWithClearingIconCache:(BOOL)clearIconCache {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _clearIconCache = clearIconCache;
    _progressToken = NOTIFY_TOKEN_INVALID;
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    self.modalInPresentation = YES;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent]];
    sheet.preferredCornerRadius = 28;
  }
  return self;
}

- (void)dealloc {
  if (_progressToken != NOTIFY_TOKEN_INVALID) notify_cancel(_progressToken);
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor systemBackgroundColor];

  _symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:52 weight:UIImageSymbolWeightMedium]]];
  _symbol.tintColor = self.view.tintColor;

  _titleLabel = [UILabel new];
  _titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
  _titleLabel.text = _clearIconCache ? AVLocalized(@"Rebuilding icons") : AVLocalized(@"Applying theme");

  _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
  _progressView.translatesAutoresizingMaskIntoConstraints = NO;

  _statusLabel = [UILabel new];
  _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
  _statusLabel.textColor = [UIColor secondaryLabelColor];
  _statusLabel.textAlignment = NSTextAlignmentCenter;
  _statusLabel.numberOfLines = 0;
  _statusLabel.text = AVLocalized(@"Preparing…");

  UIButtonConfiguration *configuration = [UIButtonConfiguration grayButtonConfiguration];
  configuration.title = AVLocalized(@"Close");
  configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
  __weak typeof(self) weakSelf = self;
  _closeButton = [UIButton buttonWithConfiguration:configuration primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
    [weakSelf dismissViewControllerAnimated:YES completion:nil];
  }]];
  _closeButton.hidden = YES;

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_symbol, _titleLabel, _progressView, _statusLabel, _closeButton]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 16;
  [stack setCustomSpacing:24 afterView:_symbol];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
    [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
    [_progressView.widthAnchor constraintEqualToConstant:260],
  ]];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (_progressToken != NOTIFY_TOKEN_INVALID) return;

  CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
  spin.toValue = @(M_PI * 2);
  spin.duration = 3;
  spin.repeatCount = HUGE_VALF;
  [_symbol.layer addAnimation:spin forKey:@"spin"];

  // SpringBoard reports (done << 32) | total while it renders the theme icons, done == UINT32_MAX before respringing
  __weak typeof(self) weakSelf = self;
  notify_register_dispatch(AVNotifyProgress, &_progressToken, dispatch_get_main_queue(), ^(int token) {
    uint64_t state = 0;
    notify_get_state(token, &state);
    [weakSelf showProgress:(uint32_t)(state >> 32) of:(uint32_t)(state & 0xFFFFFFFF)];
  });
  notify_post(_clearIconCache ? AVNotifyClearCache : AVNotifyApply);
  [[AVConfigStore sharedStore] markApplied];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf showFailureIfSpringBoardIsSilent];
  });
}

- (void)showProgress:(uint32_t)done of:(uint32_t)total {
  _springBoardAnswered = YES;
  if (done == UINT32_MAX || !total) {
    _progressView.progress = 1;
    _statusLabel.text = AVLocalized(@"Respringing…");
    return;
  }
  [_progressView setProgress:(float)done / total animated:YES];
  _statusLabel.text = [NSString localizedStringWithFormat:AVLocalized(@"Rendering icons: %u of %u"), done, total];
}

- (void)showFailureIfSpringBoardIsSilent {
  if (_springBoardAnswered) return;
  [_symbol.layer removeAllAnimations];
  _symbol.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:52 weight:UIImageSymbolWeightMedium]];
  _symbol.tintColor = [UIColor systemOrangeColor];
  _progressView.hidden = YES;
  _statusLabel.text = AVLocalized(@"SpringBoard didn't answer. Make sure Avalanche is enabled in your tweak injector, respring once and try again.");
  _closeButton.hidden = NO;
  self.modalInPresentation = NO;
}

@end
