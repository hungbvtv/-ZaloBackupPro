#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ZBManager : NSObject
+ (instancetype)shared;
- (void)startBackupFrom:(UIViewController *)vc;
- (void)startRestoreFrom:(UIViewController *)vc;
@end

@implementation ZBManager {
    BOOL _isProcessing;
}

+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (NSString *)backupRoot {
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"ZaloBackupPro_Data"];
}

- (void)runBackupFrom:(UIViewController *)vc {
    if (_isProcessing) return;
    _isProcessing = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *dest = [self backupRoot];
            [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
            
            NSString *home = NSHomeDirectory();
            NSArray *sources = @[
                @{@"path": [home stringByAppendingPathComponent:@"Library/Application Support"], @"prefix": @"L|"},
                @{@"path": [home stringByAppendingPathComponent:@"Documents"], @"prefix": @"D|"}
            ];
            
            NSSet *exts = [NSSet setWithArray:@[@"db", @"sqlite", @"sqlite-wal", @"sqlite-shm", @"jpg", @"png", @"mp4", @"plist", @"webp"]];
            __block NSInteger count = 0;
            
            for (NSDictionary *source in sources) {
                NSString *rootPath = source[@"path"];
                NSString *prefix = source[@"prefix"];
                NSDirectoryEnumerator *en = [fm enumeratorAtPath:rootPath];
                NSString *file;
                while ((file = [en nextObject])) {
                    @autoreleasepool {
                        // CHỐNG SAO LƯU LẶP VÔ TẬN
                        if ([file containsString:@"ZaloBackupPro_Data"]) continue;

                        if ([exts containsObject:file.pathExtension.lowercaseString]) {
                            NSString *src = [rootPath stringByAppendingPathComponent:file];
                            NSString *safeName = [NSString stringWithFormat:@"%@%@", prefix, [file stringByReplacingOccurrencesOfString:@"/" withString:@"|"]];
                            NSString *dst = [dest stringByAppendingPathComponent:safeName];
                            
                            [fm removeItemAtPath:dst error:nil];
                            if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
                        }
                    }
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_isProcessing = NO;
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro" message:[NSString stringWithFormat:@"Đã sao lưu %ld tệp thành công!\nBạn có thể lấy file trong ứng dụng Tệp (Files).", (long)count] preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [vc presentViewController:done animated:YES completion:nil];
            });
        }
    });
}

- (void)startRestoreFrom:(UIViewController *)vc {
    if (_isProcessing) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *srcDir = [self backupRoot];
    NSArray *files = [fm contentsOfDirectoryAtPath:srcDir error:nil];
    
    if (files.count == 0) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Lỗi" message:@"Không thấy bản sao lưu nào." preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:err animated:YES completion:nil];
        return;
    }

    UIAlertController *res = [UIAlertController alertControllerWithTitle:@"Khôi Phục" message:@"Dữ liệu hiện tại sẽ bị ghi đè hoàn toàn. Zalo sẽ tự đóng sau khi xong." preferredStyle:UIAlertControllerStyleAlert];
    [res addAction:[UIAlertAction actionWithTitle:@"Khôi Phục Ngay" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        self->_isProcessing = YES;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                for (NSString *f in files) {
                    NSString *src = [srcDir stringByAppendingPathComponent:f];
                    NSString *dst = nil;
                    if ([f hasPrefix:@"L|"]) {
                        NSString *rel = [[f substringFromIndex:2] stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                        dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:rel];
                    } else if ([f hasPrefix:@"D|"]) {
                        NSString *rel = [[f substringFromIndex:2] stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                        dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:rel];
                    }
                    if (dst) {
                        [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                        [fm removeItemAtPath:dst error:nil];
                        [fm copyItemAtPath:src toPath:dst error:nil];
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
            }
        });
    }]];
    [res addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:res animated:YES completion:nil];
}

- (void)startBackupFrom:(UIViewController *)vc { [self runBackupFrom:vc]; }
@end

@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *btn;
@end

@implementation ZBWindow
- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self = [super initWithWindowScene:scene];
    if (self) {
        // WINDOW CHỈ NHỎ BẰNG CÁI NÚT ĐỂ KHÔNG CHẶN CẢM ỨNG
        self.frame = CGRectMake(20, 250, 60, 60); 
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        
        self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.btn.frame = self.bounds;
        self.btn.backgroundColor = [UIColor colorWithRed:0 green:0.47 blue:1 alpha:0.9];
        self.btn.layer.cornerRadius = 30;
        self.btn.layer.shadowOpacity = 0.3;
        [self.btn setTitle:@"ZPRO" forState:UIControlStateNormal];
        self.btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
        [self addSubview:self.btn];
    }
    return self;
}

// XUYÊN QUA WINDOW NẾU KHÔNG BẤM VÀO NÚT
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    if (view == self.btn || self.rootViewController.presentedViewController) return view;
    return nil;
}

- (void)btnTapped {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Sao lưu (Backup)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startBackupFrom:self.rootViewController];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Khôi phục (Restore)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startRestoreFrom:self.rootViewController];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:menu animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [p setTranslation:CGPointZero inView:self];
}
@end

static ZBWindow *zWin;
__attribute__((constructor)) static void init() {
    // CHỐNG NHÁY: Chỉ khởi tạo khi App đã sẵn sàng
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if (!zWin) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    zWin = [[ZBWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                    zWin.hidden = NO;
                    break;
                }
            }
        }
    }];
}