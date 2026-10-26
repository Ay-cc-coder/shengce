#import <UIKit/UIKit.h>
#import "AWTheme.h"
#import "AWWebDAVClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface AWFieldView : AWDynamicView
@property(nonatomic, strong, readonly) UILabel *captionLabel;
@property(nonatomic, strong, readonly) UITextField *textField;
@property(nonatomic, strong, readonly) UILabel *hintLabel;
- (instancetype)initWithTitle:(NSString *)title
                  placeholder:(NSString *)placeholder
                       secure:(BOOL)secure
                   keyboardType:(UIKeyboardType)keyboardType;
- (void)setFieldEnabled:(BOOL)enabled;
- (void)setErrorText:(nullable NSString *)error;
- (void)setHintText:(nullable NSString *)hint;
@end

@interface AWChecklistView : AWDynamicView
- (void)reset;
- (void)setStage:(AWTestStage)stage state:(AWTestStepState)state detail:(NSString *)detail;
- (void)setSummary:(nullable NSString *)summary success:(BOOL)success;
@end

@interface AWActivityRowView : AWDynamicView
- (void)configureWithItem:(NSDictionary *)item;
@end

@interface AWMonitorView : AWDynamicView
@property(nonatomic, strong, readonly) UIButton *scanButton;
@property(nonatomic, strong, readonly) UIButton *stopButton;
- (void)updateStateText:(NSString *)stateText
                  detail:(NSString *)detail
                 pending:(NSInteger)pending
               watchPath:(NSString *)watchPath
              lastUpload:(NSString *)lastUpload
                 network:(NSString *)network
                barActive:(BOOL)barActive
                  enabled:(BOOL)enabled
                    color:(UIColor *)stateColor;
@end

@interface AWToastView : UIView
+ (void)showMessage:(NSString *)message inView:(UIView *)view;
@end

NS_ASSUME_NONNULL_END
