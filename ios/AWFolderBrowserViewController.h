#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AWFolderBrowserDelegate <NSObject>
- (void)folderBrowser:(UIViewController *)browser didChooseFolder:(NSString *)path;
@end

@interface AWFolderBrowserViewController : UIViewController

@property(nonatomic, weak, nullable) id<AWFolderBrowserDelegate> delegate;
@property(nonatomic, copy) NSString *initialPath;

@end

NS_ASSUME_NONNULL_END
