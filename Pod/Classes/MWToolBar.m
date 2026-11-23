//
//  MWToolBar.m
//  MWPhotoBrowser
//
//  Created by 19m on 2026/11/12.
//

#import "MWToolBar.h"

@interface MWToolBar() {
    CGFloat _itemW;
}

@property(nonatomic,strong ) NSMutableArray<UIButton *> *btnArray;

- (void)addItem:(UIButton *)item;

@end

@implementation MWToolBar

- (instancetype)initWithFrame:(CGRect)frame{
    self = [super initWithFrame:frame];
    if (self){
        
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
        return;
    }
    _itemW = self.frame.size.width / array.count;
    for (UIButton *item in array) {
        if (![item isKindOfClass:[UIButton class]]) continue; // 防外部误传非按钮对象
        [self addItem:item];
    }
}

- (void)addItem:(UIButton *)item {
    CGFloat margin = _btnArray.count * (_itemW);
    item.frame = CGRectMake(margin, 0, _itemW, self.frame.size.height);
    [self addSubview:item];
    [_btnArray addObject:item];
}

@end
