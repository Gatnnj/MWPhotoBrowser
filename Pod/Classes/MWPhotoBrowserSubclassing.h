//
//  MWPhotoBrowserSubclassing.h
//  MWPhotoBrowser
//
//  子类定制契约：仅声明受支持的重写点，不暴露任何实例变量。
//  Subclassing contract: declares supported override points only, without exposing instance variables.
//
//  参考 Apple 的 UIGestureRecognizerSubclass.h 组织方式：
//  普通调用方无需导入本头文件；需要继承定制时才显式导入。
//  Follows the organization of Apple's UIGestureRecognizerSubclass.h:
//  ordinary callers never import this header; import it only when subclassing.
//

#import "MWPhotoBrowser.h"

@class MWZoomingScrollView;
@class MWPhotoInteractiveTransition;

NS_ASSUME_NONNULL_BEGIN

/// 受支持的子类重写点。
/// Supported subclass override points.
///
/// 重写规则 / Overriding rules:
///
/// 1. 除文档明确说明外，重写时必须调用 super，以保留内置行为。
/// 1. Unless stated otherwise, call super when overriding to preserve built-in behavior.
///
/// 2. 不要导入 MWPhotoBrowserPrivate.h，也不要直接访问实例变量；内部状态不属于公开契约。
/// 2. Do not import MWPhotoBrowserPrivate.h or access instance variables directly; internal state is not public contract.
///
/// 3. 工厂方法必须返回全新实例，不要返回共享或已加入其他视图层级的对象。
/// 3. Factory methods must return a fresh instance, never a shared object or one already in another view hierarchy.
///
/// 4. 所有钩子的默认实现等价于内置行为，不重写即保持原有功能不变。
/// 4. Every hook's default implementation matches the built-in behavior; not overriding keeps existing functionality intact.
@interface MWPhotoBrowser (MWSubclassing)

#pragma mark - Factory Hooks

/// 创建承载各图片页的横向分页滚动视图。
/// Creates the horizontally paging scroll view that hosts the photo pages.
/// @return 未配置的新滚动视图 / A newly created, unconfigured scroll view.
/// @discussion 仅负责创建；属性配置在 configurePagingScrollView: 中完成。必须调用 super 或返回等价的 UIScrollView 实例。
/// Responsible for creation only; configuration happens in configurePagingScrollView:.
/// Call super or return an equivalent UIScrollView instance.
- (UIScrollView *)makePagingScrollView;

/// 配置分页滚动视图的分页、指示器、背景与内容尺寸等属性。
/// Configures paging, indicators, background, content size and related properties of the paging scroll view.
/// @param pagingScrollView 待配置的滚动视图 / The scroll view to configure.
/// @discussion 重写时先调用 super，再追加自定义配置，避免破坏分页与布局。
/// Call super first, then apply custom configuration, so paging and layout stay intact.
- (void)configurePagingScrollView:(UIScrollView *)pagingScrollView;

/// 创建底部工具栏。
/// Creates the toolbar.
/// @return 未配置的新工具栏 / A newly created, unconfigured toolbar.
/// @discussion 可返回 MWToolBar 子类实例以定制外观；属性配置在 configureToolbar: 中完成。
/// Return a MWToolBar subclass to customize appearance; configuration happens in configureToolbar:.
- (MWToolBar *)makeToolbar;

/// 配置工具栏的裁剪与初始显隐。
/// Configures the toolbar's clipping and initial visibility.
/// @param toolbar 待配置的工具栏 / The toolbar to configure.
- (void)configureToolbar:(MWToolBar *)toolbar;

/// 创建拖拽关闭交互控制器，并完成与浏览器各层的回调接线。
/// Creates the drag-to-dismiss interaction controller and wires its callbacks to the browser layers.
/// @return 已接线的交互控制器；返回 nil 表示不启用拖拽关闭 / A wired controller, or nil to disable drag-to-dismiss.
/// @discussion 仅在 enableCustomTransition 为 YES 时被调用。默认实现已处理背景透明度、
/// 分页开关、缩放态判定与飞回目标；如需替换，请自行保证这些回调语义。
/// Called only when enableCustomTransition is YES. The default implementation handles background alpha,
/// paging toggling, zoom-state checks and the fly-back target. Preserve these callback semantics if you replace it.
- (nullable MWPhotoInteractiveTransition *)makeInteractiveTransition;

#pragma mark - Setup Hooks

/// 校验网格相关设置，按代理能力收敛 enableGrid 与 startOnGrid。
/// Validates grid settings, reconciling enableGrid and startOnGrid with the delegate's capabilities.
/// @discussion 在视图加载最开始调用。重写时请调用 super，否则网格开关可能处于无效组合。
/// Called at the very start of view loading. Call super when overriding, otherwise the grid flags may end up inconsistent.
- (void)validateGridSettings;

/// 配置浏览器根视图的背景与裁剪。
/// Configures the browser root view's background and clipping.
/// @discussion 自定义转场需要根视图非不透明才能透出底层内容，修改 opaque 前请确认该约束。
/// The custom transition requires a non-opaque root view to reveal underlying content; keep that constraint in mind.
- (void)setUpRootView;

/// 装配自定义转场的拖拽关闭交互，并把手势安装到根视图。
/// Sets up the drag-to-dismiss interaction for the custom transition and installs its gesture on the root view.
/// @discussion 仅在 enableCustomTransition 为 YES 时执行实际装配。
/// Performs actual setup only when enableCustomTransition is YES.
- (void)setUpDismissInteraction;

/// 装配旧版上下轻扫关闭手势。
/// Sets up the legacy swipe-to-dismiss gesture.
/// @discussion 仅当 enableSwipeToDismiss 为 YES 且 enableCustomTransition 为 NO 时生效，
/// 以免与跟手拖拽相互干扰。
/// Effective only when enableSwipeToDismiss is YES and enableCustomTransition is NO,
/// so it never interferes with the finger-tracking drag.
- (void)setUpLegacyDismissGestureIfNeeded;

#pragma mark - Layout Template Hooks

/// 页面重新布局前的回调，此时内部布局标记已置位。
/// Called before pages are laid out again; the internal layout flag is already set.
/// @discussion 默认空实现，无需调用 super。可在此准备自定义布局所需的状态。
/// Empty by default; calling super is not required. Prepare state needed by custom layout here.
- (void)willPerformLayout;

/// 页面重新布局后的回调，此时内部布局标记尚未清除。
/// Called after pages are laid out again; the internal layout flag is not yet cleared.
/// @discussion 默认空实现，无需调用 super。可在此追加覆盖层或修正自定义视图几何。
/// Empty by default; calling super is not required. Add overlays or adjust custom view geometry here.
- (void)didPerformLayout;

#pragma mark - Overridable Paging

/// 按当前可见范围创建、复用并摆放图片页。
/// Creates, recycles and positions photo pages for the current visible range.
/// @discussion 重写会影响复用池一致性，通常应改为重写 configurePage:forIndex:。
/// Overriding affects reuse-pool consistency; prefer overriding configurePage:forIndex: instead.
- (void)tilePages;

/// 配置指定索引的图片页，是定制单页内容与行为的首选重写点。
/// Configures the photo page at the given index. The preferred override point for per-page customization.
/// @param page 待配置的图片页 / The page to configure.
/// @param index 图片索引 / Photo index.
/// @discussion 必须先调用 super 完成 frame、索引与图片绑定，再追加自定义配置。
/// Call super first to bind frame, index and photo, then apply custom configuration.
- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index;

/// 从复用池取出一个可复用的图片页。
/// Dequeues a reusable photo page from the reuse pool.
/// @return 可复用的页；池为空时返回 nil / A reusable page, or nil when the pool is empty.
- (nullable MWZoomingScrollView *)dequeueRecycledPage;

/// 某个图片页开始显示时的回调。
/// Called when a photo page becomes visible.
/// @param index 开始显示的图片索引 / Index of the photo that became visible.
- (void)didStartViewingPageAtIndex:(NSUInteger)index;

#pragma mark - Overridable Geometry

/// 返回分页滚动视图的 frame。
/// Returns the frame of the paging scroll view.
- (CGRect)frameForPagingScrollView;

/// 返回指定索引图片页的 frame，页间距由本方法决定。
/// Returns the frame of the photo page at the given index; this method defines inter-page spacing.
/// @param index 图片索引 / Photo index.
- (CGRect)frameForPageAtIndex:(NSUInteger)index;

/// 返回分页滚动视图的内容尺寸。
/// Returns the content size of the paging scroll view.
- (CGSize)contentSizeForPagingScrollView;

/// 返回指定索引图片页对应的内容偏移。
/// Returns the content offset for the photo page at the given index.
/// @param index 图片索引 / Photo index.
- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index;

#pragma mark - Overridable Data

/// 返回图片总数，优先取代理，其次取初始化时传入的固定数组。
/// Returns the photo count, preferring the delegate and falling back to the fixed array passed at initialization.
- (NSUInteger)numberOfPhotos;

/// 返回指定索引的图片对象，必要时触发懒加载。
/// Returns the photo object at the given index, triggering lazy loading when needed.
/// @param index 图片索引 / Photo index.
- (nullable id<MWPhoto>)photoAtIndex:(NSUInteger)index;

/// 返回图片对象当前已就绪的 UIImage。
/// Returns the currently available UIImage of a photo object.
/// @param photo 图片对象 / The photo object.
/// @return 已加载的图片；尚未就绪时返回 nil / The loaded image, or nil when not ready yet.
- (nullable UIImage *)imageForPhoto:(id<MWPhoto>)photo;

#pragma mark - Overridable Controls

/// 更新导航栏按钮与标题的可用状态。
/// Updates the enabled state and titles of the navigation bar items.
- (void)updateNavigation;

/// 跳转到指定索引的图片页。
/// Jumps to the photo page at the given index.
/// @param index 目标索引 / Target index.
/// @param animated 是否使用动画 / Whether to animate the jump.
- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated;

/// 设置导航栏与工具栏的显隐。
/// Sets the visibility of the navigation bar and toolbar.
/// @param hidden 是否隐藏 / Whether to hide.
/// @param animated 是否使用动画 / Whether to animate.
/// @param permanent 是否保持该状态而不再自动隐藏 / Whether to keep the state instead of auto-hiding again.
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent;

/// 完成按钮的响应方法，负责关闭浏览器或在网格与单图之间切换。
/// Action for the Done button; dismisses the browser or switches between grid and single-photo mode.
/// @param sender 事件发送者 / The event sender.
- (void)doneButtonPressed:(nullable id)sender;

/// 解析当前页的转场起始缩略图，provider block 优先于代理方法。
/// Resolves the transition source thumbnail for the current page; the provider block takes precedence over the delegate.
/// @return 起始视图；未提供时返回 nil / The source view, or nil when unavailable.
- (nullable UIView *)mw_startingView;

@end

NS_ASSUME_NONNULL_END
