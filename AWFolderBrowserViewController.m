#import "AWFolderBrowserViewController.h"
#import "AWShared.h"
#import "AWTheme.h"
#import "AWComponents.h"
#import <objc/runtime.h>

static NSString *AWStandardMobilePath(NSString *path) {
    if (path.length == 0) return nil;
    NSString *standardized = [path stringByStandardizingPath];
    if ([standardized hasPrefix:@"/private/var/mobile"]) {
        standardized = [standardized substringFromIndex:@"/private".length];
    }
    if (![standardized isEqualToString:@"/var/mobile"] && ![standardized hasPrefix:@"/var/mobile/"]) return nil;
    return standardized;
}

@interface AWFolderBrowserViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UIView *headerView;
@property(nonatomic, strong) UILabel *pathLabel;
@property(nonatomic, strong) UILabel *countLabel;
@property(nonatomic, strong) UIButton *upButton;
@property(nonatomic, strong) UIButton *chooseButton;
@property(nonatomic, strong) UILabel *chooseHint;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, copy) NSString *currentPath;
@property(nonatomic, strong) NSArray<NSDictionary *> *folders;
@property(nonatomic, strong) NSArray<NSDictionary *> *files;
@property(nonatomic, assign) NSUInteger countGeneration;
@end

@implementation AWFolderBrowserViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _initialPath = @"/var/mobile";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择文件夹";
    self.view.backgroundColor = AWPaperColor();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"输入路径"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(promptForPath)];

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.backgroundColor = AWPaperColor();
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 60.0;
    table.dataSource = self;
    table.delegate = self;
    table.contentInset = UIEdgeInsetsMake(0, 0, 154, 0);
    table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:table];
    self.tableView = table;

    [NSLayoutConstraint activateConstraints:@[
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self buildHeader];
    [self buildFooter];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.text = @"这个文件夹是空的";
    _emptyLabel.font = AWFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
    _emptyLabel.textColor = AWMutedColor();
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
    ]];

    NSString *initial = AWStandardMobilePath(self.initialPath) ?: @"/var/mobile";
    [self loadPath:initial];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = AWPaperColor();
    appearance.shadowColor = AWRuleColor();
    appearance.titleTextAttributes = @{ NSForegroundColorAttributeName : AWInkColor(),
                                        NSFontAttributeName : AWFont(UIFontTextStyleHeadline, UIFontWeightSemibold) };
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.tintColor = AWAmberColor();
    self.navigationController.navigationBar.prefersLargeTitles = NO;
}

- (void)buildHeader {
    _headerView = [UIView new];
    _headerView.backgroundColor = AWPaperColor();
    _pathLabel = [UILabel new];
    _pathLabel.font = AWPathFont();
    _pathLabel.adjustsFontForContentSizeCategory = YES;
    _pathLabel.textColor = AWInkColor();
    _pathLabel.numberOfLines = 2;
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.text = @"/var/mobile";

    UILabel *caption = [UILabel new];
    caption.text = @"当前文件夹";
    caption.font = AWFont(UIFontTextStyleCaption1, UIFontWeightSemibold);
    caption.textColor = AWMutedColor();

    _upButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _upButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_upButton setImage:AWIcon(@"arrow.up.left", 14, UIFontWeightSemibold) forState:UIControlStateNormal];
    [_upButton setTitle:@" 上一级" forState:UIControlStateNormal];
    _upButton.titleLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightSemibold);
    _upButton.tintColor = AWAmberColor();
    [_upButton setTitleColor:AWAmberColor() forState:UIControlStateNormal];
    [_upButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    _upButton.accessibilityLabel = @"上一级文件夹";
    [_upButton addTarget:self action:@selector(goUp) forControlEvents:UIControlEventTouchUpInside];

    _countLabel = [UILabel new];
    _countLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    _countLabel.textColor = AWMutedColor();
    _countLabel.text = @"正在统计文件…";

    UIView *spacer = [UIView new];
    [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[ caption, spacer, _upButton ]];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.alignment = UIStackViewAlignmentCenter;

    UIScrollView *quickScroll = [UIScrollView new];
    quickScroll.translatesAutoresizingMaskIntoConstraints = NO;
    quickScroll.showsHorizontalScrollIndicator = NO;
    UIStackView *quickStack = [UIStackView new];
    quickStack.translatesAutoresizingMaskIntoConstraints = NO;
    quickStack.axis = UILayoutConstraintAxisHorizontal;
    quickStack.spacing = 8.0;
    [quickScroll addSubview:quickStack];
    [NSLayoutConstraint activateConstraints:@[
        [quickStack.leadingAnchor constraintEqualToAnchor:quickScroll.contentLayoutGuide.leadingAnchor],
        [quickStack.trailingAnchor constraintEqualToAnchor:quickScroll.contentLayoutGuide.trailingAnchor],
        [quickStack.topAnchor constraintEqualToAnchor:quickScroll.contentLayoutGuide.topAnchor],
        [quickStack.bottomAnchor constraintEqualToAnchor:quickScroll.contentLayoutGuide.bottomAnchor],
        [quickStack.heightAnchor constraintEqualToAnchor:quickScroll.frameLayoutGuide.heightAnchor],
    ]];
    [quickScroll.heightAnchor constraintEqualToConstant:38].active = YES;

    NSArray<NSArray<NSString *> *> *quickPaths = @[
        @[ @"通话录音", @"/var/mobile/Media/PhotoData/CallAssist" ],
        @[ @"语音备忘录", @"/var/mobile/Media/Recordings" ],
        @[ @"下载", @"/var/mobile/Downloads" ],
        @[ @"所有媒体", @"/var/mobile/Media" ],
    ];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSArray *entry in quickPaths) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:entry[1] isDirectory:&isDir] || !isDir) continue;
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        [chip setTitle:entry[0] forState:UIControlStateNormal];
        [chip setTitleColor:AWInkColor() forState:UIControlStateNormal];
        chip.titleLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightMedium);
        chip.backgroundColor = AWSurfaceColor();
        chip.layer.cornerRadius = 10.0;
        chip.layer.cornerCurve = kCACornerCurveContinuous;
        chip.layer.borderWidth = 1.0;
        chip.layer.borderColor = AWRuleColor().CGColor;
        chip.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
        [chip.heightAnchor constraintEqualToConstant:44].active = YES;
        chip.accessibilityLabel = [NSString stringWithFormat:@"快捷位置，%@", entry[0]];
        objc_setAssociatedObject(chip, "aw.path", entry[1], OBJC_ASSOCIATION_COPY_NONATOMIC);
        [chip addTarget:self action:@selector(quickPathTapped:) forControlEvents:UIControlEventTouchUpInside];
        [quickStack addArrangedSubview:chip];
    }

    UIView *rule = [UIView new];
    rule.backgroundColor = AWRuleColor();
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    [rule.heightAnchor constraintEqualToConstant:0.5].active = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ topRow, _pathLabel, _countLabel, quickScroll, rule ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.alignment = UIStackViewAlignmentFill;
    [_headerView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:_headerView.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:-12],
    ]];
    CGSize size = [_headerView systemLayoutSizeFittingSize:CGSizeMake(self.view.bounds.size.width, 0)
                            withHorizontalFittingPriority:UILayoutPriorityRequired
                                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    _headerView.frame = CGRectMake(0, 0, self.view.bounds.size.width, MAX(150, size.height));
    self.tableView.tableHeaderView = _headerView;
}

- (void)buildFooter {
    UIView *footer = [UIView new];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.backgroundColor = AWPaperColor();
    UIView *rule = [UIView new];
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    rule.backgroundColor = AWRuleColor();
    [footer addSubview:rule];

    _chooseHint = [UILabel new];
    _chooseHint.translatesAutoresizingMaskIntoConstraints = NO;
    _chooseHint.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    _chooseHint.adjustsFontForContentSizeCategory = YES;
    _chooseHint.textColor = AWMutedColor();
    _chooseHint.numberOfLines = 2;
    _chooseHint.text = @"正在统计这个文件夹里的文件…";

    _chooseButton = [AWDynamicButton buttonWithType:UIButtonTypeSystem];
    _chooseButton.translatesAutoresizingMaskIntoConstraints = NO;
    AWLayoutPillButton(_chooseButton, AWAmberColor(), AWAmberInkColor());
    [_chooseButton setTitle:@"监控这个文件夹" forState:UIControlStateNormal];
    [_chooseButton.heightAnchor constraintEqualToConstant:52].active = YES;
    [_chooseButton addTarget:self action:@selector(chooseCurrentFolder) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _chooseHint, _chooseButton ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10.0;
    [footer addSubview:stack];
    [self.view addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [rule.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor],
        [rule.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],
        [rule.topAnchor constraintEqualToAnchor:footer.topAnchor],
        [rule.heightAnchor constraintEqualToConstant:0.5],
        [stack.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:footer.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.tableView.tableHeaderView) {
        UIView *header = self.tableView.tableHeaderView;
        CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(self.tableView.bounds.size.width, 0)
                                 withHorizontalFittingPriority:UILayoutPriorityRequired
                                       verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        CGRect frame = header.frame;
        if (fabs(frame.size.height - size.height) > 0.5 || fabs(frame.size.width - self.tableView.bounds.size.width) > 0.5) {
            frame.size.width = self.tableView.bounds.size.width;
            frame.size.height = size.height;
            header.frame = frame;
            self.tableView.tableHeaderView = header;
        }
    }
}

- (void)loadPath:(NSString *)path {
    NSString *safePath = AWStandardMobilePath(path);
    if (!safePath) {
        [self showError:@"只能选择 /var/mobile 下的文件夹"];
        return;
    }
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:safePath isDirectory:&isDir] || !isDir) {
        [self showError:@"这个文件夹不存在或无法访问"];
        return;
    }
    NSError *error = nil;
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:safePath error:&error];
    if (!names) {
        [self showError:error.localizedDescription ?: @"无法读取这个文件夹"];
        return;
    }
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *child = [safePath stringByAppendingPathComponent:name];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:child error:nil];
        if (!attributes) continue;
        if ([attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) continue;
        BOOL childIsDir = [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
        if (childIsDir) {
            [folders addObject:@{ @"name" : name, @"path" : child }];
        } else if ([attributes[NSFileType] isEqualToString:NSFileTypeRegular]) {
            NSMutableDictionary *file = [@{
                @"name" : name,
                @"path" : child,
                @"size" : attributes[NSFileSize] ?: @0,
                @"extension" : name.pathExtension ?: @"",
            } mutableCopy];
            if (attributes[NSFileModificationDate]) {
                file[@"modified"] = @([attributes[NSFileModificationDate] timeIntervalSince1970]);
            }
            [files addObject:file];
        }
    }
    self.currentPath = safePath;
    self.folders = folders;
    self.files = files;
    self.pathLabel.text = safePath;
    self.upButton.enabled = ![safePath isEqualToString:@"/var/mobile"];
    self.upButton.alpha = self.upButton.enabled ? 1.0 : 0.38;
    self.emptyLabel.hidden = (folders.count + files.count) > 0;
    [self.tableView reloadData];
    [self refreshFileCount];
}

- (void)refreshFileCount {
    NSString *path = self.currentPath;
    NSUInteger generation = ++self.countGeneration;
    self.countLabel.text = @"正在统计文件…";
    self.chooseHint.text = @"正在统计这个文件夹里的文件…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSDirectoryEnumerator<NSString *> *enumerator = [fm enumeratorAtPath:path];
        NSUInteger count = 0;
        BOOL capped = NO;
        for (NSString *relative in enumerator) {
            if ([relative.lastPathComponent hasPrefix:@"."]) continue;
            BOOL isDir = NO;
            NSString *full = [path stringByAppendingPathComponent:relative];
            if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;
            count++;
            if (count >= 9999) {
                capped = YES;
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.countGeneration) return;
            NSString *countText = capped ? @"9999+ 个文件" : [NSString stringWithFormat:@"%lu 个文件", (unsigned long)count];
            self.countLabel.text = [NSString stringWithFormat:@"%@（包含子文件夹）", countText];
            if (count == 0) {
                self.chooseHint.text = @"这个文件夹目前是空的。测试连接通过后开始监控，新文件会自动上传。";
            } else {
                self.chooseHint.text = [NSString stringWithFormat:@"文件夹中已有 %@。测试连接通过后开始监控，会先上传它们，然后保持静默监听。", countText];
            }
        });
    });
}

- (void)goUp {
    if ([self.currentPath isEqualToString:@"/var/mobile"]) return;
    [self loadPath:self.currentPath.stringByDeletingLastPathComponent];
}

- (void)quickPathTapped:(UIButton *)sender {
    NSString *path = objc_getAssociatedObject(sender, "aw.path");
    if (path.length) [self loadPath:path];
}

- (void)promptForPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入文件夹路径"
                                                                   message:@"路径需要位于 /var/mobile 下"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"/var/mobile/Media/Recordings";
        textField.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.text = self.currentPath;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"前往" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf loadPath:alert.textFields.firstObject.text ?: @""];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseCurrentFolder {
    if (self.currentPath.length == 0) return;
    [self.delegate folderBrowser:self didChooseFolder:self.currentPath];
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开文件夹"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table

- (NSArray<NSDictionary *> *)itemsForSection:(NSInteger)section {
    if (self.folders.count && section == 0) return self.folders;
    return self.files;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger count = 0;
    if (self.folders.count) count++;
    if (self.files.count) count++;
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self itemsForSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 36.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [UIView new];
    header.backgroundColor = AWPaperColor();
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL folderSection = self.folders.count && section == 0;
    label.text = folderSection
        ? [NSString stringWithFormat:@"文件夹 · %lu", (unsigned long)self.folders.count]
        : [NSString stringWithFormat:@"文件 · %lu", (unsigned long)self.files.count];
    label.font = AWFont(UIFontTextStyleCaption1, UIFontWeightSemibold);
    label.textColor = AWMutedColor();
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-6],
    ]];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"EntryCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.backgroundColor = AWPaperColor();
        cell.textLabel.font = AWFont(UIFontTextStyleBody, UIFontWeightMedium);
        cell.textLabel.textColor = AWInkColor();
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
        cell.detailTextLabel.textColor = AWMutedColor();
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.tintColor = AWAmberColor();
        UIView *selected = [UIView new];
        selected.backgroundColor = [AWAmberColor() colorWithAlphaComponent:0.10];
        cell.selectedBackgroundView = selected;
        cell.separatorInset = UIEdgeInsetsMake(0, 52, 0, 20);
    }
    BOOL folderSection = self.folders.count && indexPath.section == 0;
    NSArray<NSDictionary *> *items = [self itemsForSection:indexPath.section];
    NSDictionary *item = items[indexPath.row];
    cell.textLabel.text = item[@"name"];
    if (folderSection) {
        cell.imageView.image = AWIcon(@"folder.fill", 21, UIFontWeightRegular);
        cell.imageView.tintColor = AWAmberColor();
        cell.detailTextLabel.text = @"文件夹";
        UIImageView *chevron = [[UIImageView alloc] initWithImage:AWIcon(@"chevron.right", 12, UIFontWeightSemibold)];
        chevron.tintColor = AWMutedColor();
        cell.accessoryView = chevron;
        cell.accessibilityLabel = [NSString stringWithFormat:@"文件夹，%@", item[@"name"]];
        cell.accessibilityHint = @"打开这个文件夹";
    } else {
        NSString *extension = [(NSString *)item[@"extension"] uppercaseString];
        NSArray<NSString *> *audio = @[ @"MP3", @"WAV", @"M4A", @"AAC", @"CAF", @"AMR", @"FLAC", @"OGG", @"OPUS", @"AIFF", @"AIF" ];
        BOOL isAudio = [audio containsObject:extension];
        cell.imageView.image = AWIcon(isAudio ? @"waveform" : @"doc.fill", 21, UIFontWeightRegular);
        cell.imageView.tintColor = isAudio ? AWAmberColor() : AWMutedColor();
        NSString *kind = extension.length ? [extension stringByAppendingString:@" 文件"] : @"文件";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@", kind, AWFormatBytes([item[@"size"] unsignedLongLongValue])];
        UIImageView *info = [[UIImageView alloc] initWithImage:AWIcon(@"info.circle", 14, UIFontWeightRegular)];
        info.tintColor = AWMutedColor();
        cell.accessoryView = info;
        cell.accessibilityLabel = [NSString stringWithFormat:@"文件，%@，%@", item[@"name"], cell.detailTextLabel.text ?: @""];
        cell.accessibilityHint = @"显示文件信息";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL folderSection = self.folders.count && indexPath.section == 0;
    NSArray<NSDictionary *> *items = [self itemsForSection:indexPath.section];
    NSDictionary *item = items[indexPath.row];
    if (folderSection) {
        [self loadPath:item[@"path"]];
        return;
    }
    NSString *extension = [(NSString *)item[@"extension"] uppercaseString];
    NSString *kind = extension.length ? [extension stringByAppendingString:@" 文件"] : @"未知格式";
    NSString *modified = [item[@"modified"] doubleValue] > 0 ? AWShortTimeString([item[@"modified"] doubleValue]) : @"—";
    NSString *message = [NSString stringWithFormat:
        @"格式：%@\n大小：%@\n修改时间：%@\n\n%@\n\n监控这个文件夹时会按原文件名上传，不需要单独选择文件。",
        kind, AWFormatBytes([item[@"size"] unsignedLongLongValue]), modified, item[@"path"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item[@"name"]
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
