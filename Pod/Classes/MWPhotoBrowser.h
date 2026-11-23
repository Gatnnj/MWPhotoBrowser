//
//  MWPhotoBrowser.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MWPhoto.h"
#import "MWPhotoProtocol.h"
#import "MWToolBar.h"

/// 调试日志开关：置 1 开启，默认关闭。
/// Debug logging switch: set to 1 to enable. Disabled by default.
#if 0
#define MWLog(x, ...) NSLog(x, ## __VA_ARGS__);
#else
#define MWLog(x, ...)
#endif

NS_ASSUME_NONNULL_BEGIN

@class MWPhotoBrowser;

/// 自定义加载指示视图的可选进度接口。
/// Optional progress interface for custom loading indicator views.
///
/// 未实现该方法的视图只会显示不确定进度动画。
/// Views that do not implement this method show an indeterminate animation only.
@protocol MWPhotoBrowserLoadingView <NSObject>
@optional

/// 接收 0 到 1 的下载进度。
/// Receives download progress in the range 0 to 1.
/// @param progress 当前进度 / Current progress.
- (void)setProgress:(CGFloat)progress;

@end

/// 图片数据源与事件代理。
/// Photo data source and event delegate.
///
/// 浏览器不持有图片数据，所有数据均通过本协议按需索取。
/// The browser does not own photo data; all data is requested on demand through this protocol.
@protocol MWPhotoBrowserDelegate <NSObject>

/// 返回图片总数。必需方法。
/// Returns the total number of photos. Required.
/// @param photoBrowser 发起询问的浏览器 / The browser making the request.
- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser;

/// 返回指定索引的图片对象。必需方法。
/// Returns the photo object at the given index. Required.
/// @param photoBrowser 发起询问的浏览器 / The browser making the request.
/// @param index 图片索引 / Photo index.
- (nullable id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index;

@optional

/// 返回指定索引的缩略图对象，用于网格视图与占位显示。
/// Returns the thumbnail photo at the given index, used by the grid view and placeholders.
/// @param photoBrowser 发起询问的浏览器 / The browser making the request.
/// @param index 图片索引 / Photo index.
/// @discussion 未实现时网格功能自动关闭。
/// The grid feature is disabled automatically when this method is not implemented.
- (nullable id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index;

/// 返回指定图片在列表中的缩略图视图，作为连贯转场的起点与飞回目标。
/// Returns the thumbnail view for the photo, used as the source and destination of the coherent transition.
/// @param photoBrowser 发起询问的浏览器 / The browser making the request.
/// @param index 图片索引 / Photo index.
/// @discussion 仅在 enableCustomTransition 为 YES 时生效；返回 nil 时转场降级为渐隐。
/// Effective only when enableCustomTransition is YES. Returning nil falls back to a fade transition.
- (nullable UIView *)photoBrowser:(MWPhotoBrowser *)photoBrowser startingViewForPhotoAtIndex:(NSUInteger)index;

/// 返回指定图片显示在导航栏上的标题。
/// Returns the navigation bar title for the given photo.
/// @param photoBrowser 发起询问的浏览器 / The browser making the request.
/// @param index 图片索引 / Photo index.
- (nullable NSString *)photoBrowser:(MWPhotoBrowser *)photoBrowser titleForPhotoAtIndex:(NSUInteger)index;

/// 通知代理当前显示的图片已切换。
/// Notifies the delegate that the displayed photo has changed.
/// @param photoBrowser 发起通知的浏览器 / The browser sending the notification.
/// @param index 当前图片索引 / Index of the current photo.
- (void)photoBrowser:(MWPhotoBrowser *)photoBrowser didDisplayPhotoAtIndex:(NSUInteger)index;

/// 用户点击完成按钮时回调，由代理自行关闭浏览器。
/// Called when the user taps Done; the delegate is responsible for dismissing the browser.
/// @param photoBrowser 待关闭的浏览器 / The browser to dismiss.
/// @discussion 未实现时浏览器自行执行 dismiss。
/// When not implemented, the browser dismisses itself.
- (void)photoBrowserDidFinishModalPresentation:(MWPhotoBrowser *)photoBrowser;

@end

/// 支持网格浏览、标题与选择的图片浏览器。
/// A photo browser with optional grid view, captions and selections.
///
/// 两种使用方式均受支持：
/// Both usage styles are supported:
///
/// 1. 外部组合（推荐）：创建实例、设置代理与属性、按需注入 provider block。
/// 1. External composition (recommended): create an instance, set the delegate and properties,
///    and inject provider blocks as needed.
///
/// 2. 继承定制：导入 MWPhotoBrowserSubclassing.h，重写其中声明的受支持钩子。
/// 2. Subclassing: import MWPhotoBrowserSubclassing.h and override the supported hooks declared there.
///
/// @code
/// MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
/// browser.enableGrid = NO;
/// UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:browser];
/// [self presentViewController:navigation animated:YES completion:nil];
/// @endcode
@interface MWPhotoBrowser : UIViewController <UIScrollViewDelegate, UIViewControllerTransitioningDelegate>

#pragma mark - Configuration

/// 图片数据源与事件代理。
/// Data source and event delegate.
@property (nonatomic, weak, nullable) id<MWPhotoBrowserDelegate> delegate;

/// 宽高比接近屏幕时是否放大图片以铺满屏幕。默认 YES。
/// Whether to zoom photos to fill the screen when their aspect ratio is close to the screen's. Defaults to YES.
@property (nonatomic) BOOL zoomPhotosToFill;

/// 是否始终显示导航栏与工具栏，禁用自动隐藏。默认 NO。
/// Whether to keep the navigation bar and toolbar always visible, disabling auto-hide. Defaults to NO.
@property (nonatomic) BOOL alwaysShowControls;

/// 是否启用网格视图。默认 YES，且需代理实现 thumbPhotoAtIndex: 才会真正生效。
/// Whether the grid view is enabled. Defaults to YES and requires the delegate's thumbPhotoAtIndex: to take effect.
@property (nonatomic) BOOL enableGrid;

/// 是否启用上下轻扫关闭。默认 YES；enableCustomTransition 为 YES 时本开关被忽略。
/// Whether swipe-to-dismiss is enabled. Defaults to YES. Ignored when enableCustomTransition is YES.
@property (nonatomic) BOOL enableSwipeToDismiss;

/// 视图加载时是否隐藏工具栏。默认 NO。
/// Whether the toolbar starts hidden when the view loads. Defaults to NO.
/// @discussion 该值在视图加载时应用；加载后请通过 customToolBarItems: 等方法调整工具栏。
/// Applied at view load time. Use customToolBarItems: and related methods to adjust the toolbar afterwards.
@property (nonatomic) BOOL isHiddenToolBar;

/// 网格视图是否正在显示的状态标记，由网格控制器维护。
/// State flag indicating whether the grid view is showing. Maintained by the grid controller.
@property (nonatomic) BOOL isShowGriding;

/// 是否启用自定义丝滑转场（连贯放大进入 + 拖拽关闭）。默认 NO，保持原有行为。
/// Whether to enable the custom smooth transition (coherent zoom-in plus drag-to-dismiss). Defaults to NO.
/// @discussion 启用后需以 UIModalPresentationOverFullScreen 呈现以保留底层视图，
/// 并将包装用导航控制器的 transitioningDelegate 指向本浏览器。
/// When enabled, present with UIModalPresentationOverFullScreen to keep the underlying view visible,
/// and point the wrapping navigation controller's transitioningDelegate at this browser.
@property (nonatomic) BOOL enableCustomTransition;

/// 是否以网格视图作为起始界面。默认 NO；置 YES 会强制启用 enableGrid。
/// Whether to start on the grid view. Defaults to NO. Setting YES forces enableGrid to YES.
@property (nonatomic) BOOL startOnGrid;

/// 控件自动隐藏前的等待秒数。默认 5。
/// Delay in seconds before the controls hide automatically. Defaults to 5.
@property (nonatomic) NSUInteger delayToHideElements;

/// 当前显示图片的索引。只读。
/// Index of the currently displayed photo. Read-only.
/// @discussion 设置起始页请使用 setCurrentPhotoIndex:。
/// Use setCurrentPhotoIndex: to set the starting page.
@property (nonatomic, readonly) NSUInteger currentIndex;

#pragma mark - Providers

/// 自定义加载指示视图的工厂 block。
/// Factory block for custom loading indicator views.
/// @discussion 返回已配置的新视图；返回 nil 则使用内置进度指示器。
/// 返回的视图会在容器内居中，并在加载结束时隐藏；实现 setProgress: 可接收 0 到 1 的进度。
/// Return a newly configured view, or nil to use the built-in progress indicator.
/// The returned view is centered in its container and hidden when loading finishes.
/// Implement setProgress: to receive progress from 0 to 1.
@property (nonatomic, copy, nullable) UIView * _Nullable (^loadingViewProvider)(UIView *container);

/// 转场起始缩略图的提供者 block，按当前页索引查询。
/// Provider block for the transition source thumbnail, queried with the current page index.
/// @discussion 可在代理就绪前设置；其结果优先于代理的 startingViewForPhotoAtIndex:。
/// Can be set before the delegate is ready. Its result takes precedence over the delegate's startingViewForPhotoAtIndex:.
@property (nonatomic, copy, nullable) UIView * _Nullable (^startingViewProvider)(NSUInteger index);

#pragma mark - Initialization

/// 使用固定图片数组初始化，无需实现数据源代理。
/// Initializes with a fixed photo array; no data source delegate is required.
/// @param photosArray 图片对象数组 / Array of photo objects.
- (instancetype)initWithPhotos:(NSArray<id<MWPhoto>> *)photosArray;

/// 使用数据源代理初始化，图片按需向代理索取。
/// Initializes with a data source delegate; photos are requested on demand.
/// @param delegate 数据源与事件代理 / Data source and event delegate.
- (instancetype)initWithDelegate:(id <MWPhotoBrowserDelegate>)delegate;

#pragma mark - Data

/// 设置浏览器起始显示的图片索引，越界时自动收敛到有效范围。
/// Sets the starting photo index, clamped to the valid range when out of bounds.
/// @param index 目标图片索引 / Target photo index.
- (void)setCurrentPhotoIndex:(NSUInteger)index;

#pragma mark - Toolbar

/// 向工具栏追加自定义按钮。
/// Appends custom buttons to the toolbar.
/// @param array 按钮数组 / Array of buttons.
/// @discussion 调用会确保视图已加载。
/// Calling this method ensures the view is loaded.
- (void)customToolBarItems:(NSArray<UIButton *> *)array;

/// 将工具栏停靠到左侧、底部或右侧，并清除自定义 frame。
/// Docks the toolbar to the left, bottom or right edge and clears any custom frame.
/// @param position 停靠位置 / Docking position.
- (void)customToolBarPosition:(MWToolBarPosition)position;

/// 使用浏览器视图坐标系下的指定 frame 摆放工具栏。
/// Places the toolbar using the given frame in the browser view's coordinate system.
/// @param frame 目标 frame / Target frame.
- (void)customToolBarFrame:(CGRect)frame;

@end

#pragma mark - Grid

/// 网格总览的展示接口。
/// Grid overview presentation interface.
@interface MWPhotoBrowser (MWGrid)

/// 以动画展示网格总览。
/// Shows the grid overview with animation.
/// @discussion 等同调用 showGrid:YES，前置条件不满足时调用被忽略。
/// Equivalent to calling showGrid:YES; ignored when prerequisites are not met.
- (void)showGridAnimated;

/// 展示网格总览。
/// Shows the grid overview.
/// @param animated 是否使用动画 / Whether to animate the transition.
/// @discussion 需要 enableGrid 为 YES、代理实现 photoBrowser:thumbPhotoAtIndex:，
/// 且当前未处于网格过渡中。视图未加载时会先行加载。
/// Requires enableGrid to be YES, the delegate to implement photoBrowser:thumbPhotoAtIndex:,
/// and no grid transition in progress. Loads the view first when needed.
- (void)showGrid:(BOOL)animated;

@end

#pragma mark - Data Refresh

/// 数据刷新接口。
/// Data refresh interface.
///
/// 声明在分类中，与内部按职责拆分的实现保持一致；调用方式与主类方法完全相同。
/// Declared in a category to mirror the internal responsibility split; call sites are identical to primary-class methods.
@interface MWPhotoBrowser (MWData)

/// 重新读取数据源并刷新界面。
/// Refetches data from the data source and refreshes the interface.
- (void)reloadData;

@end

#pragma mark - Paging

/// 前后翻页接口。
/// Photo paging interface.
@interface MWPhotoBrowser (MWNavigation)

/// 切换到下一张图片。
/// Advances to the next photo.
/// @param animated 是否使用动画 / Whether to animate the change.
- (void)showNextPhotoAnimated:(BOOL)animated;

/// 切换到上一张图片。
/// Returns to the previous photo.
/// @param animated 是否使用动画 / Whether to animate the change.
- (void)showPreviousPhotoAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
