#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT UIColor *AWInkColor(void);
FOUNDATION_EXPORT UIColor *AWPaperColor(void);
FOUNDATION_EXPORT UIColor *AWSurfaceColor(void);
FOUNDATION_EXPORT UIColor *AWMutedColor(void);
FOUNDATION_EXPORT UIColor *AWFaintColor(void);
FOUNDATION_EXPORT UIColor *AWRuleColor(void);
FOUNDATION_EXPORT UIColor *AWAmberColor(void);
FOUNDATION_EXPORT UIColor *AWAmberInkColor(void);
FOUNDATION_EXPORT UIColor *AWAmberTextColor(void);
FOUNDATION_EXPORT UIColor *AWSignalColor(void);
FOUNDATION_EXPORT UIColor *AWRustColor(void);
FOUNDATION_EXPORT UIColor *AWMonitorColor(void);
FOUNDATION_EXPORT UIColor *AWMonitorTextColor(void);
FOUNDATION_EXPORT UIColor *AWMonitorMutedColor(void);

FOUNDATION_EXPORT UIFont *AWFont(UIFontTextStyle style, UIFontWeight weight);
FOUNDATION_EXPORT UIFont *AWDisplayFont(void);
FOUNDATION_EXPORT UIFont *AWNumericFont(void);
FOUNDATION_EXPORT UIFont *AWPathFont(void);
FOUNDATION_EXPORT UIImage * _Nullable AWIcon(NSString *symbolName, CGFloat pointSize, UIFontWeight weight);

FOUNDATION_EXPORT void AWApplyPressStyle(UIButton *button);
FOUNDATION_EXPORT void AWLayoutPillButton(UIButton *button, UIColor *background, UIColor *foreground);

@interface AWDynamicView : UIView
@end

@interface AWDynamicButton : UIButton
@end

@interface AWStatusDotView : UIView
- (void)setColor:(UIColor *)color active:(BOOL)active;
@end

@interface AWSignalView : UIView
@property(nonatomic, assign, getter=isActive) BOOL active;
- (void)setActive:(BOOL)active animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
