//
//  MWToolBar.m
//  MWPhotoBrowser
//
//  Created by 19m on 2026/11/12.
//

#import "MWToolBar.h"

@interface MWToolBar() {
    CGFloat _itemW;
    NSUInteger _itemCount;
}

@property(nonatomic,strong ) NSMutableArray<UIButton *> *btnArray;

- (void)addItem:(UIButton *)item;

@end

@implementation MWToolBar

static const CGFloat MWToolBarItemHeight = 50.0;
static const CGFloat MWToolBarSideWidth = 40.0;

- (instancetype)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self){
        _position = MWToolBarPositionBottom;
    }
    return self;
}

- (void)addItems:(NSArray<UIButton *> *) array {
    for (UIView *subView in self.subviews) {
        [subView removeFromSuperview];
    }
    
    _btnArray = [NSMutableArray array];
    // 空数组/ nil 直接返回：避免除零得到 inf，导致后续 frame 计算异常
    if (array.count == 0) {
        _itemCount = 0;
        if (self.superview) {
            self.frame = [self frameForContainerBounds:self.superview.bounds safeAreaInsets:self.superview.safeAreaInsets];
        }
        return;
    }
    _itemCount = array.count;
    BOOL vertical = self.position != MWToolBarPositionBottom;
    if (self.superview) {
        self.frame = [self frameForContainerBounds:self.superview.bounds safeAreaInsets:self.superview.safeAreaInsets];
    }
    _itemW = vertical ? MWToolBarSideWidth : self.frame.size.width / array.count;
    for (UIButton *item in array) {
        if (![item isKindOfClass:[UIButton class]]) continue; // 防外部误传非按钮对象
        [self addItem:item];
    }
}

/// 逐个摆放并加入按钮
- (void)addItem:(UIButton *)item {
    CGRect frame;
    if (self.position == MWToolBarPositionBottom) {
        frame = CGRectMake(_btnArray.count * _itemW, 0, _itemW, self.frame.size.height);
    } else {
        frame = CGRectMake(0, _btnArray.count * MWToolBarItemHeight, MWToolBarSideWidth, MWToolBarItemHeight);
    }
    item.frame = frame;
    [self addSubview:item];
    [_btnArray addObject:item];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL vertical = self.position != MWToolBarPositionBottom;
    CGFloat itemWidth = vertical ? MWToolBarSideWidth : (self.btnArray.count ? CGRectGetWidth(self.bounds) / self.btnArray.count : 0);
    [self.btnArray enumerateObjectsUsingBlock:^(UIButton *item, NSUInteger index, BOOL *stop) {
        (void)stop;
        item.frame = vertical
            ? CGRectMake(0, index * MWToolBarItemHeight, MWToolBarSideWidth, MWToolBarItemHeight)
            : CGRectMake(index * itemWidth, 0, itemWidth, CGRectGetHeight(self.bounds));
    }];
}

- (CGRect)frameForContainerBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    if (self.customFrame) return self.customFrame.CGRectValue;
    CGFloat bottom = CGRectGetHeight(bounds) - safeAreaInsets.bottom;
    if (self.position == MWToolBarPositionLeft) {
        return CGRectMake(CGRectGetMinX(bounds), bottom - _itemCount * MWToolBarItemHeight,
                          MWToolBarSideWidth, _itemCount * MWToolBarItemHeight);
    }
    if (self.position == MWToolBarPositionRight) {
        return CGRectMake(CGRectGetMaxX(bounds) - MWToolBarSideWidth, bottom - _itemCount * MWToolBarItemHeight,
                          MWToolBarSideWidth, _itemCount * MWToolBarItemHeight);
    }
    return CGRectMake(CGRectGetMinX(bounds), bottom - MWToolBarItemHeight,
                      CGRectGetWidth(bounds), MWToolBarItemHeight);
}

@end
