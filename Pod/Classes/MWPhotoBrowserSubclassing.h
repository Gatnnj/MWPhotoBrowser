//
//  MWPhotoBrowserSubclassing.h
//  MWPhotoBrowser
//
//  子类定制契约：仅声明受支持的重写点，不暴露任何实例变量。
//
//  参考 Apple 的 UIGestureRecognizerSubclass.h 组织方式：
//  普通调用方无需导入本头文件；需要继承定制时才显式导入。
//

#import "MWPhotoBrowser.h"

@class MWZoomingScrollView;
@class MWPhotoInteractiveTransition;

NS_ASSUME_NONNULL_BEGIN

/// 受支持的子类重写点。
///
/// 重写规则：
///
/// 1. 除文档明确说明外，重写时必须调用 super，以保留内置行为。
///
/// 2. 不要导入 MWPhotoBrowserPrivate.h，也不要直接访问实例变量；内部状态不属于公开契约。
///
/// 3. 工厂方法必须返回全新实例，不要返回共享或已加入其他视图层级的对象。
///
/// 4. 所有钩子的默认实现等价于内置行为，不重写即保持原有功能不变。
@interface MWPhotoBrowser (MWSubclassing)

#pragma mark - Factory Hooks

/// 创建承载各图片页的横向分页滚动视图。
/// @return 未配置的新滚动视图。
/// @discussion 仅负责创建；属性配置在 configurePagingScrollView: 中完成。必须调用 super 或返回等价的 UIScrollView 实例。
- (UIScrollView *)makePagingScrollView;

/// 配置分页滚动视图的分页、指示器、背景与内容尺寸等属性。
/// @param pagingScrollView 待配置的滚动视图。
/// @discussion 重写时先调用 super，再追加自定义配置，避免破坏分页与布局。
- (void)configurePagingScrollView:(UIScrollView *)pagingScrollView;

/// 创建底部工具栏。
/// @return 未配置的新工具栏。
/// @discussion 可返回 MWToolBar 子类实例以定制外观；属性配置在 configureToolbar: 中完成。
- (MWToolBar *)makeToolbar;

/// 配置工具栏的裁剪与初始显隐。
/// @param toolbar 待配置的工具栏。
- (void)configureToolbar:(MWToolBar *)toolbar;

/// 创建拖拽关闭交互控制器，并完成与浏览器各层的回调接线。
/// @return 已接线的交互控制器；返回 nil 表示不启用拖拽关闭。
/// @discussion 仅在 enableCustomTransition 为 YES 时被调用。默认实现已处理背景透明度、
/// 分页开关、缩放态判定与飞回目标；如需替换，请自行保证这些回调语义。
- (nullable MWPhotoInteractiveTransition *)makeInteractiveTransition;

#pragma mark - Setup Hooks

/// 校验网格相关设置，按代理能力收敛 enableGrid 与 startOnGrid。
/// @discussion 在视图加载最开始调用。重写时请调用 super，否则网格开关可能处于无效组合。
- (void)validateGridSettings;

/// 配置浏览器根视图的背景与裁剪。
/// @discussion 自定义转场需要根视图非不透明才能透出底层内容，修改 opaque 前请确认该约束。
- (void)setUpRootView;

/// 装配自定义转场的拖拽关闭交互，并把手势安装到根视图。
/// @discussion 仅在 enableCustomTransition 为 YES 时执行实际装配。
- (void)setUpDismissInteraction;

/// 装配旧版上下轻扫关闭手势。
/// @discussion 仅当 enableSwipeToDismiss 为 YES 且 enableCustomTransition 为 NO 时生效，
/// 以免与跟手拖拽相互干扰。
- (void)setUpLegacyDismissGestureIfNeeded;

#pragma mark - Layout Template Hooks

/// 页面重新布局前的回调，此时内部布局标记已置位。
/// @discussion 默认空实现，无需调用 super。可在此准备自定义布局所需的状态。
- (void)willPerformLayout;

/// 页面重新布局后的回调，此时内部布局标记尚未清除。
/// @discussion 默认空实现，无需调用 super。可在此追加覆盖层或修正自定义视图几何。
- (void)didPerformLayout;

#pragma mark - Overridable Paging

/// 按当前可见范围创建、复用并摆放图片页。
/// @discussion 重写会影响复用池一致性，通常应改为重写 configurePage:forIndex:。
- (void)tilePages;

/// 配置指定索引的图片页，是定制单页内容与行为的首选重写点。
/// @param page 待配置的图片页。
/// @param index 图片索引。
/// @discussion 必须先调用 super 完成 frame、索引与图片绑定，再追加自定义配置。
- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index;

/// 从复用池取出一个可复用的图片页。
/// @return 可复用的页；池为空时返回 nil。
- (nullable MWZoomingScrollView *)dequeueRecycledPage;

/// 某个图片页开始显示时的回调。
/// @param index 开始显示的图片索引。
- (void)didStartViewingPageAtIndex:(NSUInteger)index;

#pragma mark - Overridable Geometry

/// 返回分页滚动视图的 frame。
- (CGRect)frameForPagingScrollView;

/// 返回指定索引图片页的 frame，页间距由本方法决定。
/// @param index 图片索引。
- (CGRect)frameForPageAtIndex:(NSUInteger)index;

/// 返回分页滚动视图的内容尺寸。
- (CGSize)contentSizeForPagingScrollView;

/// 返回指定索引图片页对应的内容偏移。
/// @param index 图片索引。
- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index;

#pragma mark - Overridable Data

/// 返回图片总数，优先取代理，其次取初始化时传入的固定数组。
- (NSUInteger)numberOfPhotos;

/// 返回指定索引的图片对象，必要时触发懒加载。
/// @param index 图片索引。
- (nullable id<MWPhoto>)photoAtIndex:(NSUInteger)index;

/// 返回图片对象当前已就绪的 UIImage。
/// @param photo 图片对象。
/// @return 已加载的图片；尚未就绪时返回 nil。
- (nullable UIImage *)imageForPhoto:(id<MWPhoto>)photo;

#pragma mark - Overridable Controls

/// 更新导航栏按钮与标题的可用状态。
- (void)updateNavigation;

/// 跳转到指定索引的图片页。
/// @param index 目标索引。
/// @param animated 是否使用动画。
- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated;

/// 设置导航栏与工具栏的显隐。
/// @param hidden 是否隐藏。
/// @param animated 是否使用动画。
/// @param permanent 是否保持该状态而不再自动隐藏。
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent;

/// 完成按钮的响应方法，负责关闭浏览器或在网格与单图之间切换。
/// @param sender 事件发送者。
- (void)doneButtonPressed:(nullable id)sender;

/// 解析当前页的转场起始缩略图，provider block 优先于代理方法。
/// @return 起始视图；未提供时返回 nil。
- (nullable UIView *)mw_startingView;

@end

NS_ASSUME_NONNULL_END
