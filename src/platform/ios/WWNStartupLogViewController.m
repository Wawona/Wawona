/*
 * WWNStartupLogViewController.m
 *
 * Native iOS scrollable startup log overlay shown during the launch
 * transition from Machines UI → compositor.
 *
 * Design goals:
 *   • Native UITextView: selectable, copyable, scrollable.
 *   • Monospaced font to match terminal aesthetics.
 *   • Auto-scrolls to bottom on new entries.
 *   • Header shows machine/client label + spinner.
 *   • Tap outside the text view (or a Done button) dismisses early.
 *   • Programmatic fade-out from the first Wayland frame notification.
 *   • Dark, translucent glass material to let the compositor show through.
 */

#import "WWNStartupLogViewController.h"
#import "../../util/WWNStartupLogger.h"

static NSTimeInterval const kFadeDuration  = 0.4;
static NSTimeInterval const kAutoTimeout   = 60.0;   /* max time before auto-dismiss */
static CGFloat        const kCornerRadius  = 16.0;
static CGFloat        const kMaxOverlayH   = 0.72;   /* fraction of screen height */

@interface WWNStartupLogViewController () <WWNStartupLoggerDelegate>

@property (nonatomic, strong) UIVisualEffectView *blurContainer;
@property (nonatomic, strong) UILabel            *titleLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
#if TARGET_OS_VISION
/* UITextView / UIScrollView scroll-indicator paths abort on visionOS
 * Simulator (UIPointerInteraction / Gestures throw inside
 * CreateScrollIndicator). Keep a non-scrolling UILabel only. */
@property (nonatomic, strong) UILabel            *logLabel;
#else
@property (nonatomic, strong) UITextView         *textView;
#endif
@property (nonatomic, strong) UIButton           *doneButton;
@property (nonatomic, assign) BOOL                dismissing;
@property (nonatomic, strong) NSTimer            *timeoutTimer;

@end

@implementation WWNStartupLogViewController

#pragma mark - Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    [self buildUI];

    /* Subscribe to startup logger. */
    [WWNStartupLogger shared].delegate = self;

    /* Populate any lines already captured before we appeared. */
    NSArray<NSString *> *existing = [[WWNStartupLogger shared] capturedLines];
    if (existing.count > 0) {
        NSString *joined = [existing componentsJoinedByString:@"\n"];
        [self setLogText:joined];
        [self scrollToBottom];
    }

    /* Safety auto-dismiss. */
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoTimeout
                                                         target:self
                                                       selector:@selector(handleTimeout)
                                                       userInfo:nil
                                                        repeats:NO];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    if ([WWNStartupLogger shared].delegate == self) {
        [WWNStartupLogger shared].delegate = nil;
    }
    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
}

#pragma mark - UI Construction

- (void)buildUI
{
    UIView *root = self.view;

    /* Tap-to-dismiss on the dim background. */
    UITapGestureRecognizer *bgTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(handleBackgroundTap)];
    bgTap.cancelsTouchesInView = NO;
    [root addGestureRecognizer:bgTap];

    /* Blurred glass card. */
#if TARGET_OS_TV
    UIBlurEffect *blur =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraDark];
#else
    UIBlurEffect *blur =
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark];
#endif
    self.blurContainer = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.blurContainer.layer.cornerRadius  = kCornerRadius;
    self.blurContainer.layer.masksToBounds = YES;
    [root addSubview:self.blurContainer];

    UIView *card = self.blurContainer.contentView;

    /* Header row: spinner + title + done button. */
    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [UIColor systemGreenColor];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.spinner startAnimating];
    [card addSubview:self.spinner];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.text = self.clientLabel ?: @"Starting…";
    self.titleLabel.numberOfLines = 1;
    [card addSubview:self.titleLabel];

    self.doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.doneButton setTitle:@"Done" forState:UIControlStateNormal];
    self.doneButton.titleLabel.font = [UIFont systemFontOfSize:15.0
                                                        weight:UIFontWeightMedium];
    [self.doneButton addTarget:self
                        action:@selector(handleDone)
              forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.doneButton];

#if TARGET_OS_VISION
    self.logLabel = [[UILabel alloc] init];
    self.logLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.logLabel.numberOfLines = 0;
    self.logLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    self.logLabel.font = [UIFont monospacedSystemFontOfSize:12.5
                                                     weight:UIFontWeightRegular];
    self.logLabel.textColor = [UIColor systemGreenColor];
    self.logLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    self.logLabel.layer.cornerRadius = 8.0;
    self.logLabel.layer.masksToBounds = YES;
    self.logLabel.text = @"";
    [card addSubview:self.logLabel];
#else
    /* Log text view. Selectable, copyable, non-editable. */
    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
#if !TARGET_OS_TV
    self.textView.editable = NO;
#endif
    self.textView.selectable  = YES;
    self.textView.scrollEnabled = YES;
    self.textView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    self.textView.layer.cornerRadius = 8.0;
    self.textView.layer.masksToBounds = YES;
    self.textView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);

    self.textView.font = [UIFont monospacedSystemFontOfSize:12.5
                                                     weight:UIFontWeightRegular];
    self.textView.textColor = [UIColor systemGreenColor];
    self.textView.text = @"";
    [card addSubview:self.textView];
#endif

    /* Hint label at bottom. */
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.font = [UIFont systemFontOfSize:11.0];
    hintLabel.textColor = [UIColor secondaryLabelColor];
    hintLabel.text = @"Select text to copy · auto-dismisses on first frame";
    hintLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:hintLabel];

    /* Constraints. */
    CGFloat margin = 16.0;
    CGFloat inner  = 12.0;

    /* Card: centered, up to 94% wide, up to kMaxOverlayH tall, min 280 pt. */
    [NSLayoutConstraint activateConstraints:@[
        [self.blurContainer.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [self.blurContainer.centerYAnchor constraintEqualToAnchor:root.centerYAnchor
                                                          constant:-44.0],
        [self.blurContainer.widthAnchor constraintLessThanOrEqualToAnchor:root.widthAnchor
                                                               multiplier:0.94],
        [self.blurContainer.widthAnchor constraintGreaterThanOrEqualToConstant:300.0],
        [self.blurContainer.heightAnchor constraintLessThanOrEqualToAnchor:root.heightAnchor
                                                                multiplier:kMaxOverlayH],
        [self.blurContainer.heightAnchor constraintGreaterThanOrEqualToConstant:280.0],
    ]];

    /* Spinner */
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor
                                                   constant:margin],
        [self.spinner.topAnchor constraintEqualToAnchor:card.topAnchor constant:margin],
    ]];

    /* Title */
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.spinner.trailingAnchor
                                                      constant:8.0],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.spinner.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.doneButton.leadingAnchor
                                                                 constant:-8.0],
    ]];

    /* Done button */
    [NSLayoutConstraint activateConstraints:@[
        [self.doneButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor
                                                       constant:-margin],
        [self.doneButton.centerYAnchor constraintEqualToAnchor:self.spinner.centerYAnchor],
    ]];

    /* Separator line height helper. */
    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [UIColor separatorColor];
    [card addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [sep.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [sep.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:inner],
        [sep.heightAnchor constraintEqualToConstant:0.5],
    ]];

#if TARGET_OS_VISION
    UIView *logView = self.logLabel;
#else
    UIView *logView = self.textView;
#endif
    /* Text / log view */
    [NSLayoutConstraint activateConstraints:@[
        [logView.topAnchor constraintEqualToAnchor:sep.bottomAnchor
                                          constant:inner],
        [logView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor
                                              constant:margin],
        [logView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor
                                               constant:-margin],
    ]];

    /* Hint label */
    [NSLayoutConstraint activateConstraints:@[
        [hintLabel.topAnchor constraintEqualToAnchor:logView.bottomAnchor
                                            constant:inner],
        [hintLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor
                                                constant:margin],
        [hintLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor
                                                 constant:-margin],
        [hintLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor
                                               constant:-margin],
    ]];
}

#pragma mark - Public

- (void)setClientLabel:(NSString *)clientLabel
{
    _clientLabel = [clientLabel copy];
    if (self.isViewLoaded) {
        self.titleLabel.text = clientLabel ?: @"Starting…";
    }
}

- (void)dismissWithCompletion:(void (^)(void))completion
{
    if (self.dismissing) {
        if (completion) completion();
        return;
    }
    self.dismissing = YES;

    [self.timeoutTimer invalidate];
    self.timeoutTimer = nil;
    [WWNStartupLogger shared].delegate = nil;
    [[WWNStartupLogger shared] endCapture];

    [self.spinner stopAnimating];

    [UIView animateWithDuration:kFadeDuration animations:^{
        self.view.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
        if (completion) completion();
    }];
}

#pragma mark - Actions

- (void)handleDone
{
    [self dismissWithCompletion:nil];
}

- (void)handleBackgroundTap
{
    /* Only dismiss if the tap is outside the blur card. */
    /* (Allow taps inside the card to propagate normally.) */
}

- (void)handleTimeout
{
    [self dismissWithCompletion:nil];
}

#pragma mark - WWNStartupLoggerDelegate

- (void)startupLogger:(id)logger didAppendLine:(NSString *)line
{
    /* Called on main queue. */
    if (self.dismissing) return;

    NSString *current = [self logText];
    if (current.length > 0) {
        [self setLogText:[current stringByAppendingFormat:@"\n%@", line]];
    } else {
        [self setLogText:line];
    }
    [self scrollToBottom];
}

#pragma mark - Helpers

- (NSString *)logText
{
#if TARGET_OS_VISION
    return self.logLabel.text ?: @"";
#else
    return self.textView.text ?: @"";
#endif
}

- (void)setLogText:(NSString *)text
{
#if TARGET_OS_VISION
    self.logLabel.text = text ?: @"";
#else
    self.textView.text = text ?: @"";
#endif
}

- (void)scrollToBottom
{
#if TARGET_OS_VISION
    /* Non-scrolling label; truncation keeps the newest lines visible. */
    (void)self;
#else
    if (self.textView.text.length == 0) return;
    NSRange end = NSMakeRange(self.textView.text.length - 1, 1);
    [self.textView scrollRangeToVisible:end];
#endif
}

@end
