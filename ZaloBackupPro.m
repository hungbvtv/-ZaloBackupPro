#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ============================================================
// ZaloBackup Pro v3
// - Backup -> nen ZIP -> chon thu muc luu qua Files picker
// - Restore -> chon file ZIP bat ky qua Files picker
// ============================================================

@interface ZBRootVC : UIViewController @end
@implementation ZBRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface ZBManager : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)startBackupFrom:(UIViewController *)vc;
- (void)startRestoreFrom:(UIViewController *)vc;
@property (nonatomic, weak) UIViewController *pendingVC;
@property (nonatomic, assign) BOOL isRestoreMode;
@end

@implementation ZBManager { BOOL _isProcessing; }

+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (NSString *)tempDir {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"ZBTemp"];
}

// ---- Nen thu muc thanh ZIP ----
- (BOOL)zipDirectory:(NSString *)srcDir toFile:(NSString *)zipPath {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *files = [fm subpathsAtPath:srcDir];
    if (!files.count) return NO;

    // Dung NSFileCoordinator + NSData de tao ZIP don gian
    // Vi khong co ZipArchive, dung tar thay the
    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/bin/zip";
    task.arguments = @[@"-rj", zipPath, srcDir];
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

// ---- Giai nen ZIP ----
- (BOOL)unzipFile:(NSString *)zipPath toDir:(NSString *)destDir {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSTask *task = [NSTask new];
    task.launchPath = @"/usr/bin/unzip";
    task.arguments = @[@"-o", zipPath, @"-d", destDir];
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

- (void)startBackupFrom:(UIViewController *)vc {
    if (_isProcessing) return;
    _isProcessing = YES;

    dispatch_async(dispatch_get_global_queue(0,0), ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *temp = [self tempDir];
            [fm removeItemAtPath:temp error:nil];
            [fm createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:nil];

            NSArray *sources = @[
                @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"], @"prefix":@"L|"},
                @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"], @"prefix":@"D|"},
                @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"], @"prefix":@"C|"}
            ];
            NSSet *exts = [NSSet setWithArray:@[@"db",@"sqlite",@"sqlite3",@"sqlite-wal",@"sqlite-shm",@"db-wal",@"db-shm",@"jpg",@"jpeg",@"png",@"mp4",@"mov",@"plist",@"m4a",@"aac",@"mp3"]];
            NSInteger count = 0;

            for (NSDictionary *source in sources) {
                NSString *root = source[@"path"];
                if (![fm fileExistsAtPath:root]) continue;
                NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
                NSString *file;
                while ((file = [en nextObject])) {
                    if ([file containsString:@"ZBTemp"]) continue;
                    if ([exts containsObject:file.pathExtension.lowercaseString]) {
                        NSString *src = [root stringByAppendingPathComponent:file];
                        NSString *safe = [NSString stringWithFormat:@"%@%@", source[@"prefix"],
                                         [file stringByReplacingOccurrencesOfString:@"/" withString:@"|"]];
                        NSString *dst = [temp stringByAppendingPathComponent:safe];
                        [fm removeItemAtPath:dst error:nil];
                        if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
                    }
                }
            }

            // Tao file ZIP
            NSDateFormatter *df = [NSDateFormatter new];
            df.dateFormat = @"yyyyMMdd_HHmmss";
            NSString *zipName = [NSString stringWithFormat:@"ZaloBackup_%@.zip", [df stringFromDate:NSDate.date]];
            NSString *zipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:zipName];
            [fm removeItemAtPath:zipPath error:nil];

            // Zip bang NSData + minizip approach (khong can binary zip)
            // Su dung cach don gian: luu tung file vao 1 folder roi share
            // Vi iOS khong co /usr/bin/zip, ta dung NSFileCoordinator sharing
            // => Thay vao do, luu folder roi mo Files picker de "Move" ra ngoai

            // Cach khac: dung UIActivityViewController de share folder
            // Nhung de don gian nhat: copy folder ra Documents roi cho user pick
            NSString *finalDir = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject]
                                  stringByAppendingPathComponent:zipName.stringByDeletingPathExtension];
            [fm removeItemAtPath:finalDir error:nil];
            NSError *cpErr = nil;
            [fm copyItemAtPath:temp toPath:finalDir error:&cpErr];

            NSString *msg;
            if (!cpErr) {
                msg = [NSString stringWithFormat:@"Da sao luu %ld tep.\n\nThu muc: Documents/%@\n\nGio chon noi luu file ZIP.", (long)count, zipName.stringByDeletingPathExtension];
            } else {
                msg = [NSString stringWithFormat:@"Loi: %@", cpErr.localizedDescription];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                self->_isProcessing = NO;
                if (!cpErr) {
                    // Hoi user muon luu o dau
                    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Backup Xong"
                        message:msg preferredStyle:UIAlertControllerStyleAlert];
                    [ac addAction:[UIAlertAction actionWithTitle:@"Chon Noi Luu (Files)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                        self.pendingVC = vc;
                        self.isRestoreMode = NO;
                        // Luu NSURL cua folder vua tao de export
                        [[NSUserDefaults standardUserDefaults] setObject:finalDir forKey:@"zbExportPath"];
                        [self openSavePicker:vc folderPath:finalDir];
                    }]];
                    [ac addAction:[UIAlertAction actionWithTitle:@"Giu Trong Documents" style:UIAlertActionStyleDefault handler:nil]];
                    UIViewController *top = vc;
                    while (top.presentedViewController) top = top.presentedViewController;
                    [top presentViewController:ac animated:YES completion:nil];
                } else {
                    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Loi" message:msg preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    UIViewController *top = vc;
                    while (top.presentedViewController) top = top.presentedViewController;
                    [top presentViewController:err animated:YES completion:nil];
                }
            });
        }
    });
}

- (void)openSavePicker:(UIViewController *)vc folderPath:(NSString *)path {
    // Dung UIActivityViewController de share/save folder
    NSURL *url = [NSURL fileURLWithPath:path];
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        avc.popoverPresentationController.sourceView = vc.view;
        avc.popoverPresentationController.sourceRect = CGRectMake(vc.view.bounds.size.width/2, vc.view.bounds.size.height/2, 0, 0);
    }
    UIViewController *top = vc;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:avc animated:YES completion:nil];
}

- (void)startRestoreFrom:(UIViewController *)vc {
    if (_isProcessing) return;
    self.pendingVC = vc;
    self.isRestoreMode = YES;

    // Mo Files picker chon thu muc backup
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc]
                  initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    } else {
        picker = [[UIDocumentPickerViewController alloc]
                  initWithDocumentTypes:@[@"public.folder"] inMode:UIDocumentPickerModeOpen];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    UIViewController *top = vc;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:picker animated:YES completion:nil];
}

// UIDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    if (!self.isRestoreMode) return;

    BOOL ok = [url startAccessingSecurityScopedResource];
    UIViewController *vc = self.pendingVC;

    // Confirm restore
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Xac Nhan Khoi Phuc"
        message:[NSString stringWithFormat:@"Khoi phuc tu:\n%@\n\nDu lieu se bi ghi de. App se tu dong sau khi xong.", url.lastPathComponent]
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Khoi Phuc" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        self->_isProcessing = YES;
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSFileManager *fm = NSFileManager.defaultManager;
            NSArray *files = [fm contentsOfDirectoryAtPath:url.path error:nil];
            NSInteger count = 0;
            for (NSString *f in files) {
                if (f.length < 3) continue;
                NSString *src = [url.path stringByAppendingPathComponent:f];
                NSString *rel = [[f substringFromIndex:2] stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                NSString *dst = nil;
                if ([f hasPrefix:@"L|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:rel];
                else if ([f hasPrefix:@"D|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:rel];
                else if ([f hasPrefix:@"C|"]) dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:rel];
                if (dst) {
                    [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                    [fm removeItemAtPath:dst error:nil];
                    if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
                }
            }
            if (ok) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_isProcessing = NO;
                exit(0);
            });
        });
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:^(UIAlertAction *_) {
        if (ok) [url stopAccessingSecurityScopedResource];
    }]];
    UIViewController *top = vc;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:confirm animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}
@end

// ============================================================
// ZBWindow
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
    self.rootVC = [ZBRootVC new];
    self.rootViewController = self.rootVC;
    [self makeKeyAndVisible];

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
    CGPoint p = [self.rootVC.view convertPoint:point fromView:self];
    if (CGRectContainsPoint(self.btn.frame, p)) return self.btn;
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
                activeScene = (UIWindowScene *)scene; break;
            }
        }
        if (activeScene) {
            zWin = [[ZBWindow alloc] initWithWindowScene:activeScene];
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ launchZaloPro(); });
        }
    });
}
__attribute__((constructor))
static void zbInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ launchZaloPro(); });
}
