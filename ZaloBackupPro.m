#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ZBManager : NSObject
+ (instancetype)shared;
- (void)startBackupFrom:(UIViewController *)vc;
- (void)startRestoreFrom:(UIViewController *)vc;
@end

@implementation ZBManager
+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (NSString *)backupRoot {
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"ZaloBackupPro_Data"];
}

- (void)startBackupFrom:(UIViewController *)vc {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro" message:@"Bắt đầu sao lưu Tin nhắn & Hình ảnh?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Sao Lưu Ngay" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self runBackupFrom:vc];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

- (void)runBackupFrom:(UIViewController *)vc {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *dest = [self backupRoot];
        [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *home = NSHomeDirectory();
        NSArray *searchPaths = @[
            [home stringByAppendingPathComponent:@"Library/Application Support"],
            [home stringByAppendingPathComponent:@"Documents"]
        ];
        
        // Các định dạng cần backup
        NSSet *exts = [NSSet setWithArray:@[@"db", @"sqlite", @"sqlite-wal", @"sqlite-shm", @"jpg", @"png", @"mp4", @"mov"]];
        __block NSInteger count = 0;
        
        for (NSString *path in searchPaths) {
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
            NSString *file;
            while ((file = [en nextObject])) {
                if ([exts containsObject:file.pathExtension.lowercaseString]) {
                    NSString *src = [path stringByAppendingPathComponent:file];
                    // Chuyển dấu / thành __ để lưu phẳng trong thư mục backup
                    NSString *safeName = [file stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
                    NSString *dst = [dest stringByAppendingPathComponent:safeName];
                    [fm removeItemAtPath:dst error:nil];
                    if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Thành công" message:[NSString stringWithFormat:@"Đã sao lưu %ld tệp tin.", (long)count] preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [vc presentViewController:done animated:YES completion:nil];
        });
    });
}

- (void)startRestoreFrom:(UIViewController *)vc {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *srcDir = [self backupRoot];
    NSArray *files = [fm contentsOfDirectoryAtPath:srcDir error:nil];
    
    if (files.count == 0) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Lỗi" message:@"Không tìm thấy dữ liệu để khôi phục." preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:err animated:YES completion:nil];
        return;
    }

    UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Khôi Phục" message:@"Dữ liệu hiện tại sẽ bị ghi đè. Bạn có chắc chắn?" preferredStyle:UIAlertControllerStyleAlert];
    [res addAction:[UIAlertAction actionWithTitle:@"Khôi Phục Ngay" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            for (NSString *f in files) {
                NSString *src = [srcDir stringByAppendingPathComponent:f];
                // Chuyển __ ngược lại thành / để tìm đường dẫn gốc
                NSString *relPath = [f stringByReplacingOccurrencesOfString:@"__" withString:@"/"];
                NSString *dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:relPath];
                
                [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                [fm removeItemAtPath:dst error:nil];
                [fm copyItemAtPath:src toPath:dst error:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Xong" message:@"Đã khôi phục dữ liệu. Vui lòng đóng hẳn Zalo và mở lại." preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [vc presentViewController:done animated:YES completion:nil];
            });
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
- (instancetype)init {
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 1000;
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        
        self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.btn.frame = CGRectMake(20, 150, 60, 60);
        self.btn.backgroundColor = [UIColor colorWithRed:0 green:0.5 blue:1 alpha:0.8];
        self.btn.layer.cornerRadius = 30;
        [self.btn setTitle:@"ZPRO" forState:UIControlStateNormal];
        self.btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self.btn addGestureRecognizer:pan];
        [self addSubview:self.btn];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    if (view == self.btn || self.rootViewController.presentedViewController) return view;
    return nil;
}

- (void)btnTapped {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro" message:@"Chọn chức năng" preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Backup (Sao lưu)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startBackupFrom:self.rootViewController];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Restore (Khôi phục)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startRestoreFrom:self.rootViewController];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        menu.popoverPresentationController.sourceView = self.btn;
    }
    [self.rootViewController presentViewController:menu animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self];
    self.btn.center = CGPointMake(self.btn.center.x + t.x, self.btn.center.y + t.y);
    [p setTranslation:CGPointZero inView:self];
}

- (void)update {
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (s.activationState == UISceneActivationStateForegroundActive) { self.windowScene = s; break; }
        }
    }
}
@end

static ZBWindow *win;
__attribute__((constructor)) static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        win = [[ZBWindow alloc] init];
        [win update];
        win.hidden = NO;
        [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) {
            [win update];
            [win makeKeyAndVisible];
            win.hidden = NO;
        }];
    });
}