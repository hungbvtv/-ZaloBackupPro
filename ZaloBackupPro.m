#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// --- Giao diện Quản lý ---
@interface ZBManager : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)startBackup;
- (void)startRestore;
- (UIViewController *)getTopVC;
@end

@implementation ZBManager
+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (UIViewController *)getTopVC {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) { keyWindow = window; break; }
            }
        }
    }
    if (!keyWindow) keyWindow = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

- (void)startBackup {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro" message:@"Bạn muốn lưu bản backup vào đâu?" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu vào App Documents" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self runBackupToPath:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [[self getTopVC] presentViewController:alert animated:YES completion:nil];
}

- (void)runBackupToPath:(NSString *)customPath {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *backupDir = [docPath stringByAppendingPathComponent:@"ZaloBackupPro_Data"];
        
        [fm createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *libPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
        NSInteger count = 0;
        
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:libPath];
        NSString *file;
        while ((file = [enumerator nextObject])) {
            if ([file.pathExtension isEqualToString:@"db"] || [file.pathExtension isEqualToString:@"sqlite"]) {
                NSString *src = [libPath stringByAppendingPathComponent:file];
                NSString *dst = [backupDir stringByAppendingPathComponent:[file stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
                [fm removeItemAtPath:dst error:nil];
                if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Thành công" message:[NSString stringWithFormat:@"Đã backup %ld tệp tin database.", (long)count] preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[self getTopVC] presentViewController:done animated:YES completion:nil];
        });
    });
}

- (void)startRestore {
    // Logic khôi phục tương tự
}
@end

// --- Cửa sổ Nút bấm Nổi ---
@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *floatingBtn;
@end

@implementation ZBWindow
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 150, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.windowLevel = UIWindowLevelAlert + 999; // Luôn trên cùng
        
        // Hỗ trợ iOS 13 đến iOS 26+
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    self.windowScene = (UIWindowScene *)scene; break;
                }
            }
        }

        self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatingBtn.frame = self.bounds;
        self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.8];
        self.floatingBtn.layer.cornerRadius = 30;
        [self.floatingBtn setTitle:@"ZBackup" forState:UIControlStateNormal];
        self.floatingBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        [self.floatingBtn addTarget:self action:@selector(btnClicked) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.floatingBtn addGestureRecognizer:pan];
        
        [self addSubview:self.floatingBtn];
        self.hidden = NO;
    }
    return self;
}

- (void)btnClicked {
    [[ZBManager shared] startBackup];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:self];
}
@end

static ZBWindow *globalWin;
__attribute__((constructor)) static void load() {
    // Chờ 5 giây để Zalo load xong Scene trên iOS đời cao
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        globalWin = [[ZBWindow alloc] init];
    });
}