#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface UIRootVC : UIViewController @end
@implementation UIRootVC
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.clearColor; }
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface ZBManager : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)startBackupFlow;
- (void)restore;
@end

@implementation ZBManager

+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (NSString *)defaultRoot {
    NSString *path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"ZaloBackupPro"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

- (NSArray *)allBackups {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *r = NSMutableArray.new;
    for (NSString *n in [fm contentsOfDirectoryAtPath:[self defaultRoot] error:nil]) {
        BOOL d = NO;
        if ([fm fileExistsAtPath:[[self defaultRoot] stringByAppendingPathComponent:n] isDirectory:&d] && d) {
            [r addObject:n];
        }
    }
    return [r sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return [b compare:a]; }];
}

- (UIWindowScene *)activeScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (s.activationState == UISceneActivationStateForegroundActive && [s isKindOfClass:[UIWindowScene class]])
                return (UIWindowScene *)s;
        }
    }
    return nil;
}

- (UIViewController *)topVC {
    UIViewController *v = nil;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self activeScene];
        for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { v = w.rootViewController; break; } }
    } else {
        v = [UIApplication sharedApplication].keyWindow.rootViewController;
    }
    while (v.presentedViewController) v = v.presentedViewController;
    return v;
}

- (void)startBackupFlow {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Đặt Tên Backup" message:@"Nhập tên thư mục lưu backup:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        NSDateFormatter *df = NSDateFormatter.new; df.dateFormat = @"yyyyMMdd_HHmmss";
        tf.text = [df stringFromDate:NSDate.date];
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Lưu vào Documents" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = ac.textFields.firstObject.text ?: @"backup";
        [self runBackupToPath:[[self defaultRoot] stringByAppendingPathComponent:name]];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Chọn Thư Mục (Files)..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = ac.textFields.firstObject.text ?: @"backup";
        [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"zbPendingName"];
        [self openFilePicker];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC] presentViewController:ac animated:YES completion:nil];
}

- (void)openFilePicker {
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"] inMode:UIDocumentPickerModeOpen];
    }
    picker.delegate = self;
    [[self topVC] presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject; if (!u) return;
    NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:@"zbPendingName"] ?: @"backup";
    [u startAccessingSecurityScopedResource];
    [self runBackupToPath:[u.path stringByAppendingPathComponent:name]];
    [u stopAccessingSecurityScopedResource];
}

- (void)runBackupToPath:(NSString *)dest {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *home = NSHomeDirectory();
        NSString *dbD = [dest stringByAppendingPathComponent:@"DB"];
        NSString *mdD = [dest stringByAppendingPathComponent:@"Media"];
        [fm createDirectoryAtPath:dbD withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:mdD withIntermediateDirectories:YES attributes:nil error:nil];

        NSArray *search = @[
            [home stringByAppendingPathComponent:@"Library/Application Support"],
            [home stringByAppendingPathComponent:@"Documents"]
        ];
        NSSet *dbExt = [NSSet setWithArray:@[@"db", @"sqlite", @"sqlite3", @"db-wal", @"db-shm"]];
        NSSet *mdExt = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"gif", @"mp4", @"mov", @"aac", @"mp3"]];
        
        __block NSInteger dbCount = 0, mdCount = 0;
        for (NSString *rootPath in search) {
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:rootPath];
            NSString *file;
            while ((file = [en nextObject])) {
                if ([file containsString:@"ZaloBackupPro"]) continue;
                NSString *ext = file.pathExtension.lowercaseString;
                NSString *src = [rootPath stringByAppendingPathComponent:file];
                // Thay dấu / bằng __ để làm tên file phẳng (flat)
                NSString *safeName = [file stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
                
                if ([dbExt containsObject:ext]) {
                    [fm copyItemAtPath:src toPath:[dbD stringByAppendingPathComponent:safeName] error:nil];
                    dbCount++;
                } else if ([mdExt containsObject:ext]) {
                    [fm copyItemAtPath:src toPath:[mdD stringByAppendingPathComponent:safeName] error:nil];
                    mdCount++;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self alert:@"Backup Hoàn Tất" msg:[NSString stringWithFormat:@"Đã lưu tại: %@", dest]];
        });
    });
}

- (void)restore {
    NSArray *list = [self allBackups];
    if (!list.count) { [self alert:@"Thông Báo" msg:@"Chưa có bản backup nào."]; return; }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Chọn Bản Backup" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *name in list) {
        [ac addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self doRestore:name];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC] presentViewController:ac animated:YES completion:nil];
}

- (void)doRestore:(NSString *)name {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *home = NSHomeDirectory();
        NSString *dir = [[self defaultRoot] stringByAppendingPathComponent:name];
        
        // Restore DB
        NSString *dbPath = [dir stringByAppendingPathComponent:@"DB"];
        for (NSString *f in [fm contentsOfDirectoryAtPath:dbPath error:nil]) {
            NSString *src = [dbPath stringByAppendingPathComponent:f];
            // Chuyển __ ngược lại thành / để tìm đúng đường dẫn gốc
            NSString *relPath = [f stringByReplacingOccurrencesOfString:@"__" withString:@"/"];
            NSString *dst = [[home stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:relPath];
            [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:src toPath:dst error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self alert:@"Xong" msg:@"Hãy đóng và mở lại Zalo."];
        });
    });
}

- (void)alert:(NSString *)t msg:(NSString *)m {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[self topVC] presentViewController:ac animated:YES completion:nil];
}
@end

@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *mainBtn, *backupBtn, *restoreBtn;
@property (nonatomic, assign) BOOL isOpen;
@end

@implementation ZBWindow
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 62, 62)];
    if (self) {
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    self.windowScene = scene; break;
                }
            }
        }
        self.windowLevel = UIWindowLevelAlert + 1;
        self.rootViewController = [UIRootVC new];
        
        self.mainBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        self.mainBtn.frame = CGRectMake(3, 3, 56, 56);
        self.mainBtn.backgroundColor = [UIColor colorWithRed:0.04 green:0.49 blue:0.98 alpha:0.9];
        self.mainBtn.layer.cornerRadius = 28;
        [self.mainBtn setTitle:@"Z" forState:UIControlStateNormal];
        [self.mainBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        [self.rootViewController.view addSubview:self.mainBtn];
        
        self.backupBtn = [self createSubBtn:@"Backup" color:[UIColor colorWithRed:0.12 green:0.7 blue:0.22 alpha:1] action:@selector(bk)];
        self.restoreBtn = [self createSubBtn:@"Restore" color:[UIColor colorWithRed:0.98 green:0.56 blue:0 alpha:1] action:@selector(rs)];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self.mainBtn addGestureRecognizer:pan];
        
        CGRect s = [UIScreen mainScreen].bounds;
        self.frame = CGRectMake(s.size.width - 70, s.size.height - 200, 62, 62);
        self.hidden = NO;
    }
    return self;
}

- (UIButton *)createSubBtn:(NSString *)title color:(UIColor *)color action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(-50, 5, 110, 38);
    b.alpha = 0;
    b.backgroundColor = color;
    b.layer.cornerRadius = 19;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.rootViewController.view addSubview:b];
    return b;
}

- (void)toggle {
    self.isOpen = !self.isOpen;
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isOpen) {
            self.backupBtn.frame = CGRectMake(-120, -10, 110, 38); self.backupBtn.alpha = 1;
            self.restoreBtn.frame = CGRectMake(-120, 40, 110, 38); self.restoreBtn.alpha = 1;
        } else {
            self.backupBtn.frame = CGRectMake(-50, 5, 110, 38); self.backupBtn.alpha = 0;
            self.restoreBtn.frame = CGRectMake(-50, 5, 110, 38); self.restoreBtn.alpha = 0;
        }
    }];
}

- (void)bk { [self toggle]; [[ZBManager shared] startBackupFlow]; }
- (void)rs { [self toggle]; [[ZBManager shared] restore]; }

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:nil];
    CGRect f = self.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    self.frame = f;
    [g setTranslation:CGPointZero inView:nil];
}
@end

static ZBWindow *_window;
__attribute__((constructor)) static void Init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        _window = [[ZBWindow alloc] init];
    });
}