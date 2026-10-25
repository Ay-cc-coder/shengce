#import "AWActivityViewController.h"
#import "AWComponents.h"
#import "AWShared.h"
#import "AWTheme.h"
#import "AWDaemonClient.h"

@interface AWActivityCell : UITableViewCell
@property(nonatomic, strong) AWActivityRowView *rowView;
@end

@implementation AWActivityCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = AWPaperColor();
        self.contentView.backgroundColor = AWPaperColor();
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _rowView = [AWActivityRowView new];
        _rowView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_rowView];
        [NSLayoutConstraint activateConstraints:@[
            [_rowView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
            [_rowView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
            [_rowView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_rowView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
    }
    return self;
}

@end

@interface AWActivityViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) NSDictionary *status;
@property(nonatomic, strong) NSArray<NSDictionary *> *pending;
@property(nonatomic, strong) NSArray<NSDictionary *> *history;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) AWDaemonClient *daemonClient;
@property(nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation AWActivityViewController

- (instancetype)initWithStatus:(NSDictionary *)status {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _status = [status copy] ?: @{};
    }
    return self;
}

- (void)dealloc {
    [_refreshTimer invalidate];
    [_daemonClient cancel];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"全部记录";
    self.view.backgroundColor = AWPaperColor();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = AWPaperColor();
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 68.0;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    [_tableView registerClass:AWActivityCell.class forCellReuseIdentifier:@"ActivityCell"];
    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = AWAmberColor();
    [refresh addTarget:self action:@selector(reloadFromDisk) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = refresh;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    _emptyLabel = [UILabel new];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.font = AWFont(UIFontTextStyleSubheadline, UIFontWeightRegular);
    _emptyLabel.textColor = AWMutedColor();
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.text = @"还没有记录。\n新文件出现在监控文件夹后，会在这里显示上传状态。";
    [self.view addSubview:_emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
    ]];

    self.daemonClient = [AWDaemonClient new];
    [self applyStatus:self.status];
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
    [self reloadFromDisk];
    [self.refreshTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.refreshTimer = [NSTimer timerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf reloadFromDisk];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)reloadFromDisk {
    __weak typeof(self) weakSelf = self;
    [self.daemonClient fetchSnapshot:^(AWDaemonSnapshot *snapshot, NSError *error) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (snapshot.status) [self applyStatus:snapshot.status];
        [self.tableView.refreshControl endRefreshing];
    }];
}

- (void)applyStatus:(NSDictionary *)status {
    self.status = [status isKindOfClass:NSDictionary.class] ? status : @{};
    NSArray *queue = [self.status[@"queue"] isKindOfClass:NSArray.class] ? self.status[@"queue"] : @[];
    NSArray *recent = [self.status[@"recent"] isKindOfClass:NSArray.class] ? self.status[@"recent"] : @[];
    NSMutableArray *pending = [NSMutableArray array];
    for (id item in queue) {
        if ([item isKindOfClass:NSDictionary.class]) [pending addObject:item];
    }
    NSMutableArray *history = [NSMutableArray array];
    for (id item in recent) {
        if ([item isKindOfClass:NSDictionary.class]) [history addObject:item];
    }
    self.pending = pending;
    self.history = history;
    self.emptyLabel.hidden = (pending.count + history.count) > 0;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger count = 0;
    if (self.pending.count) count++;
    if (self.history.count) count++;
    return count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.pending.count && section == 0) return self.pending.count;
    return self.history.count;
}

- (NSArray<NSDictionary *> *)itemsForSection:(NSInteger)section {
    if (self.pending.count && section == 0) return self.pending;
    return self.history;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 46.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [UIView new];
    header.backgroundColor = AWPaperColor();
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = AWFont(UIFontTextStyleFootnote, UIFontWeightSemibold);
    label.textColor = AWMutedColor();
    if (self.pending.count && section == 0) {
        label.text = [NSString stringWithFormat:@"待上传 · %lu", (unsigned long)self.pending.count];
    } else {
        label.text = [NSString stringWithFormat:@"已完成 · %lu", (unsigned long)self.history.count];
    }
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-7],
    ]];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AWActivityCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ActivityCell" forIndexPath:indexPath];
    NSArray<NSDictionary *> *items = [self itemsForSection:indexPath.section];
    [cell.rowView configureWithItem:items[indexPath.row]];
    return cell;
}

@end
