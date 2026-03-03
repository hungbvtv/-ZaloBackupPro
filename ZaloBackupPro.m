#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"ZaloBackupPro_Data"];
}

- (NSString *)appGroupPath {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *bundle = [[lib stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *containerRoot = [bundle stringByDeletingLastPathComponent];
    return [[containerRoot stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Shared/AppGroup"];
}

- (void)runBackupFrom:(UIViewController *)vc {
    if (_isProcessing) return; _isProcessing = YES;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *dest = [self backupRoot];
            [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
            NSArray *sources = @[
                @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"], @"prefix": @"L|"},
                @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"], @"prefix": @"D|"},
                @{@"path": [self appGroupPath], @"prefix": @"G|"}
            ];
            NSSet *exts = [NSSet setWithArray:@[@"db", @"sqlite", @"sqlite-wal", @"sqlite-shm", @"jpg", @"png", @"mp4", @"plist"]];
            __block NSInteger count = 0;
            for (NSDictionary *source in sources) {
                NSString *root = source[@"path"];
                if (![fm fileExistsAtPath:root]) continue;
                NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
                NSString *file;
                while ((file = [en nextObject])) {
                    if ([file containsString:@"ZaloBackupPro_Data"]) continue;
                    if ([exts containsObject:file.pathExtension.lowercaseString]) {
                        NSString *src = [root stringByAppendingPathComponent:file];
                        NSString *dst = [dest stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%@", source[@"prefix"], [file stringByReplacingOccurrencesOfString:@"/" withString:@"|"]]];
                        [fm removeItemAtPath:dst error:nil];
                        if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_isProcessing = NO;
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Xong" message:[NSString stringWithFormat:@"Đã sao lưu %ld tệp.", (long)count] preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
                [vc presentViewController:done animated:YES completion:nil];
            });
        }
    });
}

- (void)startRestoreFrom:(UIViewController *)vc {
    if (_isProcessing) return;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self backupRoot] error:nil];
    if (files.count == 0) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Lỗi" message:@"Không có dữ liệu." preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:err animated:YES completion:nil]; return;
    }
    UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Khôi Phục" message:@"Dữ liệu sẽ bị ghi đè. App sẽ tự đóng." preferredStyle:UIAlertControllerStyleAlert];
    [res addAction:[UIAlertAction actionWithTitle:@"Khôi Phục" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        self->_isProcessing = YES;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            for (NSString *f in files) {
                if (f.length < 3) continue;
                NSString *src = [[self backupRoot] stringByAppendingPathComponent:f];
                NSString *dst = nil;
                NSString *rel = [[f substringFromIndex:2] stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                if ([f hasPrefix:@"L|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:rel];
                else if ([f hasPrefix:@"D|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:rel];
                else if ([f hasPrefix:@"G|"]) dst = [[self appGroupPath] stringByAppendingPathComponent:rel];
                if (dst) {
                    [[NSFileManager defaultManager] createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                    [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
                    [[NSFileManager defaultManager] copyItemAtPath:src toPath:dst error:nil];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
        });
    }]];
    [res addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:res animated:YES completion:nil];
}
@end

@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *btn;
@end

@implementation ZBWindow
- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self = [super initWithWindowScene:scene];
    if (self) {
        self.frame = scene.coordinateSpace.bounds;
        self.windowLevel = UIWindowLevelAlert + 1000;
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.btn.frame = CGRectMake(20, 250, 65, 65);
        self.btn.backgroundColor = [UIColor colorWithRed:0 green:0.47 blue:1 alpha:0.9];
        self.btn.layer.cornerRadius = 32.5;
        self.btn.layer.borderWidth = 2;
        self.btn.layer.borderColor = [UIColor whiteColor].CGColor;
        [self.btn setTitle:@"ZPRO" forState:UIControlStateNormal];
        self.btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self.btn addGestureRecognizer:pan];
        [self addSubview:self.btn];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.btn || self.rootViewController.presentedViewController) return hitView;
    return nil;
}

- (void)btnTapped {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startBackupFrom:self.rootViewController];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startRestoreFrom:self.rootViewController];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) menu.popoverPresentationController.sourceView = self.btn;
    [self.rootViewController presentViewController:menu animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self];
    self.btn.center = CGPointMake(self.btn.center.x + t.x, self.btn.center.y + t.y);
    [p setTranslation:CGPointZero inView:self];
}
@end

static ZBWindow *zWin;
static void launchZaloPro() {
    if (zWin) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *activeScene = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                activeScene = (UIWindowScene *)scene; break;
            }
        }
        if (activeScene) {
            zWin = [[ZBWindow alloc] initWithWindowScene:activeScene];
            zWin.hidden = NO;
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ launchZaloPro(); });
        }
    });
}

__attribute__((constructor)) static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ launchZaloPro(); });
}