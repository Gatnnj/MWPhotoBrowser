//
//  MWRootTabBarController.m
//  MWPhotoBrowser_Example
//

#import "MWRootTabBarController.h"
#import "MWWaterfallViewController.h"
#import "Menu.h"

@implementation MWRootTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];

    
    // Tab 1：两列瀑布流
    MWWaterfallViewController *waterfallVC = [[MWWaterfallViewController alloc] init];
    waterfallVC.tabBarItem = [[UITabBarItem alloc]
        initWithTitle:@"Waterfall"
                image:[UIImage systemImageNamed:@"square.grid.2x2"]
        selectedImage:[UIImage systemImageNamed:@"square.grid.2x2.fill"]];
    UINavigationController *waterfallNV = [[UINavigationController alloc] initWithRootViewController:waterfallVC];
    
    // Tab 2：沿用原有 Menu，直接复用 Main.storyboard 的初始 VC（Nav → Menu），Menu.m 不改
    Menu *menu = [[Menu alloc] initWithStyle:UITableViewStylePlain];
    
    menu.tabBarItem = [[UITabBarItem alloc]
        initWithTitle:@"Menu"
                image:[UIImage systemImageNamed:@"list.bullet"]
        selectedImage:[UIImage systemImageNamed:@"list.bullet"]];
    UINavigationController *menuNV = [[UINavigationController alloc] initWithRootViewController:menu];
    
    self.viewControllers = @[waterfallNV, menuNV];
    self.selectedIndex = 0;

    // iOS 15+ 默认透明 TabBar 会让列表内容透上来，这里固定为不透明背景
    UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
    [appearance configureWithDefaultBackground];
    self.tabBar.standardAppearance = appearance;
    self.tabBar.scrollEdgeAppearance = appearance;
}

@end
