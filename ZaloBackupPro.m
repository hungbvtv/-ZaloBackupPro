#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ============================================================
// ZaloBackup Pro - Fix iOS 13+ windowScene
// ============================================================

@interface ZBRootVC : UIViewController @end
@implementation ZBRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end

@interface ZBManager : NSObject
+ (instancetype)shared;
- (void)startBackupFrom:(UIViewController *)vc;
- (void)startRestoreFrom:(UIViewController *)vc;
@end

@implementation ZBManager { BOOL _isProcessing; }

+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (NSString *)backupRoot {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZaloBackupPro_Data"];
}

- (void)startBackupFrom:(UIViewController *)vc {
    if (_isProcessing) return;
    _isProcessing = YES;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *dest = [self backupRoot];
            [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
            NSArray *sources = @[
                @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"], @"prefix": @"L|"},
                @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"], @"prefix": @"D|"},
                @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"], @"prefix": @"C|"}
            ];
            NSSet *exts = [NSSet setWithArray:@[@"db",@"sqlite",@"sqlite3",@"sqlite-wal",@"sqlite-shm",@"db-wal",@"db-shm",@"jpg",@"jpeg",@"png",@"mp4",@"mov",@"plist",@"m4a",@"aac",@"mp3"]];
            NSInteger count = 0;
            for (NSDictionary *source in sources) {
                NSString *root = source[@"path"];
                if (![fm fileExistsAtPath:root]) continue;
                NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
                NSString *file;
                while ((file = [en nextObject])) {
                    if ([file containsString:@"ZaloBackupPro_Data"]) continue;
                    if ([exts containsObject:file.pathExtension.lowercaseString]) {
                        NSString *src = [root stringByAppendingPathComponent:file];
                        NSString *safe = [file stringByReplacingOccurrencesOfString:@"/" withString:@"|"];
                        NSString *dst = [dest stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%@", source[@"prefix"], safe]];
                        [fm removeItemAtPath:dst error:nil];
                        if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
                    }
                }
            }
            NSString *msg = [NSString stringWithFormat:@"Da sao luu %ld tep vao Documents/ZaloBackupPro_Data", (long)count];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_isProcessing = NO;
                UIViewController *top = vc;
                while (top.presentedViewController) top = top.presentedViewController;
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Backup Xong" message:msg preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [top presentViewController:done animated:YES completion:nil];
            });
        }
    });
}

- (void)startRestoreFrom:(UIViewController *)vc {
    if (_isProcessing) return;
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self backupRoot] error:nil];
    if (!files.count) {
        UIViewController *top = vc;
        while (top.presentedViewController) top = top.presentedViewController;
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Loi" message:@"Chua co ban backup nao." preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:err animated:YES completion:nil];
        return;
    }
    UIViewController *top = vc;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Khoi Phuc" message:@"Du lieu se bi ghi de. App se tu dong sau khi xong." preferredStyle:UIAlertControllerStyleAlert];
    [res addAction:[UIAlertAction actionWithTitle:@"Khoi Phuc" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        self->_isProcessing = YES;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSFileManager *fm = NSFileManager.defaultManager;
            for (NSString *f in files) {
                if (f.length < 3) continue;
                NSString *src = [[self backupRoot] stringByAppendingPathComponent:f];
                NSString *rel = [[f substringFromIndex:2] stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                NSString *dst = nil;
                if ([f hasPrefix:@"L|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:rel];
                else if ([f hasPrefix:@"D|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:rel];
                else if ([f hasPrefix:@"C|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:rel];
                if (dst) {
                    [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                    [fm removeItemAtPath:dst error:nil];
                    [fm copyItemAtPath:src toPath:dst error:nil];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
        });
    }]];
    [res addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:res animated:YES completion:nil];
}
@end

// ============================================================
// ZBWindow - Float button, iOS 13+ windowScene
// ============================================================
@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, strong) ZBRootVC *rootVC;
@end

@implementation ZBWindow

- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self = [super initWithWindowScene:scene];
    if (!self) return nil;

    self.frame = scene.coordinateSpace.bounds;
    self.windowLevel = UIWindowLevelAlert + 1000;
    self.backgroundColor = UIColor.clearColor;

    // Root VC quan trong - phai set truoc
    self.rootVC = [ZBRootVC new];
    self.rootViewController = self.rootVC;
    [self makeKeyAndVisible];

    // Button
    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame = CGRectMake(20, 250, 65, 65);
    self.btn.backgroundColor = [UIColor colorWithRed:0 green:0.47 blue:1 alpha:0.92];
    self.btn.layer.cornerRadius = 32.5;
    self.btn.layer.borderWidth = 2;
    self.btn.layer.borderColor = UIColor.whiteColor.CGColor;
    self.btn.layer.shadowColor = UIColor.blackColor.CGColor;
    self.btn.layer.shadowOpacity = 0.3;
    self.btn.layer.shadowOffset = CGSizeMake(0, 3);
    [self.btn setTitle:@"ZPRO" forState:UIControlStateNormal];
    self.btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.btn addGestureRecognizer:pan];

    [self.rootVC.view addSubview:self.btn];
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Chi nhan touch tren nut hoac khi co alert dang hien
    CGPoint btnPoint = [self.rootVC.view convertPoint:point fromView:self];
    if (CGRectContainsPoint(self.btn.frame, btnPoint)) return self.btn;
    if (self.rootVC.presentedViewController) return [super hitTest:point withEvent:event];
    return nil;
}

- (void)btnTapped {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startBackupFrom:self.rootVC];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startRestoreFrom:self.rootVC];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Dong" style:UIAlertActionStyleCancel handler:nil]];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        menu.popoverPresentationController.sourceView = self.btn;
        menu.popoverPresentationController.sourceRect = self.btn.bounds;
    }
    [self.rootVC presentViewController:menu animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.rootVC.view];
    CGRect f = self.btn.frame;
    CGRect bounds = self.rootVC.view.bounds;
    f.origin.x = MAX(8, MIN(f.origin.x + t.x, bounds.size.width - f.size.width - 8));
    f.origin.y = MAX(50, MIN(f.origin.y + t.y, bounds.size.height - f.size.height - 50));
    self.btn.frame = f;
    [p setTranslation:CGPointZero inView:self.rootVC.view];
}
@end

// ============================================================
// Constructor
// ============================================================
static ZBWindow *zWin;

static void launchZaloPro() {
    if (zWin) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *activeScene = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
        if (activeScene) {
            zWin = [[ZBWindow alloc] initWithWindowScene:activeScene];
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ launchZaloPro(); });
        }
    });
}

__attribute__((constructor))
static void zbInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ launchZaloPro(); });
}
