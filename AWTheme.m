#import "AWTheme.h"
#import <math.h>

@interface UIColor (AudioWatch)
+ (UIColor *)colorWithHexString:(NSString *)hex;
@end

static UIColor *AWColor(NSString *lightHex, NSString *darkHex) {
    UIColor *light = [UIColor colorWithHexString:lightHex];
    UIColor *dark = [UIColor colorWithHexString:darkHex];
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

@implementation UIColor (AudioWatch)
+ (UIColor *)colorWithHexString:(NSString *)hex {
    NSString *value = [hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if (value.length != 6) return UIColor.blackColor;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    if (![scanner scanHexInt:&rgb]) return UIColor.blackColor;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}
@end

UIColor *AWInkColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#241A11", @"#F5EDDF"); });
    return color;
}

UIColor *AWPaperColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#F2EBDD", @"#15100B"); });
    return color;
}

UIColor *AWSurfaceColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#FBF6EA", @"#201811"); });
    return color;
}

UIColor *AWMutedColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#776858", @"#B9AA96"); });
    return color;
}

UIColor *AWFaintColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#A29380", @"#7D7163"); });
    return color;
}

UIColor *AWRuleColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#D9CDB9", @"#3B2E21"); });
    return color;
}

UIColor *AWAmberColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#B0741A", @"#E7AE4B"); });
    return color;
}

UIColor *AWAmberInkColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#1C1208", @"#241708"); });
    return color;
}

UIColor *AWAmberTextColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#8F5C10", @"#E7AE4B"); });
    return color;
}

UIColor *AWSignalColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#356B4D", @"#7EBA91"); });
    return color;
}

UIColor *AWRustColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#AE4A34", @"#E4876F"); });
    return color;
}

UIColor *AWMonitorColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#26190F", @"#21160E"); });
    return color;
}

UIColor *AWMonitorTextColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#F6ECDA", @"#F6ECDA"); });
    return color;
}

UIColor *AWMonitorMutedColor(void) {
    static UIColor *color;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ color = AWColor(@"#B6A38A", @"#B6A38A"); });
    return color;
}

UIFont *AWFont(UIFontTextStyle style, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:17 weight:weight];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
}

UIFont *AWDisplayFont(void) {
    UIFont *base = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:base];
}

UIFont *AWNumericFont(void) {
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:50 weight:UIFontWeightSemibold];
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:base];
}

UIFont *AWPathFont(void) {
    UIFont *base = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:base];
}

UIImage *AWIcon(NSString *symbolName, CGFloat pointSize, UIFontWeight weight) {
    UIImageConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    return [UIImage systemImageNamed:symbolName withConfiguration:configuration];
}

void AWApplyPressStyle(UIButton *button) {
    button.titleLabel.font = AWFont(UIFontTextStyleHeadline, UIFontWeightSemibold);
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 1;
}

void AWLayoutPillButton(UIButton *button, UIColor *background, UIColor *foreground) {
    AWApplyPressStyle(button);
    button.backgroundColor = background;
    [button setTitleColor:foreground forState:UIControlStateNormal];
    button.layer.cornerRadius = 14.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 20, 14, 20);
}

@implementation AWDynamicView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self respondsToSelector:@selector(updateThemeColors)]) {
        [self performSelector:@selector(updateThemeColors)];
    }
}

@end

@implementation AWDynamicButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.titleLabel.adjustsFontForContentSizeCategory = YES;
        self.titleLabel.numberOfLines = 1;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.alpha = highlighted ? 0.82 : 1.0;
        return;
    }
    [UIView animateWithDuration:0.14
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
        self.alpha = highlighted ? 0.88 : 1.0;
    } completion:nil];
}

@end

@implementation AWStatusDotView {
    UIView *_core;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        _core = [UIView new];
        _core.translatesAutoresizingMaskIntoConstraints = NO;
        _core.layer.cornerRadius = 4.0;
        [self addSubview:_core];
        [NSLayoutConstraint activateConstraints:@[
            [_core.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_core.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_core.widthAnchor constraintEqualToConstant:8],
            [_core.heightAnchor constraintEqualToConstant:8],
        ]];
    }
    return self;
}

- (void)setColor:(UIColor *)color active:(BOOL)active {
    _core.backgroundColor = color;
    _core.layer.shadowColor = color.CGColor;
    _core.layer.shadowOpacity = active ? 0.45 : 0.0;
    _core.layer.shadowRadius = 5.0;
    _core.layer.shadowOffset = CGSizeZero;
    self.accessibilityValue = active ? @"活动" : @"空闲";
}

@end

@implementation AWSignalView {
    NSMutableArray<CALayer *> *_bars;
    NSArray<NSNumber *> *_heights;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.isAccessibilityElement = NO;
        self.backgroundColor = UIColor.clearColor;
        _heights = @[ @0.24, @0.44, @0.32, @0.62, @0.82, @0.56, @0.38, @0.72, @0.96,
                      @0.64, @0.42, @0.74, @0.50, @0.30, @0.54, @0.34, @0.22, @0.40 ];
        _bars = [NSMutableArray array];
        for (NSUInteger i = 0; i < _heights.count; i++) {
            CALayer *bar = [CALayer layer];
            bar.cornerRadius = 1.5;
            bar.backgroundColor = AWMonitorMutedColor().CGColor;
            [self.layer addSublayer:bar];
            [_bars addObject:bar];
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat gap = 3.0;
    CGFloat width = MAX(2.0, floor((CGRectGetWidth(self.bounds) - gap * (_bars.count - 1)) / _bars.count));
    CGFloat total = width * _bars.count + gap * (_bars.count - 1);
    CGFloat x = MAX(0, (CGRectGetWidth(self.bounds) - total) / 2.0);
    for (NSUInteger i = 0; i < _bars.count; i++) {
        CGFloat fraction = _heights[i].doubleValue;
        CGFloat height = MAX(3.0, CGRectGetHeight(self.bounds) * fraction);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _bars[i].frame = CGRectMake(x, CGRectGetHeight(self.bounds) - height, width, height);
        [CATransaction commit];
        x += width + gap;
    }
}

- (void)setActive:(BOOL)active {
    [self setActive:active animated:YES];
}

- (void)setActive:(BOOL)active animated:(BOOL)animated {
    _active = active;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _bars.count; i++) {
        CALayer *bar = _bars[i];
        [bar removeAnimationForKey:@"aw.breathe"];
        if (active) {
            bar.backgroundColor = (i % 4 == 0 ? AWAmberColor() : AWMonitorTextColor()).CGColor;
            bar.opacity = reduceMotion ? (i % 3 == 0 ? 0.9 : 0.55) : 1.0;
        } else {
            bar.backgroundColor = AWMonitorMutedColor().CGColor;
            bar.opacity = i % 5 == 0 ? 0.72 : 0.34;
        }
    }
    [CATransaction commit];

    if (!active || reduceMotion || !animated) return;
    CFTimeInterval now = CACurrentMediaTime();
    for (NSUInteger i = 0; i < _bars.count; i++) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @(0.28);
        animation.toValue = @(1.0);
        animation.duration = 0.55 + (i % 6) * 0.11;
        animation.autoreverses = YES;
        animation.repeatCount = HUGE_VALF;
        animation.timeOffset = fmod(now + i * 0.07, animation.duration);
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_bars[i] addAnimation:animation forKey:@"aw.breathe"];
    }
}

@end
