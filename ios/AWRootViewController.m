#import "AWRootViewController.h"
#import "AWActivityViewController.h"
#import "AWComponents.h"
#import "AWConfig.h"
#import "AWDaemonClient.h"
#import "AWPasswordStore.h"
#import "AWFolderBrowserViewController.h"
#import "AWShared.h"
#import "AWTheme.h"
#import "AWWebDAVClient.h"

@interface AWRootViewController () <AWFolderBrowserDelegate, UITextFieldDelegate>
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) AWMonitorView *monitor;
@property(nonatomic, strong) AWFieldView *serverField;
@property(nonatomic, strong) AWFieldView *accountField;
@property(nonatomic, strong) AWFieldView *passwordField;
@property(nonatomic, strong) AWChecklistView *checklist;
@property(nonatomic, strong) AWDynamicButton *testButton;
@property(nonatomic, strong) AWDynamicButton *startButton;
@property(nonatomic, strong) UIControl *folderControl;
@property(nonatomic, strong) UIImageView *folderIcon;
@property(nonatomic, strong) UILabel *folderNameLabel;
@property(nonatomic, strong) UILabel *folderPathLabel;
@property(nonatomic, strong) UILabel *folderHintLabel;
@property(nonatomic, strong) UILabel *validationLabel;
@property(nonatomic, strong) UILabel *runNoteLabel;
@property(nonatomic, strong) UILabel *daemonLabel;
@property(nonatomic, strong) UILabel *footnoteLabel;
@property(nonatomic, strong) UIStackView *activityStack;
@property(nonatomic, strong) UILabel *activityEmptyLabel;
@property(nonatomic, strong) UIButton *allActivityButton;
@property(nonatomic, strong) UIView *legacyBanner;

@property(nonatomic, strong) AWConfig *config;
@property(nonatomic, copy) NSString *draftFolder;
@property(nonatomic, strong) NSDictionary *status;
@property(nonatomic, strong) AWWebDAVClient *tester;
@property(nonatomic, strong) AWDaemonClient *daemonClient;
@property(nonatomic, assign) BOOL daemonConfigLoaded;
@property(nonatomic, assign) BOOL didInitialAppearance;
@property(nonatomic, assign) BOOL statusRequestInFlight;
@property(nonatomic, assign) CGFloat keyboardOverlap;
@property(nonatomic, copy) NSString *folderFileCountText;
@property(nonatomic, copy) NSString *savedPassword;
@property(nonatomic, copy) NSString *testedServer;
@property(nonatomic, copy) NSString *testedUsername;
@property(nonatomic, copy) NSString *testedPassword;
@property(nonatomic, assign) BOOL testPassed;
@property(nonatomic, assign) BOOL testing;
@property(nonatomic, assign) BOOL active;
@property(nonatomic, assign) BOOL showChecklist;
@property(nonatomic, assign) BOOL daemonAlive;
@property(nonatomic, assign) BOOL suppressFieldChange;
@property(nonatomic, assign) NSUInteger countGeneration;
@property(nonatomic, strong) NSTimer *statusTimer;
@property(nonatomic, assign) int statusNotifyToken;
@property(nonatomic, assign) BOOL observingStatus;
@end

@implementation AWRootViewController

- (void)dealloc {
    [_statusTimer invalidate];
    [_tester cancel];
    [_daemonClient cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AWPaperColor();
    self.daemonClient = [AWDaemonClient new];
    self.title = @"录音监控";
    [self buildLayout];
    [self loadConfiguration];
    [self reloadStatus];
    [self registerNotifications];
    [self applyNavigationAppearance];
    [self updateFormState];
    [self updateFolderUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyNavigationAppearance];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:AWIcon(@"info.circle", 18, UIFontWeightRegular)
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(showAbout)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"关于录音监控";
    [self reloadStatus];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.didInitialAppearance) {
        self.didInitialAppearance = YES;
        [self.view endEditing:YES];
        UIEdgeInsets inset = self.scrollView.adjustedContentInset;
        [self.scrollView setContentOffset:CGPointMake(0, -inset.top) animated:NO];
    }
    [self startStatusTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)startStatusTimer {
    [self.statusTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.statusTimer = [NSTimer timerWithTimeInterval:2.5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf reloadStatus];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.statusTimer forMode:NSRunLoopCommonModes];
}

#pragma mark - Layout

- (void)buildLayout {
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.alignment = UIStackViewAlignmentFill;
    self.stack.spacing = 14.0;
    [self.scrollView addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:20],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-20],
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:8],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-32],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-40],
    ]];

    UILabel *intro = [UILabel new];
    intro.text = @"选一个文件夹，新文件会自动上传到你的 WebDAV。已有文件会先上传，之后只在有新文件时工作。";
    intro.font = AWFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
    intro.adjustsFontForContentSizeCategory = YES;
    intro.textColor = AWMutedColor();
    intro.numberOfLines = 0;
    [self.stack addArrangedSubview:intro];
    [self.stack setCustomSpacing:18 afterView:intro];

    self.legacyBanner = [self buildLegacyBanner];
    if (self.legacyBanner) {
        [self.stack addArrangedSubview:self.legacyBanner];
        [self.stack setCustomSpacing:18 afterView:self.legacyBanner];
    }

    self.monitor = [[AWMonitorView alloc] initWithFrame:CGRectZero];
    [self.monitor.heightAnchor constraintGreaterThanOrEqualToConstant:204].active = YES;
    [self.monitor.scanButton addTarget:self action:@selector(requestScan) forControlEvents:UIControlEventTouchUpInside];
    [self.monitor.stopButton addTarget:self action:@selector(stopMonitoring) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.monitor];
    [self.stack setCustomSpacing:26 afterView:self.monitor];

    [self.stack addArrangedSubview:[self sectionHeader:@"连接 WebDAV" actionTitle:nil action:nil]];
    [self.stack setCustomSpacing:10 afterView:self.stack.arrangedSubviews.lastObject];

    self.serverField = [[AWFieldView alloc] initWithTitle:@"服务器地址"
                                              placeholder:@"https://dav.example.com/recordings/"
                                                   secure:NO
                                             keyboardType:UIKeyboardTypeURL];
    self.serverField.textField.returnKeyType = UIReturnKeyNext;
    [self.serverField setHintText:@"填写反代后的 HTTPS 目录，末尾斜杠可省略。"];
    self.accountField = [[AWFieldView alloc] initWithTitle:@"账号"
                                               placeholder:@"WebDAV 账号"
                                                    secure:NO
                                              keyboardType:UIKeyboardTypeASCIICapable];
    self.accountField.textField.returnKeyType = UIReturnKeyNext;
    self.passwordField = [[AWFieldView alloc] initWithTitle:@"密码"
                                                placeholder:@"WebDAV 密码"
                                                     secure:YES
                                               keyboardType:UIKeyboardTypeDefault];
    self.passwordField.textField.returnKeyType = UIReturnKeyDone;
    [self.serverField.textField addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.accountField.textField addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.passwordField.textField addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];

    UIStackView *fields = [[UIStackView alloc] initWithArrangedSubviews:@[ self.serverField, self.accountField, self.passwordField ]];
    fields.axis = UILayoutConstraintAxisVertical;
    fields.spacing = 15.0;
    [self.stack addArrangedSubview:fields];
    [self.stack setCustomSpacing:16 afterView:fields];

    self.testButton = [AWDynamicButton buttonWithType:UIButtonTypeSystem];
    [self.testButton setTitle:@"测试连接" forState:UIControlStateNormal];
    self.testButton.titleLabel.font = AWFont(UIFontTextStyleHeadline, UIFontWeightSemibold);
    [self.testButton setTitleColor:AWInkColor() forState:UIControlStateNormal];
    self.testButton.backgroundColor = [AWAmberColor() colorWithAlphaComponent:0.07];
    self.testButton.layer.cornerRadius = 14.0;
    self.testButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.testButton.layer.borderWidth = 1.0;
    self.testButton.layer.borderColor = [AWAmberColor() colorWithAlphaComponent:0.62].CGColor;
    [self.testButton.heightAnchor constraintEqualToConstant:50].active = YES;
    [self.testButton addTarget:self action:@selector(testConnection) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.testButton];
    [self.stack setCustomSpacing:12 afterView:self.testButton];

    self.checklist = [[AWChecklistView alloc] initWithFrame:CGRectZero];
    self.checklist.hidden = YES;
    [self.stack addArrangedSubview:self.checklist];
    [self.stack setCustomSpacing:12 afterView:self.checklist];

    self.footnoteLabel = [UILabel new];
    self.footnoteLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    self.footnoteLabel.adjustsFontForContentSizeCategory = YES;
    self.footnoteLabel.textColor = AWMutedColor();
    self.footnoteLabel.numberOfLines = 0;
    self.footnoteLabel.text = @"只接受 HTTPS。账号和密码只保存在本机，不会写入日志。";
    [self.stack addArrangedSubview:self.footnoteLabel];
    [self.stack setCustomSpacing:28 afterView:self.footnoteLabel];

    [self.stack addArrangedSubview:[self sectionHeader:@"监控文件夹" actionTitle:nil action:nil]];
    [self.stack setCustomSpacing:10 afterView:self.stack.arrangedSubviews.lastObject];

    self.folderControl = [self buildFolderControl];
    [self.stack addArrangedSubview:self.folderControl];
    [self.stack setCustomSpacing:8 afterView:self.folderControl];

    self.folderHintLabel = [UILabel new];
    self.folderHintLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    self.folderHintLabel.adjustsFontForContentSizeCategory = YES;
    self.folderHintLabel.textColor = AWMutedColor();
    self.folderHintLabel.numberOfLines = 0;
    [self.stack addArrangedSubview:self.folderHintLabel];
    [self.stack setCustomSpacing:18 afterView:self.folderHintLabel];

    self.startButton = [AWDynamicButton buttonWithType:UIButtonTypeSystem];
    AWLayoutPillButton(self.startButton, AWAmberColor(), AWAmberInkColor());
    [self.startButton setTitle:@"开始监控" forState:UIControlStateNormal];
    [self.startButton.heightAnchor constraintEqualToConstant:54].active = YES;
    [self.startButton addTarget:self action:@selector(startMonitoring) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:self.startButton];
    [self.stack setCustomSpacing:10 afterView:self.startButton];

    self.validationLabel = [UILabel new];
    self.validationLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightMedium);
    self.validationLabel.adjustsFontForContentSizeCategory = YES;
    self.validationLabel.textColor = AWRustColor();
    self.validationLabel.numberOfLines = 0;
    self.validationLabel.hidden = YES;
    [self.stack addArrangedSubview:self.validationLabel];

    self.runNoteLabel = [UILabel new];
    self.runNoteLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    self.runNoteLabel.adjustsFontForContentSizeCategory = YES;
    self.runNoteLabel.textColor = AWMutedColor();
    self.runNoteLabel.numberOfLines = 0;
    self.runNoteLabel.text = @"开始后由后台守护进程继续运行，关闭或从后台划掉 App 也不会中断。上传完成后保持静默，不轮询文件夹。";
    [self.stack addArrangedSubview:self.runNoteLabel];
    [self.stack setCustomSpacing:30 afterView:self.runNoteLabel];

    UIView *activityHeader = [self sectionHeader:@"最近动态" actionTitle:@"全部" action:@selector(showAllActivity)];
    [self.stack addArrangedSubview:activityHeader];
    [self.stack setCustomSpacing:6 afterView:activityHeader];

    self.activityStack = [UIStackView new];
    self.activityStack.axis = UILayoutConstraintAxisVertical;
    self.activityStack.spacing = 0.0;
    [self.stack addArrangedSubview:self.activityStack];

    self.activityEmptyLabel = [UILabel new];
    self.activityEmptyLabel.font = AWFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
    self.activityEmptyLabel.adjustsFontForContentSizeCategory = YES;
    self.activityEmptyLabel.textColor = AWMutedColor();
    self.activityEmptyLabel.numberOfLines = 0;
    self.activityEmptyLabel.text = @"还没有上传记录。\n新文件出现后，会在这里显示上传进度。";
    [self.activityStack addArrangedSubview:self.activityEmptyLabel];

    UIView *spacer = [UIView new];
    [spacer.heightAnchor constraintEqualToConstant:16].active = YES;
    [self.stack addArrangedSubview:spacer];

    self.daemonLabel = [UILabel new];
    self.daemonLabel.font = AWFont(UIFontTextStyleCaption2, UIFontWeightRegular);
    self.daemonLabel.adjustsFontForContentSizeCategory = YES;
    self.daemonLabel.textColor = AWMutedColor();
    self.daemonLabel.textAlignment = NSTextAlignmentCenter;
    self.daemonLabel.text = @"正在读取守护进程状态…";
    [self.stack addArrangedSubview:self.daemonLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:tap];
}

- (UIView *)sectionHeader:(NSString *)title actionTitle:(NSString *)actionTitle action:(SEL)action {
    UIView *container = [UIView new];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = AWFont(UIFontTextStyleHeadline, UIFontWeightSemibold);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = AWInkColor();
    [container addSubview:label];

    UIButton *button = nil;
    if (actionTitle.length) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setTitle:actionTitle forState:UIControlStateNormal];
        button.titleLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightSemibold);
        [button setTitleColor:AWAmberTextColor() forState:UIControlStateNormal];
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:button];
        if (action == @selector(showAllActivity)) self.allActivityButton = button;
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [button.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
            [button.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [label.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:(button ?: container).trailingAnchor constant:-8],
    ]];
    return container;
}

- (UIControl *)buildFolderControl {
    UIControl *control = [[UIControl alloc] initWithFrame:CGRectZero];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.backgroundColor = AWSurfaceColor();
    control.layer.cornerRadius = 14.0;
    control.layer.cornerCurve = kCACornerCurveContinuous;
    control.layer.borderWidth = 1.0;
    control.layer.borderColor = AWRuleColor().CGColor;
    control.isAccessibilityElement = YES;
    control.accessibilityTraits = UIAccessibilityTraitButton;
    control.accessibilityLabel = @"监控文件夹";
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:76].active = YES;
    [control addTarget:self action:@selector(chooseFolder) forControlEvents:UIControlEventTouchUpInside];

    UIView *iconBackground = [UIView new];
    iconBackground.translatesAutoresizingMaskIntoConstraints = NO;
    iconBackground.backgroundColor = [AWAmberColor() colorWithAlphaComponent:0.12];
    iconBackground.layer.cornerRadius = 10.0;
    iconBackground.userInteractionEnabled = NO;
    [control addSubview:iconBackground];
    self.folderIcon = [[UIImageView alloc] initWithImage:AWIcon(@"folder.fill", 20, UIFontWeightMedium)];
    self.folderIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderIcon.tintColor = AWAmberColor();
    [iconBackground addSubview:self.folderIcon];

    self.folderNameLabel = [UILabel new];
    self.folderNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderNameLabel.font = AWFont(UIFontTextStyleBody, UIFontWeightSemibold);
    self.folderNameLabel.adjustsFontForContentSizeCategory = YES;
    self.folderNameLabel.textColor = AWInkColor();
    self.folderNameLabel.numberOfLines = 1;
    self.folderPathLabel = [UILabel new];
    self.folderPathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderPathLabel.font = AWPathFont();
    self.folderPathLabel.adjustsFontForContentSizeCategory = YES;
    self.folderPathLabel.textColor = AWMutedColor();
    self.folderPathLabel.numberOfLines = 1;
    self.folderPathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [control addSubview:self.folderNameLabel];
    [control addSubview:self.folderPathLabel];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:AWIcon(@"chevron.right", 13, UIFontWeightSemibold)];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = AWMutedColor();
    chevron.contentMode = UIViewContentModeCenter;
    [chevron.widthAnchor constraintEqualToConstant:20].active = YES;
    [chevron.heightAnchor constraintEqualToConstant:20].active = YES;
    [control addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [iconBackground.leadingAnchor constraintEqualToAnchor:control.leadingAnchor constant:14],
        [iconBackground.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
        [iconBackground.widthAnchor constraintEqualToConstant:40],
        [iconBackground.heightAnchor constraintEqualToConstant:40],
        [self.folderIcon.centerXAnchor constraintEqualToAnchor:iconBackground.centerXAnchor],
        [self.folderIcon.centerYAnchor constraintEqualToAnchor:iconBackground.centerYAnchor],
        [self.folderNameLabel.leadingAnchor constraintEqualToAnchor:iconBackground.trailingAnchor constant:12],
        [self.folderNameLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-10],
        [self.folderNameLabel.topAnchor constraintEqualToAnchor:control.topAnchor constant:15],
        [self.folderPathLabel.leadingAnchor constraintEqualToAnchor:self.folderNameLabel.leadingAnchor],
        [self.folderPathLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-10],
        [self.folderPathLabel.topAnchor constraintEqualToAnchor:self.folderNameLabel.bottomAnchor constant:4],
        [self.folderPathLabel.bottomAnchor constraintEqualToAnchor:control.bottomAnchor constant:-15],
        [chevron.trailingAnchor constraintEqualToAnchor:control.trailingAnchor constant:-14],
        [chevron.centerYAnchor constraintEqualToAnchor:control.centerYAnchor],
    ]];
    return control;
}

- (UIView *)buildLegacyBanner {
    NSString *oldDaemon = @"/Library/LaunchDaemons/com.iseng.webdavmp3sync.daemon.plist";
    if (![NSFileManager.defaultManager fileExistsAtPath:oldDaemon]) return nil;
    UIView *banner = [UIView new];
    banner.backgroundColor = [AWRustColor() colorWithAlphaComponent:0.08];
    banner.layer.cornerRadius = 12.0;
    banner.layer.cornerCurve = kCACornerCurveContinuous;
    banner.layer.borderWidth = 1.0;
    banner.layer.borderColor = [AWRustColor() colorWithAlphaComponent:0.25].CGColor;
    UIImageView *icon = [[UIImageView alloc] initWithImage:AWIcon(@"exclamationmark.triangle.fill", 15, UIFontWeightSemibold)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = AWRustColor();
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = AWFont(UIFontTextStyleCaption1, UIFontWeightMedium);
    label.textColor = AWRustColor();
    label.numberOfLines = 0;
    label.text = @"检测到旧版 WebDAVMP3Sync 守护进程。建议先卸载旧插件，避免两个守护进程同时处理录音。";
    [banner addSubview:icon];
    [banner addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:12],
        [icon.topAnchor constraintEqualToAnchor:banner.topAnchor constant:13],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:9],
        [label.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-12],
        [label.topAnchor constraintEqualToAnchor:banner.topAnchor constant:11],
        [label.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-11],
    ]];
    return banner;
}

#pragma mark - Configuration

- (void)loadConfiguration {
    // Remove the test values from the development session exactly once, then
    // keep the user's own draft server/account/folder across relaunches.
    [AWConfig clearTestLeftovers];
    self.config = [AWConfig loadLocal];
    self.draftFolder = self.config.watchPath ?: @"";
    self.suppressFieldChange = YES;
    self.serverField.textField.text = self.config.server ?: @"";
    self.accountField.textField.text = self.config.username ?: @"";
    self.passwordField.textField.text = @"";
    self.savedPassword = [AWPasswordStore loadPassword] ?: @"";
    self.config.password = self.savedPassword;
    if (self.savedPassword.length) {
        self.passwordField.textField.text = self.savedPassword;
        [self.passwordField setHintText:@"已保存到本机，下次打开会自动使用。"];
    } else {
        [self.passwordField setHintText:@"密码只保存在本机，不会写入日志。"];
    }
    self.suppressFieldChange = NO;
    self.testPassed = NO;
    self.active = NO;
    self.daemonConfigLoaded = NO;
    [self updateFormState];
    [self updateFolderUI];
}

- (void)saveDraftConfiguration {
    AWConfig *draft = [AWConfig new];
    draft.server = self.serverField.textField.text ?: @"";
    draft.username = self.accountField.textField.text ?: @"";
    draft.watchPath = self.draftFolder ?: @"";
    [draft saveLocal];
}

- (void)applyDaemonConfig:(NSDictionary *)dictionary force:(BOOL)force {
    if (![dictionary isKindOfClass:NSDictionary.class]) return;
    if (self.daemonConfigLoaded && !force) return;
    AWConfig *remote = [AWConfig configFromDaemonDictionary:dictionary];
    BOOL hasRemoteConfig = remote.server.length > 0 || remote.watchPath.length > 0 || remote.hasPassword;
    if (hasRemoteConfig) {
        self.config = remote;
        self.config.password = @"";
        self.draftFolder = remote.watchPath ?: self.draftFolder;
        self.suppressFieldChange = YES;
        self.serverField.textField.text = remote.server ?: @"";
        self.accountField.textField.text = remote.username ?: @"";
        self.passwordField.textField.text = self.savedPassword.length ? self.savedPassword : @"";
        self.suppressFieldChange = NO;
        if (remote.hasPassword) [self setPasswordPlaceholder:@"已保存，留空即继续使用"];
        self.testPassed = remote.verified;
        self.active = remote.enabled;
        if (remote.verified) {
            self.testedServer = remote.server;
            self.testedUsername = remote.username;
            self.testedPassword = nil;
            self.showChecklist = YES;
            [self showPreviouslyVerified];
        } else {
            self.showChecklist = NO;
            self.checklist.hidden = YES;
        }
    } else {
        // No daemon configuration: keep the draft the user is editing.
        self.testPassed = NO;
        self.active = NO;
        self.showChecklist = NO;
        self.checklist.hidden = YES;
    }
    self.daemonConfigLoaded = YES;
    [self updateFormState];
    [self updateFolderUI];
}

- (void)showPreviouslyVerified {
    [self.checklist reset];
    [self.checklist setStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"HTTPS 地址已检查"];
    [self.checklist setStage:AWTestStageAccount state:AWTestStepStatePassed detail:@"账号已检查"];
    [self.checklist setStage:AWTestStageWrite state:AWTestStepStatePassed detail:@"写入权限已检查"];
    NSString *time = AWShortTimeString(self.config.testedAt);
    [self.checklist setSummary:[NSString stringWithFormat:@"上次测试通过 · %@", time] success:YES];
    self.checklist.hidden = NO;
}

- (void)setPasswordPlaceholder:(NSString *)text {
    self.passwordField.textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:text
                                                                                         attributes:@{ NSForegroundColorAttributeName : AWMutedColor() }];
}

- (void)fieldChanged:(UITextField *)field {
    if (self.suppressFieldChange) return;
    if (field == self.serverField.textField) [self.serverField setErrorText:nil];
    if (field == self.accountField.textField) [self.accountField setErrorText:nil];
    if (field == self.passwordField.textField) {
        [self.passwordField setErrorText:nil];
        if (field.text.length) {
            self.savedPassword = field.text;
            self.config.password = field.text;
        }
    }
    if (self.testPassed) {
        self.testPassed = NO;
        self.config.verified = NO;
        self.config.testFingerprint = @"";
        self.config.testedAt = 0;
        self.config.password = @"";
        self.testedServer = nil;
        self.testedUsername = nil;
        self.testedPassword = nil;
        [self.checklist reset];
        self.showChecklist = NO;
        self.checklist.hidden = YES;
        self.validationLabel.text = @"设置已修改，请重新测试连接。";
        self.validationLabel.hidden = NO;
    }
    [self saveDraftConfiguration];
    [self updateFormState];
}

- (void)updateFormState {
    BOOL locked = self.active;
    [self.serverField setFieldEnabled:!locked];
    [self.accountField setFieldEnabled:!locked];
    [self.passwordField setFieldEnabled:!locked];
    self.testButton.hidden = locked;
    self.startButton.hidden = locked;
    self.folderControl.userInteractionEnabled = !locked;
    self.folderControl.alpha = locked ? 0.64 : 1.0;
    self.checklist.hidden = !self.showChecklist;
    self.footnoteLabel.text = locked
        ? @"监控运行中，设置已锁定。停止监控后可以修改。"
        : @"只接受 HTTPS。账号和密码只保存在本机，不会写入日志。";
    if (!self.testing) {
        [self.testButton setTitle:(self.testPassed ? @"重新测试" : @"测试连接") forState:UIControlStateNormal];
    }
    self.testButton.enabled = !locked && !self.testing;
    BOOL hasFolder = self.draftFolder.length > 0;
    self.startButton.enabled = !locked && !self.testing && self.testPassed && hasFolder;
    self.startButton.alpha = self.startButton.enabled ? 1.0 : 0.42;
    if (!self.validationLabel.text.length || locked) {
        self.validationLabel.hidden = YES;
    }
    [self updateThemeBorders];
}

- (void)updateThemeBorders {
    self.testButton.layer.borderColor = [AWAmberColor() colorWithAlphaComponent:0.62].CGColor;
    self.folderControl.layer.borderColor = AWRuleColor().CGColor;
    if (self.legacyBanner) {
        self.legacyBanner.layer.borderColor = [AWRustColor() colorWithAlphaComponent:0.25].CGColor;
    }
    if (self.active) {
        self.testButton.backgroundColor = [AWAmberColor() colorWithAlphaComponent:0.07];
    }
}

#pragma mark - Folder

- (void)updateFolderUI {
    NSString *folder = self.draftFolder ?: @"";
    if (folder.length == 0) {
        self.folderNameLabel.text = @"选择监控文件夹";
        self.folderPathLabel.text = @"还没有选择";
        self.folderFileCountText = nil;
        self.folderHintLabel.text = self.testPassed
            ? @"连接已验证。选择一个文件夹后即可开始监控。"
            : @"建议选择通话录音或语音备忘录目录。选择后先测试服务器。";
        self.folderControl.accessibilityValue = @"未选择";
        self.startButton.enabled = NO;
        self.startButton.alpha = 0.42;
    } else {
        NSString *name = folder.lastPathComponent.length ? folder.lastPathComponent : folder;
        self.folderNameLabel.text = name;
        self.folderPathLabel.text = folder;
        self.folderControl.accessibilityValue = folder;
        [self refreshFolderCount];
    }
    [self updateFormState];
}

- (void)refreshFolderCount {
    NSString *folder = self.draftFolder;
    NSUInteger generation = ++self.countGeneration;
    if (folder.length == 0) return;
    self.folderFileCountText = nil;
    self.folderHintLabel.text = @"正在统计这个文件夹里的文件…";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSDirectoryEnumerator<NSString *> *enumerator = [fm enumeratorAtPath:folder];
        NSUInteger count = 0;
        BOOL capped = NO;
        for (NSString *relative in enumerator) {
            NSString *component = relative.lastPathComponent;
            BOOL isDir = NO;
            NSString *full = [folder stringByAppendingPathComponent:relative];
            [fm fileExistsAtPath:full isDirectory:&isDir];
            if ([component hasPrefix:@"."]) {
                if (isDir) [enumerator skipDescendants];
                continue;
            }
            if (isDir) continue;
            count++;
            if (count >= 9999) {
                capped = YES;
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != weakSelf.countGeneration) return;
            NSString *countText = capped ? @"9999+ 个文件" : [NSString stringWithFormat:@"%lu 个文件", (unsigned long)count];
            weakSelf.folderFileCountText = countText;
            [weakSelf updateFolderHint];
        });
    });
}

- (void)updateFolderHint {
    if (self.draftFolder.length == 0) {
        self.folderHintLabel.text = self.testPassed
            ? @"连接已验证。选择一个文件夹后即可开始监控。"
            : @"建议选择通话录音或语音备忘录目录。选择后先测试服务器。";
        return;
    }
    NSInteger pending = [self.status[@"pending"] integerValue];
    NSString *count = self.folderFileCountText;
    if (self.active) {
        if (pending > 0) {
            self.folderHintLabel.text = [NSString stringWithFormat:@"监控中，还有 %ld 个文件等待上传。", (long)pending];
        } else if (count.length) {
            self.folderHintLabel.text = [NSString stringWithFormat:@"监控中，文件夹内已有 %@（含子文件夹）。新文件出现时会静默上传。", count];
        } else {
            self.folderHintLabel.text = @"监控中。新文件出现时会静默上传。";
        }
    } else if (count.length) {
        if (self.testPassed) {
            self.folderHintLabel.text = [NSString stringWithFormat:@"连接已验证。点击下方“开始监控”，会先上传文件夹中已有的 %@。", count];
        } else {
            self.folderHintLabel.text = [NSString stringWithFormat:@"文件夹中已有 %@（含子文件夹）。请先测试连接，通过后开始监控会先上传它们。", count];
        }
    }
}

- (void)chooseFolder {
    if (self.active) {
        [AWToastView showMessage:@"先停止监控，再更换文件夹。" inView:self.view];
        return;
    }
    NSString *initial = self.draftFolder;
    BOOL isDirectory = NO;
    if (initial.length == 0 ||
        ![[NSFileManager defaultManager] fileExistsAtPath:initial isDirectory:&isDirectory] ||
        !isDirectory) {
        initial = @"/var/mobile/Media";
        if (![[NSFileManager defaultManager] fileExistsAtPath:initial isDirectory:&isDirectory] || !isDirectory) {
            initial = @"/var/mobile";
        }
        if (![initial isEqualToString:(self.draftFolder ?: @"")]) {
            self.draftFolder = @"";
        }
    }
    AWFolderBrowserViewController *browser = [AWFolderBrowserViewController new];
    browser.initialPath = initial;
    browser.delegate = self;
    [self.navigationController pushViewController:browser animated:YES];
}

- (void)folderBrowser:(UIViewController *)browser didChooseFolder:(NSString *)path {
    self.draftFolder = path;
    [self saveDraftConfiguration];
    [self updateFolderUI];
    [AWToastView showMessage:(self.testPassed
        ? @"文件夹已选择。点击下方开始监控。"
        : @"文件夹已选择。请先测试连接，通过后开始监控。") inView:self.view];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        UIView *target = self.testPassed ? self.startButton : self.testButton;
        if (!target || target.hidden) return;
        CGRect rect = [target convertRect:target.bounds toView:self.scrollView];
        [self.scrollView scrollRectToVisible:CGRectInset(rect, 0, -110) animated:YES];
    });
}

#pragma mark - Connection test

- (void)testConnection {
    if (self.testing || self.active) return;
    [self.view endEditing:YES];
    [self.serverField setErrorText:nil];
    [self.accountField setErrorText:nil];
    [self.passwordField setErrorText:nil];

    NSString *server = nil;
    NSString *username = nil;
    NSString *password = nil;
    NSString *error = [self connectionValuesWithServer:&server username:&username password:&password];
    if (error) {
        [self showValidation:error];
        if (!server) [self.serverField setErrorText:error];
        return;
    }

    self.testing = YES;
    self.testPassed = NO;
    self.validationLabel.hidden = YES;
    self.showChecklist = YES;
    self.checklist.hidden = NO;
    [self.checklist reset];
    [self.checklist setStage:AWTestStageAddress state:AWTestStepStateRunning detail:@"通过守护进程检查 HTTPS 地址"];
    [self.testButton setTitle:@"测试中…" forState:UIControlStateNormal];
    self.testButton.enabled = NO;
    self.startButton.enabled = NO;
    self.startButton.alpha = 0.42;
    [self updateFormState];

    NSMutableDictionary *body = [@{ @"server": server, @"username": username } mutableCopy];
    if (password.length) {
        body[@"password"] = password;
    } else {
        body[@"useStoredPassword"] = @YES;
    }
    __weak typeof(self) weakSelf = self;
    [self.daemonClient postCommand:@"/v1/test" body:body completion:^(NSDictionary *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        self.testing = NO;
        self.testButton.enabled = YES;
        if (error) {
            self.testPassed = NO;
            [self showValidation:error.localizedDescription ?: @"连接测试失败"];
            [self.checklist setStage:AWTestStageAddress state:AWTestStepStateFailed detail:error.localizedDescription ?: @"测试失败"];
            [self updateFormState];
            return;
        }
        BOOL success = [response[@"success"] boolValue];
        NSInteger failedStage = [response[@"failedStage"] integerValue];
        NSString *message = [response[@"message"] isKindOfClass:NSString.class] ? response[@"message"] : @"";
        NSString *warning = [response[@"warning"] isKindOfClass:NSString.class] ? response[@"warning"] : @"";
        if (success) {
            [self.checklist setStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"HTTPS 连接正常"];
            [self.checklist setStage:AWTestStageAccount state:AWTestStepStatePassed detail:@"账号验证通过"];
            [self.checklist setStage:AWTestStageWrite state:AWTestStepStatePassed detail:@"写入权限验证通过"];
            [self.checklist setSummary:@"连接可用，可以开始监控。" success:YES];
            NSString *normalizedError = nil;
            NSURL *normalized = AWBaseURLFromString(server, &normalizedError);
            self.suppressFieldChange = YES;
            self.serverField.textField.text = normalized.absoluteString;
            self.suppressFieldChange = NO;
            self.testedServer = normalized.absoluteString;
            self.testedUsername = username;
            self.testedPassword = password;
            self.testPassed = YES;
            if (password.length) {
                self.savedPassword = password;
                [AWPasswordStore savePassword:password];
                [self.passwordField setHintText:@"已保存到本机，下次打开会自动使用。"];
            }
            self.validationLabel.text = @"";
            self.validationLabel.hidden = YES;
            AWConfig *config = [AWConfig new];
            config.enabled = NO;
            config.server = normalized.absoluteString;
            config.username = username;
            config.watchPath = self.draftFolder;
            if (password.length) {
                [config markVerifiedWithPassword:password];
            } else {
                config.verified = YES;
                config.hasPassword = YES;
                config.testedAt = [response[@"testedAt"] doubleValue];
            }
            self.config = config;
            if (warning.length) [AWToastView showMessage:warning inView:self.view];
            UINotificationFeedbackGenerator *haptic = [UINotificationFeedbackGenerator new];
            [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"连接测试通过");
        } else {
            self.testPassed = NO;
            self.config.verified = NO;
            self.config.testFingerprint = @"";
            self.config.testedAt = 0;
            [self applyChecklistFailureStage:failedStage detail:message];
            [self.checklist setSummary:message success:NO];
            [self showValidation:message];
            if (failedStage == AWTestStageAccount) {
                [self.accountField setErrorText:message];
            } else {
                [self.serverField setErrorText:message];
            }
            UINotificationFeedbackGenerator *haptic = [UINotificationFeedbackGenerator new];
            [haptic notificationOccurred:UINotificationFeedbackTypeError];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message ?: @"连接测试失败");
        }
        [self updateFormState];
        [self updateFolderHint];
        if (self.draftFolder.length && !self.startButton.hidden && self.testPassed) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                CGRect rect = [self.startButton convertRect:self.startButton.bounds toView:self.scrollView];
                [self.scrollView scrollRectToVisible:CGRectInset(rect, 0, -110) animated:YES];
            });
        }
    }];
}

- (void)applyChecklistFailureStage:(NSInteger)stage detail:(NSString *)detail {
    if (stage == AWTestStageAddress) {
        [self.checklist setStage:AWTestStageAddress state:AWTestStepStateFailed detail:detail];
        [self.checklist setStage:AWTestStageAccount state:AWTestStepStatePending detail:@"需要先连通服务器"];
        [self.checklist setStage:AWTestStageWrite state:AWTestStepStatePending detail:@"需要先验证账号"];
    } else if (stage == AWTestStageAccount) {
        [self.checklist setStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"HTTPS 连接正常"];
        [self.checklist setStage:AWTestStageAccount state:AWTestStepStateFailed detail:detail];
        [self.checklist setStage:AWTestStageWrite state:AWTestStepStatePending detail:@"需要先验证账号"];
    } else {
        [self.checklist setStage:AWTestStageAddress state:AWTestStepStatePassed detail:@"HTTPS 连接正常"];
        [self.checklist setStage:AWTestStageAccount state:AWTestStepStatePassed detail:@"账号验证通过"];
        [self.checklist setStage:AWTestStageWrite state:AWTestStepStateFailed detail:detail];
    }
}

- (NSString *)connectionValuesWithServer:(NSString **)outServer
                               username:(NSString **)outUsername
                               password:(NSString **)outPassword {
    NSString *rawServer = [self.serverField.textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *username = [self.accountField.textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *password = self.passwordField.textField.text;
    if (password.length == 0) password = self.savedPassword ?: @"";
    if (rawServer.length == 0) return @"请填写服务器地址。";
    NSString *error = nil;
    NSURL *serverURL = AWBaseURLFromString(rawServer, &error);
    if (!serverURL) return error ?: @"服务器地址无效。";
    if (username.length == 0) return @"请填写账号。";
    BOOL canUseStored = self.config.hasPassword &&
                        [serverURL.absoluteString isEqualToString:(self.config.server ?: @"")] &&
                        [username isEqualToString:(self.config.username ?: @"")];
    if (password.length == 0 && !canUseStored) return @"请填写密码。";
    if (outServer) *outServer = serverURL.absoluteString;
    if (outUsername) *outUsername = username;
    if (outPassword) *outPassword = password;
    return nil;
}

- (void)showValidation:(NSString *)message {
    self.validationLabel.text = message;
    self.validationLabel.hidden = message.length == 0;
    self.validationLabel.textColor = AWRustColor();
}

#pragma mark - Monitoring

- (void)startMonitoring {
    if (self.active || self.testing) return;
    if (!self.testPassed) {
        [self showValidation:@"请先测试连接，确认地址、账号和写入权限。"];
        return;
    }
    if (self.draftFolder.length == 0) {
        [self showValidation:@"请选择需要监控的文件夹。"];
        return;
    }
    NSString *password = self.passwordField.textField.text;
    if (password.length == 0) password = self.savedPassword ?: @"";
    AWConfig *newConfig = [AWConfig new];
    newConfig.enabled = YES;
    newConfig.server = [self.serverField.textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    newConfig.username = [self.accountField.textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    newConfig.watchPath = self.draftFolder;
    newConfig.hasPassword = YES;
    newConfig.verified = YES;
    if (password.length) {
        if (![newConfig markVerifiedWithPassword:password]) {
            [self showValidation:@"连接信息无效，请重新测试。"];
            return;
        }
    } else {
        if (!self.config.verified || !self.config.hasPassword) {
            [self showValidation:@"请输入密码并测试连接。"];
            return;
        }
        NSURL *remoteServer = AWBaseURLFromString(self.config.server ?: @"", nil);
        NSURL *typedServer = AWBaseURLFromString(newConfig.server, nil);
        if (!remoteServer || !typedServer ||
            ![remoteServer.absoluteString isEqualToString:typedServer.absoluteString] ||
            ![newConfig.username isEqualToString:self.config.username]) {
            [self showValidation:@"服务器或账号已修改，请输入密码并重新测试。"];
            return;
        }
        newConfig.testedAt = self.config.testedAt;
        newConfig.testFingerprint = self.config.testFingerprint ?: @"";
    }

    NSDictionary *payload = [newConfig daemonPayloadWithPassword:password];
    self.startButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [self.daemonClient postCommand:@"/v1/config" body:payload completion:^(NSDictionary *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (error) {
            [self showValidation:error.localizedDescription ?: @"无法开始监控"];
            [self updateFormState];
            return;
        }
        NSDictionary *config = [response[@"config"] isKindOfClass:NSDictionary.class] ? response[@"config"] : nil;
        [self applyDaemonConfig:config force:YES];
        self.active = YES;
        self.testPassed = YES;
        self.config.enabled = YES;
        self.config.verified = YES;
        self.config.hasPassword = YES;
        self.config.password = @"";
        self.config.watchPath = self.draftFolder;
        self.testedPassword = nil;
        if (self.savedPassword.length) {
            self.passwordField.textField.text = self.savedPassword;
            [self.passwordField setHintText:@"已保存到本机，下次打开会自动使用。"];
        } else {
            self.passwordField.textField.text = @"";
            [self setPasswordPlaceholder:@"密码已保存"];
        }
        self.validationLabel.hidden = YES;
        self.showChecklist = YES;
        [self showPreviouslyVerified];
        [self updateFormState];
        [self updateFolderUI];
        [self updateMonitor];
        [AWToastView showMessage:@"监控已开始。已有文件会先上传。" inView:self.view];
        UINotificationFeedbackGenerator *haptic = [UINotificationFeedbackGenerator new];
        [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reloadStatus];
        });
    }];
}

- (void)stopMonitoring {
    if (!self.active) return;
    __weak typeof(self) weakSelf = self;
    [self.daemonClient postCommand:@"/v1/disable" body:@{} completion:^(NSDictionary *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (error) {
            [AWToastView showMessage:error.localizedDescription ?: @"无法停止监控" inView:self.view];
            return;
        }
        self.active = NO;
        self.config.enabled = NO;
        if (self.savedPassword.length) {
            self.passwordField.textField.text = self.savedPassword;
            [self.passwordField setHintText:@"已保存到本机，下次打开会自动使用。"];
        } else {
            self.passwordField.textField.text = @"";
            if (self.config.hasPassword) [self setPasswordPlaceholder:@"已保存，留空即继续使用"];
        }
        [self applyDaemonConfig:response[@"config"] force:YES];
        self.active = NO;
        self.config.enabled = NO;
        [self.config saveLocal];
        [self updateFormState];
        [self updateMonitor];
        [AWToastView showMessage:@"监控已停止。待上传队列会保留。" inView:self.view];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reloadStatus];
        });
    }];
}

- (void)requestScan {
    if (!self.active) return;
    __weak typeof(self) weakSelf = self;
    [self.daemonClient postCommand:@"/v1/scan" body:@{} completion:^(NSDictionary *response, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (error) {
            [AWToastView showMessage:error.localizedDescription ?: @"无法请求扫描" inView:self.view];
            return;
        }
        [AWToastView showMessage:@"已请求重新扫描文件夹。" inView:self.view];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reloadStatus];
        });
    }];
}

- (void)showAllActivity {
    AWActivityViewController *activity = [[AWActivityViewController alloc] initWithStatus:self.status];
    [self.navigationController pushViewController:activity animated:YES];
}

#pragma mark - Status

- (void)reloadStatus {
    if (self.statusRequestInFlight) return;
    self.statusRequestInFlight = YES;
    __weak typeof(self) weakSelf = self;
    [self.daemonClient fetchSnapshot:^(AWDaemonSnapshot *snapshot, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        self.statusRequestInFlight = NO;
        if (!snapshot) {
            self.daemonAlive = NO;
            [self updateMonitor];
            [self refreshActivity];
            self.daemonLabel.text = @"守护进程未连接。请重新安装插件或重启设备。";
            self.daemonLabel.textColor = AWRustColor();
            return;
        }
        self.daemonAlive = YES;
        self.status = snapshot.status ?: @{};
        if (!self.daemonConfigLoaded) {
            [self applyDaemonConfig:snapshot.config force:NO];
        } else if ([snapshot.config isKindOfClass:NSDictionary.class]) {
            BOOL remoteEnabled = [snapshot.config[@"enabled"] boolValue];
            self.config.enabled = remoteEnabled;
            self.config.hasPassword = [snapshot.config[@"hasPassword"] boolValue];
            self.config.verified = [snapshot.config[@"verified"] boolValue];
            self.config.updatedAt = [snapshot.config[@"updatedAt"] doubleValue];
            if (!self.testing && remoteEnabled != self.active) {
                self.active = remoteEnabled;
                [self updateFormState];
            }
            if (self.active) {
                NSString *remoteServer = [snapshot.config[@"server"] isKindOfClass:NSString.class] ? snapshot.config[@"server"] : @"";
                NSString *remoteUser = [snapshot.config[@"username"] isKindOfClass:NSString.class] ? snapshot.config[@"username"] : @"";
                NSString *remoteFolder = [snapshot.config[@"watchPath"] isKindOfClass:NSString.class] ? snapshot.config[@"watchPath"] : @"";
                if (remoteServer.length && ![remoteServer isEqualToString:(self.serverField.textField.text ?: @"")]) {
                    self.suppressFieldChange = YES;
                    self.serverField.textField.text = remoteServer;
                    self.accountField.textField.text = remoteUser;
                    self.suppressFieldChange = NO;
                }
                if (remoteFolder.length && ![remoteFolder isEqualToString:(self.draftFolder ?: @"")]) {
                    self.draftFolder = remoteFolder;
                    [self updateFolderUI];
                }
            }
        }
        [self updateMonitor];
        [self refreshActivity];
        NSNumber *pidNumber = self.status[@"pid"];
        NSInteger pid = pidNumber.integerValue;
        self.daemonLabel.text = pid > 0 ? [NSString stringWithFormat:@"守护进程运行中，PID %ld", (long)pid] : @"守护进程已连接。";
        self.daemonLabel.textColor = AWMutedColor();
    }];
}

- (void)updateMonitor {
    BOOL enabled = self.active;
    NSInteger pending = [self.status[@"pending"] integerValue];
    NSString *network = self.status[@"network"] ?: @"unknown";
    NSString *networkText = @"网络未知";
    if ([network isEqualToString:@"online"]) networkText = @"网络正常";
    else if ([network isEqualToString:@"offline"]) networkText = @"网络不可用";
    NSString *stateText = @"未开始监控";
    NSString *detail = nil;
    UIColor *color = AWFaintColor();
    BOOL bars = NO;

    if (!enabled) {
        stateText = @"未开始监控";
        if (self.testPassed && self.draftFolder.length) {
            detail = @"连接已验证，点击下方开始监控";
        } else if (self.testPassed) {
            detail = @"测试已通过，选择文件夹后开始";
        } else if (self.draftFolder.length) {
            detail = @"文件夹已选，测试连接后开始监控";
        } else {
            detail = @"测试连接并选择文件夹后开始";
        }
        color = AWFaintColor();
        networkText = @"网络待命";
    } else if (!self.config.verified) {
        stateText = @"需要检查";
        detail = @"配置校验失败，请停止后重新测试";
        color = AWRustColor();
        networkText = @"未验证";
    } else if (!self.daemonAlive && !self.status.count) {
        stateText = @"正在启动";
        detail = @"等待守护进程读取配置";
        color = AWAmberColor();
        networkText = @"等待连接";
    } else if (!self.daemonAlive) {
        stateText = @"守护进程未运行";
        detail = @"请重新安装插件或重启设备";
        color = AWRustColor();
        networkText = @"离线";
    } else {
        NSString *daemonState = [self.status[@"state"] isKindOfClass:NSString.class] ? self.status[@"state"] : @"watching";
        if ([daemonState isEqualToString:@"uploading"]) {
            stateText = @"正在上传";
            color = AWAmberColor();
            bars = YES;
            NSString *file = self.status[@"uploading"];
            detail = file.length ? [NSString stringWithFormat:@"正在上传 %@", file] : nil;
        } else if ([daemonState isEqualToString:@"waiting_network"]) {
            stateText = @"等待网络";
            color = AWRustColor();
            detail = @"网络恢复后会自动继续";
            networkText = @"等待网络";
        } else if ([daemonState isEqualToString:@"error"]) {
            stateText = @"需要检查";
            color = AWRustColor();
            detail = [self.status[@"lastError"] isKindOfClass:NSString.class] ? self.status[@"lastError"] : @"守护进程报告错误";
        } else if ([daemonState isEqualToString:@"queued"]) {
            stateText = @"准备上传";
            color = AWAmberColor();
            detail = pending > 0 ? [NSString stringWithFormat:@"%ld 个文件在队列中", (long)pending] : nil;
        } else if ([daemonState isEqualToString:@"disabled"]) {
            stateText = @"已停止";
            color = AWFaintColor();
            networkText = @"待命";
        } else {
            stateText = @"静默监控";
            color = AWSignalColor();
            detail = nil;
            networkText = [network isEqualToString:@"online"] ? @"网络正常" : networkText;
        }
    }

    NSString *path = self.config.watchPath.length ? AWDisplayPath(self.config.watchPath) : self.draftFolder.length ? AWDisplayPath(self.draftFolder) : @"还没有选择文件夹";
    NSString *lastUpload = @"还没有上传记录";
    if ([self.status[@"lastUploadAt"] doubleValue] > 0) {
        NSString *name = [self.status[@"lastUploadName"] isKindOfClass:NSString.class] ? self.status[@"lastUploadName"] : nil;
        lastUpload = [NSString stringWithFormat:@"最后上传 %@%@", AWShortTimeString([self.status[@"lastUploadAt"] doubleValue]), name.length ? [NSString stringWithFormat:@" · %@", name] : @""];
    }
    [self.monitor updateStateText:stateText
                           detail:detail
                          pending:pending
                        watchPath:path
                       lastUpload:lastUpload
                          network:networkText
                         barActive:bars
                           enabled:enabled
                             color:color];
    [self updateFolderHint];
}

- (void)refreshActivity {
    for (UIView *view in [self.activityStack.arrangedSubviews copy]) {
        [self.activityStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSArray *queue = [self.status[@"queue"] isKindOfClass:NSArray.class] ? self.status[@"queue"] : @[];
    for (id item in queue) {
        if ([item isKindOfClass:NSDictionary.class] && items.count < 3) [items addObject:item];
    }
    NSArray *recent = [self.status[@"recent"] isKindOfClass:NSArray.class] ? self.status[@"recent"] : @[];
    for (id item in recent) {
        if ([item isKindOfClass:NSDictionary.class] && items.count < 4) [items addObject:item];
    }
    if (items.count == 0) {
        [self.activityStack addArrangedSubview:self.activityEmptyLabel];
    } else {
        for (NSDictionary *item in items) {
            AWActivityRowView *row = [AWActivityRowView new];
            [row configureWithItem:item];
            [self.activityStack addArrangedSubview:row];
        }
    }
    self.allActivityButton.hidden = (queue.count + recent.count) == 0;
    self.allActivityButton.enabled = self.allActivityButton.hidden ? NO : YES;
}

#pragma mark - Keyboard & notifications

- (void)registerNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(fieldBeganEditing:)
                                                 name:UITextFieldTextDidBeginEditingNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(fieldEndedEditing:)
                                                 name:UITextFieldTextDidEndEditingNotification
                                               object:nil];
}

- (void)keyboardWillChange:(NSNotification *)note {
    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGFloat overlap = 0;
    if (![note.name isEqualToString:UIKeyboardWillHideNotification]) {
        CGRect screenRect = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGRect converted = [self.view convertRect:screenRect fromView:nil];
        overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
    }
    self.keyboardOverlap = overlap;
    [UIView animateWithDuration:duration animations:^{
        UIEdgeInsets inset = self.scrollView.contentInset;
        inset.bottom = overlap + 16;
        self.scrollView.contentInset = inset;
        UIEdgeInsets indicator = self.scrollView.verticalScrollIndicatorInsets;
        indicator.bottom = overlap;
        self.scrollView.verticalScrollIndicatorInsets = indicator;
    }];
}

- (void)fieldBeganEditing:(NSNotification *)note {
    UITextField *field = note.object;
    if (![field isDescendantOfView:self.scrollView]) return;
    if (self.keyboardOverlap <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGRect rect = [field convertRect:field.bounds toView:self.scrollView];
        [self.scrollView scrollRectToVisible:CGRectInset(rect, 0, -120) animated:YES];
    });
}

- (void)fieldEndedEditing:(NSNotification *)note {
    if (note.object != self.passwordField.textField) return;
    NSString *password = self.passwordField.textField.text;
    if (password.length == 0) return;
    self.savedPassword = password;
    self.config.password = password;
    [AWPasswordStore savePassword:password];
    [self.passwordField setHintText:@"已保存到本机，下次打开会自动使用。"];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Navigation

- (void)applyNavigationAppearance {
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    if (!navigationBar) return;
    UINavigationBarAppearance *standard = [UINavigationBarAppearance new];
    [standard configureWithOpaqueBackground];
    standard.backgroundColor = AWPaperColor();
    standard.shadowColor = AWRuleColor();
    standard.titleTextAttributes = @{ NSForegroundColorAttributeName : AWInkColor(),
                                      NSFontAttributeName : AWFont(UIFontTextStyleHeadline, UIFontWeightSemibold) };
    standard.largeTitleTextAttributes = @{ NSForegroundColorAttributeName : AWInkColor(),
                                           NSFontAttributeName : AWDisplayFont() };
    UINavigationBarAppearance *scrollEdge = [UINavigationBarAppearance new];
    [scrollEdge configureWithTransparentBackground];
    scrollEdge.backgroundColor = UIColor.clearColor;
    scrollEdge.shadowColor = UIColor.clearColor;
    scrollEdge.largeTitleTextAttributes = standard.largeTitleTextAttributes;
    scrollEdge.titleTextAttributes = standard.titleTextAttributes;
    navigationBar.standardAppearance = standard;
    navigationBar.scrollEdgeAppearance = scrollEdge;
    navigationBar.compactAppearance = standard;
    navigationBar.tintColor = AWAmberColor();
    navigationBar.prefersLargeTitles = YES;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyNavigationAppearance];
    [self updateThemeBorders];
}

- (void)showAbout {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    NSString *message = [NSString stringWithFormat:
        @"版本 %@\n\n"
         "工作方式\n"
         "先验证 HTTPS 地址、账号和写入权限，再开始监控。文件夹里已有的文件会先上传，之后只有新文件出现时才唤醒守护进程。\n\n"
         "网络中断\n"
         "上传失败的文件会保留在队列里，并标记为等待网络。网络恢复后自动继续，不需要重新选择文件。\n\n"
         "文件规则\n"
         "文件名保持不变；子文件夹结构会原样保留。服务器已有同名文件时会覆盖。本地文件不会被删除。\n\n"
         "日志\n"
         "/var/mobile/Library/Logs/AudioWatch.log", version];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"关于录音监控"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
