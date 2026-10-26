#import "AWComponents.h"
#import "AWShared.h"

@interface AWInsetTextField : UITextField
@end

@implementation AWInsetTextField
- (CGRect)textRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, 14, 0, 14));
}
- (CGRect)editingRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, 14, 0, 14));
}
- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0, 14, 0, 14));
}
- (CGRect)rightViewRectForBounds:(CGRect)bounds {
    return CGRectMake(CGRectGetMaxX(bounds) - 48, 0, 48, CGRectGetHeight(bounds));
}
@end

@interface AWFieldView () <UITextFieldDelegate>
@property(nonatomic, strong) UILabel *captionLabel;
@property(nonatomic, strong) UITextField *textField;
@property(nonatomic, strong) UILabel *hintLabel;
@property(nonatomic, strong) UIView *fieldBox;
@property(nonatomic, strong) UIButton *revealButton;
@property(nonatomic, copy) NSString *errorText;
@property(nonatomic, copy) NSString *hintText;
@property(nonatomic, assign) BOOL fieldFocused;
@property(nonatomic, assign) BOOL secure;
@end

@implementation AWFieldView

- (instancetype)initWithTitle:(NSString *)title
                  placeholder:(NSString *)placeholder
                       secure:(BOOL)secure
                 keyboardType:(UIKeyboardType)keyboardType {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.secure = secure;

    _captionLabel = [UILabel new];
    _captionLabel.text = title;
    _captionLabel.font = AWFont(UIFontTextStyleFootnote, UIFontWeightSemibold);
    _captionLabel.adjustsFontForContentSizeCategory = YES;
    _captionLabel.textColor = AWMutedColor();

    _fieldBox = [UIView new];
    _fieldBox.translatesAutoresizingMaskIntoConstraints = NO;
    _fieldBox.backgroundColor = AWSurfaceColor();
    _fieldBox.layer.cornerRadius = 12.0;
    _fieldBox.layer.cornerCurve = kCACornerCurveContinuous;
    _fieldBox.layer.borderWidth = 1.0;

    _textField = [[AWInsetTextField alloc] initWithFrame:CGRectZero];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;
    _textField.delegate = self;
    _textField.font = AWFont(UIFontTextStyleBody, UIFontWeightRegular);
    _textField.adjustsFontForContentSizeCategory = YES;
    _textField.textColor = AWInkColor();
    _textField.tintColor = AWAmberColor();
    _textField.secureTextEntry = secure;
    _textField.keyboardType = keyboardType;
    _textField.autocorrectionType = UITextAutocorrectionTypeNo;
    _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textField.spellCheckingType = UITextSpellCheckingTypeNo;
    _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _textField.accessibilityLabel = title;
    _textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder ?: @""
                                                                       attributes:@{ NSForegroundColorAttributeName : AWMutedColor() }];
    if (keyboardType == UIKeyboardTypeURL) {
        _textField.textContentType = UITextContentTypeURL;
        _textField.returnKeyType = UIReturnKeyNext;
    } else if (keyboardType == UIKeyboardTypeASCIICapable) {
        _textField.textContentType = UITextContentTypeUsername;
        _textField.returnKeyType = UIReturnKeyNext;
    } else if (secure) {
        _textField.textContentType = UITextContentTypePassword;
        _textField.returnKeyType = UIReturnKeyDone;
    }
    [_fieldBox addSubview:_textField];

    if (secure) {
        _revealButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _revealButton.translatesAutoresizingMaskIntoConstraints = NO;
        _revealButton.tintColor = AWMutedColor();
        _revealButton.accessibilityLabel = @"显示密码";
        UIImage *eye = AWIcon(@"eye", 16, UIFontWeightMedium);
        [_revealButton setImage:eye forState:UIControlStateNormal];
        [_revealButton addTarget:self action:@selector(toggleReveal) forControlEvents:UIControlEventTouchUpInside];
        _textField.rightView = _revealButton;
        _textField.rightViewMode = UITextFieldViewModeAlways;
    }

    _hintLabel = [UILabel new];
    _hintLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    _hintLabel.adjustsFontForContentSizeCategory = YES;
    _hintLabel.textColor = AWMutedColor();
    _hintLabel.numberOfLines = 0;
    _hintLabel.hidden = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _captionLabel, _fieldBox, _hintLabel ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6.0;
    stack.alignment = UIStackViewAlignmentFill;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_fieldBox.heightAnchor constraintGreaterThanOrEqualToConstant:50.0],
        [_textField.leadingAnchor constraintEqualToAnchor:_fieldBox.leadingAnchor],
        [_textField.trailingAnchor constraintEqualToAnchor:_fieldBox.trailingAnchor],
        [_textField.topAnchor constraintEqualToAnchor:_fieldBox.topAnchor],
        [_textField.bottomAnchor constraintEqualToAnchor:_fieldBox.bottomAnchor],
    ]];
    [self updateThemeColors];
    return self;
}

- (void)updateThemeColors {
    _fieldBox.backgroundColor = AWSurfaceColor();
    _textField.textColor = AWInkColor();
    _textField.tintColor = AWAmberColor();
    _captionLabel.textColor = AWMutedColor();
    _revealButton.tintColor = AWMutedColor();
    if (self.errorText.length) {
        _fieldBox.layer.borderColor = AWRustColor().CGColor;
        _hintLabel.textColor = AWRustColor();
    } else if (self.fieldFocused) {
        _fieldBox.layer.borderColor = AWAmberColor().CGColor;
        _hintLabel.textColor = AWMutedColor();
    } else {
        _fieldBox.layer.borderColor = AWRuleColor().CGColor;
        _hintLabel.textColor = AWMutedColor();
    }
    _textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:_textField.attributedPlaceholder.string ?: @""
                                                                       attributes:@{ NSForegroundColorAttributeName : AWMutedColor() }];
}

- (void)setFieldEnabled:(BOOL)enabled {
    _textField.enabled = enabled;
    _revealButton.enabled = enabled;
    self.alpha = enabled ? 1.0 : 0.58;
    if (!enabled) {
        _fieldBox.backgroundColor = [AWSurfaceColor() colorWithAlphaComponent:0.55];
    } else {
        _fieldBox.backgroundColor = AWSurfaceColor();
    }
}

- (void)setErrorText:(NSString *)error {
    _errorText = [error copy];
    if (error.length) {
        _hintLabel.text = error;
        _hintLabel.hidden = NO;
    } else {
        _hintLabel.text = self.hintText;
        _hintLabel.hidden = self.hintText.length == 0;
    }
    [self updateThemeColors];
}

- (void)setHintText:(NSString *)hint {
    _hintText = [hint copy];
    if (_errorText.length == 0) {
        _hintLabel.text = hint;
        _hintLabel.hidden = hint.length == 0;
    }
}

- (void)toggleReveal {
    _textField.secureTextEntry = !_textField.secureTextEntry;
    _revealButton.accessibilityLabel = _textField.secureTextEntry ? @"显示密码" : @"隐藏密码";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.fieldFocused = YES;
    [self updateThemeColors];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    self.fieldFocused = NO;
    [self updateThemeColors];
}

@end

@interface AWChecklistView ()
@property(nonatomic, strong) UIStackView *rows;
@property(nonatomic, strong) UILabel *summaryLabel;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *rowViews;
@end

@implementation AWChecklistView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _rows = [UIStackView new];
    _rows.axis = UILayoutConstraintAxisVertical;
    _rows.spacing = 11.0;
    _summaryLabel = [UILabel new];
    _summaryLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightMedium);
    _summaryLabel.adjustsFontForContentSizeCategory = YES;
    _summaryLabel.numberOfLines = 0;
    _summaryLabel.hidden = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _rows, _summaryLabel ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10.0;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _rowViews = [NSMutableArray array];
    NSArray<NSString *> *titles = @[ @"地址可达", @"账号有效", @"可写入" ];
    for (NSString *title in titles) {
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [icon.widthAnchor constraintEqualToConstant:20].active = YES;
        [icon.heightAnchor constraintEqualToConstant:20].active = YES;

        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        spinner.hidesWhenStopped = YES;
        spinner.color = AWAmberColor();
        [spinner.widthAnchor constraintEqualToConstant:20].active = YES;
        [spinner.heightAnchor constraintEqualToConstant:20].active = YES;

        UILabel *titleLabel = [UILabel new];
        titleLabel.text = title;
        titleLabel.font = AWFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
        titleLabel.adjustsFontForContentSizeCategory = YES;
        titleLabel.textColor = AWInkColor();
        UILabel *detailLabel = [UILabel new];
        detailLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
        detailLabel.adjustsFontForContentSizeCategory = YES;
        detailLabel.textColor = AWMutedColor();
        detailLabel.numberOfLines = 0;

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, detailLabel ]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 2.0;
        UIView *iconHolder = [UIView new];
        [iconHolder addSubview:icon];
        [iconHolder addSubview:spinner];
        [iconHolder.widthAnchor constraintEqualToConstant:20].active = YES;
        [iconHolder.heightAnchor constraintEqualToConstant:20].active = YES;
        [icon.centerXAnchor constraintEqualToAnchor:iconHolder.centerXAnchor].active = YES;
        [icon.centerYAnchor constraintEqualToAnchor:iconHolder.centerYAnchor].active = YES;
        [spinner.centerXAnchor constraintEqualToAnchor:iconHolder.centerXAnchor].active = YES;
        [spinner.centerYAnchor constraintEqualToAnchor:iconHolder.centerYAnchor].active = YES;

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ iconHolder, textStack ]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentTop;
        row.spacing = 10.0;
        row.isAccessibilityElement = YES;
        row.accessibilityLabel = title;
        [self.rows addArrangedSubview:row];
        [_rowViews addObject:@{ @"icon" : icon, @"spinner" : spinner, @"title" : titleLabel, @"detail" : detailLabel, @"row" : row }];
    }
    [self reset];
    return self;
}

- (void)reset {
    [self.rows setHidden:NO];
    for (NSUInteger i = 0; i < self.rowViews.count; i++) {
        [self applyState:AWTestStepStatePending toIndex:i detail:i == 0 ? @"等待测试" : @"等待上一步"];
    }
    self.summaryLabel.hidden = YES;
    self.summaryLabel.text = nil;
}

- (void)setStage:(AWTestStage)stage state:(AWTestStepState)state detail:(NSString *)detail {
    NSInteger index = (NSInteger)stage;
    if (index < 0 || index >= (NSInteger)self.rowViews.count) return;
    [self applyState:state toIndex:(NSUInteger)index detail:detail];
}

- (void)applyState:(AWTestStepState)state toIndex:(NSUInteger)index detail:(NSString *)detail {
    NSDictionary *views = self.rowViews[index];
    UIImageView *icon = views[@"icon"];
    UIActivityIndicatorView *spinner = views[@"spinner"];
    UILabel *title = views[@"title"];
    UILabel *detailLabel = views[@"detail"];
    UIView *row = views[@"row"];
    NSString *symbol = @"circle";
    UIColor *color = AWMutedColor();
    icon.hidden = NO;
    [spinner stopAnimating];

    switch (state) {
        case AWTestStepStateRunning:
            icon.hidden = YES;
            [spinner startAnimating];
            color = AWAmberColor();
            break;
        case AWTestStepStatePassed:
            symbol = @"checkmark.circle.fill";
            color = AWSignalColor();
            break;
        case AWTestStepStateFailed:
            symbol = @"xmark.circle.fill";
            color = AWRustColor();
            break;
        default:
            symbol = @"circle";
            color = AWMutedColor();
            break;
    }
    icon.image = AWIcon(symbol, 18, UIFontWeightSemibold);
    icon.tintColor = color;
    title.textColor = state == AWTestStepStatePending ? AWMutedColor() : AWInkColor();
    detailLabel.text = detail ?: @"";
    detailLabel.textColor = state == AWTestStepStateFailed ? AWRustColor() : AWMutedColor();
    row.accessibilityValue = [NSString stringWithFormat:@"%@，%@", title.text ?: @"", detail ?: @""];
}

- (void)setSummary:(NSString *)summary success:(BOOL)success {
    self.summaryLabel.text = summary;
    self.summaryLabel.textColor = success ? AWSignalColor() : AWRustColor();
    self.summaryLabel.hidden = summary.length == 0;
}

@end

@interface AWActivityRowView ()
@property(nonatomic, strong) UIImageView *stateIcon;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *metaLabel;
@property(nonatomic, strong) UILabel *errorLabel;
@property(nonatomic, strong) UIView *rule;
@end

@implementation AWActivityRowView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _stateIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
    _stateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _stateIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_stateIcon.widthAnchor constraintEqualToConstant:22].active = YES;
    [_stateIcon.heightAnchor constraintEqualToConstant:22].active = YES;

    _nameLabel = [UILabel new];
    _nameLabel.font = AWFont(UIFontTextStyleSubheadline, UIFontWeightSemibold);
    _nameLabel.adjustsFontForContentSizeCategory = YES;
    _nameLabel.textColor = AWInkColor();
    _nameLabel.numberOfLines = 2;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _metaLabel = [UILabel new];
    _metaLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    _metaLabel.adjustsFontForContentSizeCategory = YES;
    _metaLabel.textColor = AWMutedColor();
    _metaLabel.numberOfLines = 1;
    _errorLabel = [UILabel new];
    _errorLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightRegular);
    _errorLabel.adjustsFontForContentSizeCategory = YES;
    _errorLabel.textColor = AWRustColor();
    _errorLabel.numberOfLines = 2;
    _errorLabel.hidden = YES;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[ _nameLabel, _metaLabel, _errorLabel ]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 3.0;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ _stateIcon, textStack ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 10.0;
    [self addSubview:row];

    _rule = [UIView new];
    _rule.translatesAutoresizingMaskIntoConstraints = NO;
    _rule.backgroundColor = AWRuleColor();
    [self addSubview:_rule];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-11],
        [_rule.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32],
        [_rule.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_rule.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_rule.heightAnchor constraintEqualToConstant:0.5],
    ]];
    self.isAccessibilityElement = YES;
    return self;
}

- (void)configureWithItem:(NSDictionary *)item {
    NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"未命名文件";
    if (name.length == 0) name = @"未命名文件";
    NSString *status = [item[@"status"] isKindOfClass:NSString.class] ? item[@"status"] : @"queued";
    NSString *error = [item[@"error"] isKindOfClass:NSString.class] ? item[@"error"] : @"";
    unsigned long long bytes = [item[@"size"] unsignedLongLongValue];
    NSTimeInterval time = [item[@"time"] doubleValue];
    NSString *statusText = @"等待上传";
    NSString *symbol = @"clock";
    UIColor *color = AWAmberColor();
    if ([status isEqualToString:@"uploaded"]) {
        statusText = @"已上传";
        symbol = @"checkmark.circle.fill";
        color = AWSignalColor();
    } else if ([status isEqualToString:@"uploading"]) {
        statusText = @"正在上传";
        symbol = @"arrow.up.circle.fill";
        color = AWAmberColor();
    } else if ([status isEqualToString:@"waiting_network"]) {
        statusText = @"等待网络";
        symbol = @"wifi.exclamationmark";
        color = AWRustColor();
    } else if ([status isEqualToString:@"failed"]) {
        statusText = @"需要处理";
        symbol = @"exclamationmark.triangle.fill";
        color = AWRustColor();
    } else if ([status isEqualToString:@"queued"]) {
        statusText = @"排队中";
        symbol = @"clock";
        color = AWAmberColor();
    }
    self.stateIcon.image = AWIcon(symbol, 19, UIFontWeightSemibold);
    self.stateIcon.tintColor = color;
    self.nameLabel.text = name;
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObjects:statusText, AWFormatBytes(bytes), nil];
    if (time > 0) [parts addObject:AWShortTimeString(time)];
    self.metaLabel.text = [parts componentsJoinedByString:@"  ·  "];
    self.errorLabel.text = error.length ? error : nil;
    self.errorLabel.hidden = error.length == 0;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@，%@", name, statusText, self.metaLabel.text ?: @""];
    if (error.length) self.accessibilityValue = error;
}

- (void)updateThemeColors {
    self.rule.backgroundColor = AWRuleColor();
    self.nameLabel.textColor = AWInkColor();
    self.metaLabel.textColor = AWMutedColor();
}

@end

@interface AWMonitorView ()
@property(nonatomic, strong) AWStatusDotView *dot;
@property(nonatomic, strong) UILabel *stateLabel;
@property(nonatomic, strong) UILabel *networkLabel;
@property(nonatomic, strong) UILabel *countLabel;
@property(nonatomic, strong) UILabel *countCaption;
@property(nonatomic, strong) UILabel *folderCaption;
@property(nonatomic, strong) UILabel *pathLabel;
@property(nonatomic, strong) UILabel *lastUploadLabel;
@property(nonatomic, strong) AWSignalView *signal;
@end

@implementation AWMonitorView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = AWMonitorColor();
    self.layer.cornerRadius = 22.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [AWMonitorTextColor() colorWithAlphaComponent:0.10].CGColor;

    _dot = [[AWStatusDotView alloc] initWithFrame:CGRectZero];
    _dot.translatesAutoresizingMaskIntoConstraints = NO;
    [_dot.widthAnchor constraintEqualToConstant:12].active = YES;
    [_dot.heightAnchor constraintEqualToConstant:12].active = YES;

    _stateLabel = [UILabel new];
    _stateLabel.font = AWFont(UIFontTextStyleFootnote, UIFontWeightSemibold);
    _stateLabel.adjustsFontForContentSizeCategory = YES;
    _stateLabel.textColor = AWMonitorTextColor();

    _networkLabel = [UILabel new];
    _networkLabel.font = AWFont(UIFontTextStyleCaption2, UIFontWeightMedium);
    _networkLabel.adjustsFontForContentSizeCategory = YES;
    _networkLabel.textColor = AWMonitorMutedColor();
    _networkLabel.textAlignment = NSTextAlignmentRight;
    [_networkLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIView *spacer = [UIView new];
    [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[ _dot, _stateLabel, spacer, _networkLabel ]];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.alignment = UIStackViewAlignmentCenter;
    top.spacing = 8.0;

    _countLabel = [UILabel new];
    _countLabel.font = AWNumericFont();
    _countLabel.adjustsFontForContentSizeCategory = YES;
    _countLabel.textColor = AWMonitorTextColor();
    _countLabel.text = @"0";
    _countCaption = [UILabel new];
    _countCaption.font = AWFont(UIFontTextStyleCaption1, UIFontWeightMedium);
    _countCaption.adjustsFontForContentSizeCategory = YES;
    _countCaption.textColor = AWMonitorMutedColor();
    _countCaption.text = @"个文件待上传";
    _countCaption.numberOfLines = 1;

    UIStackView *countStack = [[UIStackView alloc] initWithArrangedSubviews:@[ _countLabel, _countCaption ]];
    countStack.axis = UILayoutConstraintAxisVertical;
    countStack.spacing = -2.0;
    countStack.alignment = UIStackViewAlignmentLeading;

    _folderCaption = [UILabel new];
    _folderCaption.font = AWFont(UIFontTextStyleCaption1, UIFontWeightSemibold);
    _folderCaption.textColor = AWMonitorMutedColor();
    _folderCaption.text = @"监控文件夹";
    _pathLabel = [UILabel new];
    _pathLabel.font = AWPathFont();
    _pathLabel.adjustsFontForContentSizeCategory = YES;
    _pathLabel.textColor = AWMonitorTextColor();
    _pathLabel.numberOfLines = 2;
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.text = @"还没有选择文件夹";
    _lastUploadLabel = [UILabel new];
    _lastUploadLabel.font = AWFont(UIFontTextStyleCaption2, UIFontWeightRegular);
    _lastUploadLabel.adjustsFontForContentSizeCategory = YES;
    _lastUploadLabel.textColor = AWMonitorMutedColor();
    _lastUploadLabel.text = @"新文件出现后会自动上传";
    _lastUploadLabel.numberOfLines = 1;

    UIStackView *detailStack = [[UIStackView alloc] initWithArrangedSubviews:@[ _folderCaption, _pathLabel, _lastUploadLabel ]];
    detailStack.axis = UILayoutConstraintAxisVertical;
    detailStack.spacing = 5.0;
    detailStack.alignment = UIStackViewAlignmentFill;

    UIStackView *middle = [[UIStackView alloc] initWithArrangedSubviews:@[ countStack, detailStack ]];
    middle.axis = UILayoutConstraintAxisHorizontal;
    middle.alignment = UIStackViewAlignmentTop;
    middle.spacing = 18.0;
    [countStack.widthAnchor constraintGreaterThanOrEqualToConstant:96].active = YES;

    _signal = [[AWSignalView alloc] initWithFrame:CGRectZero];
    _signal.translatesAutoresizingMaskIntoConstraints = NO;
    [_signal.widthAnchor constraintEqualToConstant:118].active = YES;
    [_signal.heightAnchor constraintEqualToConstant:30].active = YES;

    _scanButton = [AWDynamicButton buttonWithType:UIButtonTypeSystem];
    _scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    _scanButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    _scanButton.layer.cornerRadius = 11.0;
    [_scanButton setTitle:@"立即扫描" forState:UIControlStateNormal];
    [_scanButton setTitleColor:AWMonitorTextColor() forState:UIControlStateNormal];
    _scanButton.titleLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightSemibold);
    _scanButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [_scanButton.heightAnchor constraintEqualToConstant:44].active = YES;

    _stopButton = [AWDynamicButton buttonWithType:UIButtonTypeSystem];
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    _stopButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    _stopButton.layer.cornerRadius = 11.0;
    [_stopButton setTitle:@"停止监控" forState:UIControlStateNormal];
    [_stopButton setTitleColor:AWMonitorMutedColor() forState:UIControlStateNormal];
    _stopButton.titleLabel.font = AWFont(UIFontTextStyleCaption1, UIFontWeightSemibold);
    _stopButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    [_stopButton.heightAnchor constraintEqualToConstant:44].active = YES;

    UIView *buttonSpacer = [UIView new];
    [buttonSpacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[ _signal, buttonSpacer, _scanButton, _stopButton ]];
    bottom.axis = UILayoutConstraintAxisHorizontal;
    bottom.alignment = UIStackViewAlignmentCenter;
    bottom.spacing = 8.0;

    UIView *rule = [UIView new];
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    rule.backgroundColor = [AWMonitorTextColor() colorWithAlphaComponent:0.10];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ top, middle, rule, bottom ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 15.0;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
        [rule.heightAnchor constraintEqualToConstant:0.5],
    ]];
    return self;
}

- (void)updateStateText:(NSString *)stateText
                  detail:(NSString *)detail
                 pending:(NSInteger)pending
               watchPath:(NSString *)watchPath
              lastUpload:(NSString *)lastUpload
                 network:(NSString *)network
                barActive:(BOOL)barActive
                  enabled:(BOOL)enabled
                    color:(UIColor *)stateColor {
    self.stateLabel.text = stateText;
    self.dot.backgroundColor = UIColor.clearColor;
    [self.dot setColor:stateColor active:enabled];
    self.networkLabel.text = network;
    self.countLabel.text = [NSString stringWithFormat:@"%ld", (long)MAX(0, pending)];
    self.countCaption.text = pending > 0 ? @"个文件待上传" : @"队列空闲";
    self.pathLabel.text = watchPath.length ? watchPath : @"还没有选择文件夹";
    self.lastUploadLabel.text = lastUpload.length ? lastUpload : (enabled ? @"等待新文件" : @"新文件出现后会自动上传");
    self.scanButton.hidden = !enabled;
    self.stopButton.hidden = !enabled;
    [self.signal setActive:enabled && barActive animated:YES];
    if (detail.length) {
        self.lastUploadLabel.text = detail;
    }
    self.stateLabel.accessibilityLabel = @"监控状态";
    self.stateLabel.accessibilityValue = stateText;
    self.networkLabel.accessibilityLabel = @"网络";
    self.networkLabel.accessibilityValue = network;
    self.countLabel.accessibilityLabel = @"待上传文件";
    self.countLabel.accessibilityValue = [NSString stringWithFormat:@"%ld", (long)MAX(0, pending)];
    self.pathLabel.accessibilityLabel = @"监控文件夹";
    self.pathLabel.accessibilityValue = watchPath.length ? watchPath : @"未选择文件夹";
}

@end

@implementation AWToastView

+ (void)showMessage:(NSString *)message inView:(UIView *)view {
    if (!view || message.length == 0) return;
    [view viewWithTag:99221].hidden = YES;
    [[view viewWithTag:99221] removeFromSuperview];

    AWToastView *toast = [AWToastView new];
    toast.tag = 99221;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.backgroundColor = AWMonitorColor();
    toast.layer.cornerRadius = 12.0;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    toast.alpha = 0.0;
    toast.transform = CGAffineTransformMakeTranslation(0, 8);
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = message;
    label.font = AWFont(UIFontTextStyleFootnote, UIFontWeightMedium);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = AWMonitorTextColor();
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    [toast addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-16],
        [label.topAnchor constraintEqualToAnchor:toast.topAnchor constant:11],
        [label.bottomAnchor constraintEqualToAnchor:toast.bottomAnchor constant:-11],
    ]];
    [view addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:view.leadingAnchor constant:24],
        [toast.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-24],
        [toast.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-22],
    ]];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    [UIView animateWithDuration:0.24 animations:^{
        toast.alpha = 1.0;
        toast.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:2.5 options:0 animations:^{
            toast.alpha = 0.0;
            toast.transform = CGAffineTransformMakeTranslation(0, 6);
        } completion:^(BOOL done) {
            [toast removeFromSuperview];
        }];
    }];
}

@end
