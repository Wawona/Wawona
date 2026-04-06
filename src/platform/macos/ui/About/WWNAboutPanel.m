#import "WWNAboutPanel.h"
#import "../Helpers/WWNImageLoader.h"
#ifndef WAWONA_VERSION
#define WAWONA_VERSION "0.0.0-unknown"
#endif

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// iOS: Full implementation
@interface WWNAboutPanel ()
@end

/// Load the About-header logo using the same cascading strategy as macOS:
/// try the dark logo by exact filename, then pathForResource, then direct
/// bundle path, then generic/light fallbacks.  No style switching — the
/// dark logo is used unconditionally, matching the macOS About panel.
static UIImage *WWNAboutLogo(void) {
  NSBundle *bundle = [NSBundle mainBundle];
  NSFileManager *fm = [NSFileManager defaultManager];
  UIImage *img = nil;

  // 1. imageNamed (works if the file is in an asset catalog)
  img = [UIImage imageNamed:@"Wawona-iOS-Dark-1024x1024@1x.png"];
  if (img) return img;

  // 2. pathForResource (base + extension separated)
  NSString *path =
      [bundle pathForResource:@"Wawona-iOS-Dark-1024x1024@1x" ofType:@"png"];
  if (path) {
    img = [UIImage imageWithContentsOfFile:path];
    if (img) return img;
  }

  // 3. Without the @1x scale suffix (ios.nix installs an unsuffixed copy)
  path = [bundle pathForResource:@"Wawona-iOS-Dark-1024x1024" ofType:@"png"];
  if (path) {
    img = [UIImage imageWithContentsOfFile:path];
    if (img) return img;
  }

  // 4. Direct bundle-path with the original @1x filename — bypasses iOS
  //    pathForResource:ofType: which treats @1x as a scale modifier and
  //    refuses to return it on 2x/3x devices.
  NSString *bundleRoot = [bundle bundlePath];
  NSString *direct =
      [bundleRoot stringByAppendingPathComponent:
                      @"Wawona-iOS-Dark-1024x1024@1x.png"];
  if ([fm fileExistsAtPath:direct]) {
    img = [UIImage imageWithContentsOfFile:direct];
    if (img) return img;
  }

  // 5. Direct bundle-path without scale suffix
  direct = [bundleRoot stringByAppendingPathComponent:
                           @"Wawona-iOS-Dark-1024x1024.png"];
  if ([fm fileExistsAtPath:direct]) {
    img = [UIImage imageWithContentsOfFile:direct];
    if (img) return img;
  }

  // 6. Generic "Wawona" name
  img = [UIImage imageNamed:@"Wawona"];
  if (img) return img;

  path = [bundle pathForResource:@"Wawona" ofType:@"png"];
  if (path) {
    img = [UIImage imageWithContentsOfFile:path];
    if (img) return img;
  }

  // 7. Light variant as last resort
  img = [UIImage imageNamed:@"Wawona-iOS-Light-1024x1024@1x.png"];
  if (img) return img;

  return nil;
}

@implementation WWNAboutPanel

+ (instancetype)sharedAboutPanel {
  static WWNAboutPanel *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    self.title = @"About Wawona";
    self.modalPresentationStyle = UIModalPresentationPageSheet;
  }
  return self;
}

- (void)loadView {
  self.view = [[UIView alloc] init];
  self.view.backgroundColor = [UIColor systemBackgroundColor];

  UIScrollView *scrollView = [[UIScrollView alloc] init];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:scrollView];

  UIStackView *contentStack = [[UIStackView alloc] init];
  contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  contentStack.axis = UILayoutConstraintAxisVertical;
  contentStack.spacing = 20;
  contentStack.alignment = UIStackViewAlignmentCenter;
  [scrollView addSubview:contentStack];

  // App Logo (same approach as macOS: always use the dark logo)
  UIImageView *logoView =
      [[UIImageView alloc] initWithImage:WWNAboutLogo()];
  logoView.contentMode = UIViewContentModeScaleAspectFit;
  [contentStack addArrangedSubview:logoView];

  [NSLayoutConstraint activateConstraints:@[
    [logoView.widthAnchor constraintEqualToConstant:100],
    [logoView.heightAnchor constraintEqualToConstant:100]
  ]];

  // App name & version
  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.text = @"Wawona";
  titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
  [contentStack addArrangedSubview:titleLabel];

  NSString *version = [NSString stringWithUTF8String:WAWONA_VERSION];
  if (![version hasPrefix:@"v"])
    version = [NSString stringWithFormat:@"v%@", version];
  UILabel *versionLabel = [[UILabel alloc] init];
  versionLabel.text = [NSString stringWithFormat:@"Version %@", version];
  versionLabel.font = [UIFont systemFontOfSize:16];
  versionLabel.textColor = [UIColor secondaryLabelColor];
  [contentStack addArrangedSubview:versionLabel];

  // Author Section
  UIImageView *avatarView =
      [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
  avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  avatarView.layer.cornerRadius = 40;
  avatarView.layer.masksToBounds = YES;
  avatarView.contentMode = UIViewContentModeScaleAspectFill;
  avatarView.backgroundColor = [UIColor secondarySystemBackgroundColor];
  [contentStack addArrangedSubview:avatarView];
  [NSLayoutConstraint activateConstraints:@[
    [avatarView.widthAnchor constraintEqualToConstant:80],
    [avatarView.heightAnchor constraintEqualToConstant:80]
  ]];
  [self loadImageURL:@"https://github.com/aspauldingcode.png?size=160"
            intoView:avatarView];

  UILabel *nameLabel = [[UILabel alloc] init];
  nameLabel.text = @"Alex Spaulding";
  nameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
  [contentStack addArrangedSubview:nameLabel];

  // Donation Buttons
  UIStackView *donateStack = [[UIStackView alloc] init];
  donateStack.axis = UILayoutConstraintAxisHorizontal;
  donateStack.spacing = 10;
  donateStack.distribution = UIStackViewDistributionFillEqually;
  [contentStack addArrangedSubview:donateStack];

  UIButton *kofiBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  if (@available(iOS 15.0, *)) {
    UIButtonConfiguration *config =
        [UIButtonConfiguration plainButtonConfiguration];
    config.title = @"Ko-fi";
    config.imagePlacement = NSDirectionalRectEdgeLeading;
    config.imagePadding = 8;
    kofiBtn.configuration = config;
  } else {
    [kofiBtn setTitle:@" Ko-fi" forState:UIControlStateNormal];
  }
  [kofiBtn addTarget:self
                action:@selector(openDonateLink:)
      forControlEvents:UIControlEventTouchUpInside];
  [donateStack addArrangedSubview:kofiBtn];

  UIButton *sponsorBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  if (@available(iOS 15.0, *)) {
    UIButtonConfiguration *config =
        [UIButtonConfiguration plainButtonConfiguration];
    config.title = @"GitHub Sponsors";
    config.imagePlacement = NSDirectionalRectEdgeLeading;
    config.imagePadding = 8;
    sponsorBtn.configuration = config;
  } else {
    [sponsorBtn setTitle:@" GitHub Sponsors" forState:UIControlStateNormal];
  }
  [sponsorBtn addTarget:self
                 action:@selector(openSponsorLink:)
       forControlEvents:UIControlEventTouchUpInside];
  [donateStack addArrangedSubview:sponsorBtn];

  // Social Links
  UIStackView *socialStack = [[UIStackView alloc] init];
  socialStack.axis = UILayoutConstraintAxisVertical;
  socialStack.spacing = 5;
  socialStack.alignment = UIStackViewAlignmentCenter;
  [contentStack addArrangedSubview:socialStack];

  [self addSocialButton:@"GitHub"
                   icon:@"https://github.githubassets.com/images/modules/"
                        @"logos_page/GitHub-Mark.png"
                 action:@selector(openGitHubLink:)
                toStack:socialStack];
  [self addSocialButton:@"LinkedIn"
                   icon:@"https://upload.wikimedia.org/wikipedia/commons/c/ca/"
                        @"LinkedIn_logo_initials.png"
                 action:@selector(openLinkedInLink:)
                toStack:socialStack];

  [NSLayoutConstraint activateConstraints:@[
    [scrollView.topAnchor
        constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [scrollView.trailingAnchor
        constraintEqualToAnchor:self.view.trailingAnchor],
    [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [contentStack.topAnchor constraintEqualToAnchor:scrollView.topAnchor
                                           constant:40],
    [contentStack.centerXAnchor
        constraintEqualToAnchor:scrollView.centerXAnchor],
    [contentStack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor
                                             constant:-40],
    [contentStack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor
                                              constant:-40]
  ]];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                           target:self
                           action:@selector(dismissAbout:)];
}

- (void)addSocialButton:(NSString *)title
                   icon:(NSString *)url
                 action:(SEL)action
                toStack:(UIStackView *)stack {
  UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
  [btn setTitle:[NSString stringWithFormat:@" %@", title]
       forState:UIControlStateNormal];
  [btn addTarget:self
                action:action
      forControlEvents:UIControlEventTouchUpInside];
  [stack addArrangedSubview:btn];
  [self loadImageURL:url intoView:btn];
}

- (void)loadImageURL:(NSString *)url intoView:(id)view {
  [[WWNImageLoader sharedLoader]
      loadImageFromURL:url
            completion:^(WImage _Nullable image) {
              if (!image)
                return;
              if ([view isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)view;
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(20, 20), NO,
                                                       0.0);
                [image drawInRect:CGRectMake(0, 0, 20, 20)];
                UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                UIImage *finalImage = [resized
                    imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
                if (@available(iOS 15.0, *)) {
                  if (btn.configuration) {
                    UIButtonConfiguration *config = btn.configuration;
                    config.image = finalImage;
                    btn.configuration = config;
                  } else {
                    [btn setImage:finalImage forState:UIControlStateNormal];
                  }
                } else {
                  [btn setImage:finalImage forState:UIControlStateNormal];
                }
              } else if ([view isKindOfClass:[UIImageView class]]) {
                ((UIImageView *)view).image = image;
              }
            }];
}

- (void)openDonateLink:(id)sender {
  [[UIApplication sharedApplication]
                openURL:[NSURL
                            URLWithString:@"https://ko-fi.com/aspauldingcode"]
                options:@{}
      completionHandler:nil];
}
- (void)openSponsorLink:(id)sender {
  [[UIApplication sharedApplication]
                openURL:[NSURL
                            URLWithString:
                                @"https://github.com/sponsors/aspauldingcode"]
                options:@{}
      completionHandler:nil];
}
- (void)openGitHubLink:(id)sender {
  [[UIApplication sharedApplication]
                openURL:[NSURL
                            URLWithString:@"https://github.com/aspauldingcode"]
                options:@{}
      completionHandler:nil];
}
- (void)openLinkedInLink:(id)sender {
  [[UIApplication sharedApplication]
                openURL:[NSURL
                            URLWithString:
                                @"https://www.linkedin.com/in/aspauldingcode/"]
                options:@{}
      completionHandler:nil];
}

- (void)dismissAbout:(id)sender {
  [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)showAboutPanel:(id)sender {
  (void)sender;
}
@end

#else // macOS implementation

@implementation WWNAboutPanel

+ (instancetype)sharedAboutPanel {
  static WWNAboutPanel *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 400, 480)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskFullSizeContentView
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [window setTitle:@"About Wawona"];
  [window center];
  [window setLevel:NSFloatingWindowLevel];
  [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];

  // Let AppKit handle window appearance with native Liquid Glass
  self = [super initWithWindow:window];
  if (self) {
    [[self.window standardWindowButton:NSWindowMiniaturizeButton]
        setHidden:YES];
    [[self.window standardWindowButton:NSWindowZoomButton] setHidden:YES];
    [self setupAboutView];
  }
  return self;
}

// Setup Tahoe glass background effect
// Removed: managed by configureWindowAppearance now

- (void)setupAboutView {
  NSView *contentView = self.window.contentView;

  NSStackView *stack = [[NSStackView alloc] init];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.spacing = 20;
  stack.edgeInsets = NSEdgeInsetsMake(40, 40, 40, 40);
  stack.alignment = NSLayoutAttributeCenterX;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [contentView addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:50],
    [stack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                        constant:40],
    [stack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                         constant:-40],
    [stack.bottomAnchor
        constraintLessThanOrEqualToAnchor:contentView.bottomAnchor
                                 constant:-30]
  ]];

  // App Logo
  NSImageView *logoView = [[NSImageView alloc] init];
  logoView.imageScaling = NSImageScaleProportionallyUpOrDown;
  logoView.translatesAutoresizingMaskIntoConstraints = NO;

  // Prefer the dark variant for About branding.
  NSImage *logo = [NSImage imageNamed:@"Wawona-iOS-Dark-1024x1024@1x.png"];
  if (!logo) {
    NSString *darkPath = [[NSBundle mainBundle]
        pathForResource:@"Wawona-iOS-Dark-1024x1024@1x"
                 ofType:@"png"];
    if (darkPath) {
      logo = [[NSImage alloc] initWithContentsOfFile:darkPath];
    }
  }
  if (!logo) {
    logo = [NSImage imageNamed:@"Wawona"];
  }
  if (!logo) {
    NSString *pngPath =
        [[NSBundle mainBundle] pathForResource:@"Wawona" ofType:@"png"];
    if (pngPath) {
      logo = [[NSImage alloc] initWithContentsOfFile:pngPath];
    }
  }
  if (!logo) {
    logo = [NSImage imageNamed:@"Wawona-iOS-Light-1024x1024@1x.png"];
  }
  if (logo) {
    logoView.image = logo;
  }

  [stack addArrangedSubview:logoView];
  [NSLayoutConstraint activateConstraints:@[
    [logoView.widthAnchor constraintEqualToConstant:128],
    [logoView.heightAnchor constraintEqualToConstant:128]
  ]];

  // App Name
  NSTextField *title = [[NSTextField alloc] init];
  title.stringValue = @"Wawona";
  title.font = [NSFont systemFontOfSize:42 weight:NSFontWeightBold];
  title.alignment = NSTextAlignmentCenter;
  title.bezeled = NO;
  title.drawsBackground = NO;
  title.editable = NO;
  title.selectable = NO;
  [stack addArrangedSubview:title];

  // Subtitle (Platform)
  NSTextField *subtitle = [[NSTextField alloc] init];
  subtitle.stringValue = @"Native macOS Wayland Compositor";
  subtitle.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
  subtitle.textColor = [NSColor secondaryLabelColor];
  subtitle.alignment = NSTextAlignmentCenter;
  subtitle.bezeled = NO;
  subtitle.drawsBackground = NO;
  subtitle.editable = NO;
  subtitle.selectable = NO;
  [stack addArrangedSubview:subtitle];

  // Version Section (Vertically Centered Stack)
  NSStackView *versionStack = [[NSStackView alloc] init];
  versionStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  versionStack.spacing = 8;
  versionStack.alignment = NSLayoutAttributeCenterY;
  [stack addArrangedSubview:versionStack];

  NSString *version = [NSString stringWithUTF8String:WAWONA_VERSION];
  if (![version hasPrefix:@"v"]) {
    version = [NSString stringWithFormat:@"v%@", version];
  }

  NSTextField *versionLabel = [[NSTextField alloc] init];
  versionLabel.stringValue = [NSString stringWithFormat:@"Version %@", version];
  versionLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
  versionLabel.textColor = [NSColor tertiaryLabelColor];
  versionLabel.alignment = NSTextAlignmentCenter;
  versionLabel.bezeled = NO;
  versionLabel.drawsBackground = NO;
  versionLabel.editable = NO;
  versionLabel.selectable = NO;
  [versionStack addArrangedSubview:versionLabel];

  [stack setCustomSpacing:30 afterView:versionStack];

  // Separator
  [stack addArrangedSubview:[self createSeparator]];

  // Credits Header
  NSTextField *creditsHeader = [[NSTextField alloc] init];
  creditsHeader.stringValue = @"Author";
  creditsHeader.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
  creditsHeader.textColor = [NSColor secondaryLabelColor];
  creditsHeader.alignment = NSTextAlignmentCenter;
  creditsHeader.bezeled = NO;
  creditsHeader.drawsBackground = NO;
  creditsHeader.editable = NO;
  creditsHeader.selectable = NO;
  [stack addArrangedSubview:creditsHeader];

  // Author Info Container (Vertically centered)
  NSStackView *authorStack = [[NSStackView alloc] init];
  authorStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  authorStack.spacing = 20;
  authorStack.alignment = NSLayoutAttributeCenterY;
  [stack addArrangedSubview:authorStack];

  // Avatar
  NSImageView *avatarView = [[NSImageView alloc] init];
  avatarView.imageScaling = NSImageScaleProportionallyUpOrDown;
  avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  avatarView.image = [NSImage imageNamed:NSImageNameUser];

  // Setup layer for a perfect circle
  avatarView.wantsLayer = YES;
  avatarView.layer.masksToBounds = YES;
  avatarView.layer.cornerRadius = 32.0;
  avatarView.layer.contentsGravity = kCAGravityResizeAspect;
  avatarView.layer.borderWidth = 0.0; // Ensure no default border interference

  [authorStack addArrangedSubview:avatarView];

  [NSLayoutConstraint activateConstraints:@[
    [avatarView.widthAnchor constraintEqualToConstant:64],
    [avatarView.heightAnchor constraintEqualToConstant:64]
  ]];
  [self loadGitHubAvatar:avatarView];

  // Author details
  NSStackView *detailsStack = [[NSStackView alloc] init];
  detailsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  detailsStack.spacing = 4;
  detailsStack.alignment = NSLayoutAttributeLeading;
  [authorStack addArrangedSubview:detailsStack];

  NSTextField *nameLabel = [[NSTextField alloc] init];
  nameLabel.stringValue = @"Alex Spaulding";
  nameLabel.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
  nameLabel.bezeled = NO;
  nameLabel.drawsBackground = NO;
  nameLabel.editable = NO;
  nameLabel.selectable = YES;
  [detailsStack addArrangedSubview:nameLabel];

  NSTextField *handleLabel = [[NSTextField alloc] init];
  handleLabel.stringValue = @"github@aspauldingcode";
  handleLabel.font = [NSFont systemFontOfSize:12];
  handleLabel.textColor = [NSColor linkColor];
  handleLabel.bezeled = NO;
  handleLabel.drawsBackground = NO;
  handleLabel.editable = NO;
  handleLabel.selectable = YES;
  [detailsStack addArrangedSubview:handleLabel];

  [stack setCustomSpacing:40 afterView:authorStack];

  // =========================================================================
  // DONATION EMPHASIS
  // =========================================================================
  [stack addArrangedSubview:[self createSeparator]];

  NSTextField *supportLabel = [[NSTextField alloc] init];
  supportLabel.stringValue = @"Love Wawona? ❤️ Support development!";
  supportLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
  supportLabel.textColor = [NSColor labelColor];
  supportLabel.alignment = NSTextAlignmentCenter;
  supportLabel.bezeled = NO;
  supportLabel.drawsBackground = NO;
  supportLabel.editable = NO;
  supportLabel.selectable = NO;
  [stack addArrangedSubview:supportLabel];

  NSStackView *donateStack = [[NSStackView alloc] init];
  donateStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  donateStack.spacing = 15;
  donateStack.distribution = NSStackViewDistributionFillEqually;
  [stack addArrangedSubview:donateStack];

  NSButton *kofiButton = [[NSButton alloc] init];
  kofiButton.title = @"Ko-fi";
  kofiButton.imagePosition = NSImageLeft;
  kofiButton.bezelStyle = NSBezelStyleRounded;
  kofiButton.target = self;
  kofiButton.action = @selector(openDonateLink:);
  kofiButton.controlSize = NSControlSizeLarge;
  [donateStack addArrangedSubview:kofiButton];

  NSButton *sponsorButton = [[NSButton alloc] init];
  sponsorButton.title = @"GitHub Sponsors";
  sponsorButton.imagePosition = NSImageLeft;
  sponsorButton.bezelStyle = NSBezelStyleRounded;
  sponsorButton.target = self;
  sponsorButton.action = @selector(openSponsorLink:);
  sponsorButton.controlSize = NSControlSizeLarge;
  [donateStack addArrangedSubview:sponsorButton];

  [NSLayoutConstraint activateConstraints:@[
    [donateStack.widthAnchor constraintEqualToConstant:320],
    [kofiButton.heightAnchor constraintEqualToConstant:40],
    [sponsorButton.heightAnchor constraintEqualToConstant:40]
  ]];

  [stack setCustomSpacing:30 afterView:donateStack];

  // Footer / Buttons
  NSStackView *footerStack = [[NSStackView alloc] init];
  footerStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  footerStack.spacing = 15;
  footerStack.distribution = NSStackViewDistributionFillEqually;
  [stack addArrangedSubview:footerStack];

  NSButton *repoButton =
      [self premiumButtonWithTitle:@"GitHub" action:@selector(openGitHubLink:)];
  [footerStack addArrangedSubview:repoButton];

  NSButton *xButton =
      [self premiumButtonWithTitle:@"X" action:@selector(openXLink:)];
  [footerStack addArrangedSubview:xButton];

  NSButton *linkedinButton =
      [self premiumButtonWithTitle:@"LinkedIn"
                            action:@selector(openLinkedInLink:)];
  [footerStack addArrangedSubview:linkedinButton];

  NSButton *webButton =
      [self premiumButtonWithTitle:@"Portfolio"
                            action:@selector(openPortfolioLink:)];
  [footerStack addArrangedSubview:webButton];

  // Configure icons
  [self loadImageURL:@"https://ko-fi.com/android-icon-192x192.png"
            intoView:kofiButton];
  [self loadImageURL:@"https://encrypted-tbn0.gstatic.com/images?q=tbn:"
                     @"ANd9GcRp_gdQoe-SxKGw3IvS-1G_JPsMY70HkqxAPg&s"
            intoView:sponsorButton];
  [self loadImageURL:@"https://github.githubassets.com/images/modules/logos_"
                     @"page/GitHub-Mark.png"
            intoView:repoButton];
  [self loadImageURL:@"https://x.com/favicon.ico" intoView:xButton];
  [self loadImageURL:@"https://upload.wikimedia.org/wikipedia/commons/c/ca/"
                     @"LinkedIn_logo_initials.png"
            intoView:linkedinButton];
  [self loadImageURL:@"https://aspauldingcode.com/favicon.ico"
            intoView:webButton];

  // Copyright
  NSTextField *copyright = [[NSTextField alloc] init];
  copyright.stringValue = @"© 2026 Alex Spaulding. All rights reserved.";
  copyright.font = [NSFont systemFontOfSize:11];
  copyright.textColor = [NSColor tertiaryLabelColor];
  copyright.alignment = NSTextAlignmentCenter;
  copyright.bezeled = NO;
  copyright.drawsBackground = NO;
  copyright.editable = NO;
  copyright.selectable = NO;
  [stack addArrangedSubview:copyright];
}

- (NSButton *)premiumButtonWithTitle:(NSString *)title action:(SEL)action {
  NSButton *btn = [[NSButton alloc] init];
  btn.title = title;
  btn.target = self;
  btn.action = action;
  btn.bezelStyle = NSBezelStyleRounded;
  btn.imagePosition = NSImageLeft; // Position image to the left of text
  return btn;
}

- (void)loadImageURL:(NSString *)url intoView:(id)view {
  [[WWNImageLoader sharedLoader]
      loadImageFromURL:url
            completion:^(WImage _Nullable image) {
              if (!image) {
                return;
              }
              if ([view isKindOfClass:[NSButton class]]) {
                NSButton *btn = (NSButton *)view;
                [image setSize:NSMakeSize(16, 16)];
                btn.image = image;
              } else if ([view isKindOfClass:[NSImageView class]]) {
                NSImageView *iv = (NSImageView *)view;
                iv.image = image;
              }
            }];
}

- (NSBox *)createSeparator {
  NSBox *separator = [[NSBox alloc] init];
  separator.boxType = NSBoxSeparator;
  separator.translatesAutoresizingMaskIntoConstraints = NO;
  [separator.widthAnchor constraintEqualToConstant:400].active = YES;
  [separator.heightAnchor constraintEqualToConstant:1].active = YES;
  return separator;
}

- (void)showAboutPanel:(id)sender {
  [self showWindow:sender];
  [self.window makeKeyAndOrderFront:sender];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)openDonateLink:(NSButton *)sender {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://ko-fi.com/aspauldingcode"]];
}

- (void)openGitHubLink:(NSButton *)sender {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL
                  URLWithString:@"https://github.com/aspauldingcode/Wawona"]];
}

- (void)openPortfolioLink:(NSButton *)sender {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://aspauldingcode.com"]];
}

- (void)openXLink:(NSButton *)sender {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://x.com/aspauldingcode"]];
}

- (void)openLinkedInLink:(NSButton *)sender {
  [[NSWorkspace sharedWorkspace]
      openURL:
          [NSURL URLWithString:@"https://www.linkedin.com/in/aspauldingcode/"]];
}

- (void)openSponsorLink:(NSButton *)sender {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL
                  URLWithString:@"https://github.com/sponsors/aspauldingcode"]];
}
- (void)loadGitHubAvatar:(NSImageView *)imageView {
  NSString *avatarURLString = @"https://github.com/aspauldingcode.png?size=128";
  [self loadImageURL:avatarURLString intoView:imageView];
}

@end
#endif
