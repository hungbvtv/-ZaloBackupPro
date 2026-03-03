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
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject]
            stringByAppendingPathComponent:@"ZaloBackupPro"];
}
- (NSArray *)allBackups {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *r = NSMutableArray.new;
    for (NSString *n in [fm contentsOfDirectoryAtPath:[self defaultRoot] error:nil]) {
        BOOL d=NO;
        [fm fileExistsAtPath:[[self defaultRoot] stringByAppendingPathComponent:n] isDirectory:&d];
        if (d) [r addObject:n];
    }
    return [r sortedArrayUsingComparator:^(id a,id b){return [b compare:a];}];
}
- (UIWindowScene *)activeScene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive &&
            [s isKindOfClass:[UIWindowScene class]])
            return (UIWindowScene *)s;
    }
    return nil;
}
- (UIViewController *)topVC {
    UIViewController *v = nil;
    UIWindowScene *scene = [self activeScene];
    for (UIWindow *w in scene.windows) {
        if (w.isKeyWindow) { v = w.rootViewController; break; }
    }
    if (!v) v = scene.windows.firstObject.rootViewController;
    while (v.presentedViewController) v = v.presentedViewController;
    return v;
}
- (void)startBackupFlow {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Dat Ten Backup"
        message:@"Nhap ten thu muc luu backup:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        NSDateFormatter *df = NSDateFormatter.new; df.dateFormat = @"yyyyMMdd_HHmmss";
        tf.text = [df stringFromDate:NSDate.date];
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Luu vao Documents" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *name = ac.textFields.firstObject.text;
        if (!name.length) name = @"backup";
        [self runBackupToPath:[[self defaultRoot] stringByAppendingPathComponent:name]];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Chon Thu Muc (Files)..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *name = ac.textFields.firstObject.text;
        if (!name.length) name = @"backup";
        [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"zbPendingName"];
        [self openFilePicker];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC] presentViewController:ac animated:YES completion:nil];
}
- (void)openFilePicker {
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    } else {
        picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.folder"] inMode:UIDocumentPickerModeOpen];
    }
    picker.delegate = self; picker.allowsMultipleSelection = NO;
    [[self topVC] presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject; if (!u) return;
    NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:@"zbPendingName"] ?: @"backup";
    BOOL ok = [u startAccessingSecurityScopedResource];
    [self runBackupToPath:[u.path stringByAppendingPathComponent:name]];
    if (ok) [u stopAccessingSecurityScopedResource];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {}
- (void)runBackupToPath:(NSString *)dest {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *home = NSHomeDirectory();
        NSString *dbD = [dest stringByAppendingPathComponent:@"DB"];
        NSString *mdD = [dest stringByAppendingPathComponent:@"Media"];
        [fm createDirectoryAtPath:dbD withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:mdD withIntermediateDirectories:YES attributes:nil error:nil];
        NSArray *search = @[
            [home stringByAppendingPathComponent:@"Library/Application Support"],
            [home stringByAppendingPathComponent:@"Library/Caches"],
            [home stringByAppendingPathComponent:@"Documents"]
        ];
        NSSet *dbExt = [NSSet setWithArray:@[@"db",@"sqlite",@"sqlite3",@"db-wal",@"db-shm"]];
        NSSet *mdExt = [NSSet setWithArray:@[@"jpg",@"jpeg",@"png",@"gif",@"mp4",@"mov",@"aac",@"mp3",@"amr",@"m4a"]];
        NSInteger db=0, md=0;
        for (NSString *sp in search) {
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:sp]; NSString *f;
            while ((f = en.nextObject)) {
                if ([f containsString:@"ZaloBackupPro"]) { [en skipDescendants]; continue; }
                NSString *ext = f.pathExtension.lowercaseString;
                NSString *src = [sp stringByAppendingPathComponent:f];
                NSString *safe = [f stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
                if ([dbExt containsObject:ext]) {
                    NSString *dst = [dbD stringByAppendingPathComponent:safe];
                    [fm removeItemAtPath:dst error:nil];
                    if ([fm copyItemAtPath:src toPath:dst error:nil]) db++;
                } else if ([mdExt containsObject:ext]) {
                    NSString *dst = [mdD stringByAppendingPathComponent:safe];
                    [fm removeItemAtPath:dst error:nil];
                    if ([fm copyItemAtPath:src toPath:dst error:nil]) md++;
                }
            }
        }
        [@{@"date":NSDate.date.description,@"db":@(db),@"media":@(md)}
            writeToFile:[dest stringByAppendingPathComponent:@"info.plist"] atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self alert:@"Backup Hoan Tat"
                    msg:[NSString stringWithFormat:@"Database : %ld file
Media    : %ld file

Luu tai:
%@",(long)db,(long)md,dest]];
        });
    });
}
- (void)restore {
    NSArray *list = [self allBackups];
    if (!list.count) { [self alert:@"Thong Bao" msg:@"Chua co ban backup nao."]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Chon Ban Backup"
            message:@"Chon thoi diem khoi phuc:" preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *name in list) {
            [ac addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
                [self doRestore:name];
            }]];
        }
        [ac addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
        [[self topVC] presentViewController:ac animated:YES completion:nil];
    });
}
- (void)doRestore:(NSString *)name {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *home = NSHomeDirectory();
        NSString *dir = [[self defaultRoot] stringByAppendingPathComponent:name];
        NSInteger count = 0;
        for (NSString *f in [fm contentsOfDirectoryAtPath:[dir stringByAppendingPathComponent:@"DB"] error:nil]) {
            NSString *src = [[dir stringByAppendingPathComponent:@"DB"] stringByAppendingPathComponent:f];
            NSString *dst = [[home stringByAppendingPathComponent:@"Library/Application Support"]
                             stringByAppendingPathComponent:[f stringByReplacingOccurrencesOfString:@"__" withString:@"/"]];
            [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dst error:nil];
            if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
        }
        for (NSString *f in [fm contentsOfDirectoryAtPath:[dir stringByAppendingPathComponent:@"Media"] error:nil]) {
            NSString *src = [[dir stringByAppendingPathComponent:@"Media"] stringByAppendingPathComponent:f];
            NSString *dst = [[home stringByAppendingPathComponent:@"Documents"]
                             stringByAppendingPathComponent:[f stringByReplacingOccurrencesOfString:@"__" withString:@"/"]];
            [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dst error:nil];
            if ([fm copyItemAtPath:src toPath:dst error:nil]) count++;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self alert:@"Khoi Phuc Xong"
                    msg:[NSString stringWithFormat:@"Da khoi phuc %ld file.
Hay TAT va MO LAI Zalo.",(long)count]];
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
@property UIButton *mainBtn, *backupBtn, *restoreBtn;
@property BOOL open;
@end

@implementation ZBWindow
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0,0,62,62)];
    if (!self) return nil;
    // Fix iOS 13+ windowScene
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                self.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
    self.windowLevel = UIWindowLevelAlert + 1;
    self.backgroundColor = UIColor.clearColor;
    UIRootVC *rvc = UIRootVC.new; self.rootViewController = rvc;
    UIView *v = rvc.view;

    self.mainBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.mainBtn.frame = CGRectMake(3,3,56,56);
    self.mainBtn.backgroundColor = [UIColor colorWithRed:0.04 green:0.49 blue:0.98 alpha:0.93];
    self.mainBtn.layer.cornerRadius = 28;
    self.mainBtn.layer.shadowColor = UIColor.blackColor.CGColor;
    self.mainBtn.layer.shadowOpacity = 0.3;
    self.mainBtn.layer.shadowOffset = CGSizeMake(0,3);
    [self.mainBtn setTitle:@"S" forState:UIControlStateNormal];
    self.mainBtn.titleLabel.font = [UIFont systemFontOfSize:26];
    [self.mainBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:self.mainBtn];

    self.backupBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backupBtn.frame = CGRectMake(-50,5,118,38); self.backupBtn.alpha = 0;
    self.backupBtn.backgroundColor = [UIColor colorWithRed:0.12 green:0.70 blue:0.22 alpha:0.96];
    self.backupBtn.layer.cornerRadius = 19;
    [self.backupBtn setTitle:@"Backup" forState:UIControlStateNormal];
    self.backupBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.backupBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.backupBtn addTarget:self action:@selector(bk) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:self.backupBtn];

    self.restoreBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.restoreBtn.frame = CGRectMake(-50,5,118,38); self.restoreBtn.alpha = 0;
    self.restoreBtn.backgroundColor = [UIColor colorWithRed:0.98 green:0.56 blue:0 alpha:0.96];
    self.restoreBtn.layer.cornerRadius = 19;
    [self.restoreBtn setTitle:@"Restore" forState:UIControlStateNormal];
    self.restoreBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.restoreBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.restoreBtn addTarget:self action:@selector(rs) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:self.restoreBtn];

    UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [self.mainBtn addGestureRecognizer:p];

    UIWindowScene *scene = self.windowScene;
    CGRect s = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    self.frame = CGRectMake(s.size.width-72, s.size.height-155, 62, 62);
    self.hidden = NO;
    return self;
}
- (void)toggle {
    self.open = !self.open;
    [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.5 options:0 animations:^{
        if (self.open) {
            self.backupBtn.frame  = CGRectMake(-50,-44,118,38); self.backupBtn.alpha  = 1;
            self.restoreBtn.frame = CGRectMake(-50,-88,118,38); self.restoreBtn.alpha = 1;
        } else {
            self.backupBtn.frame  = CGRectMake(-50,5,118,38); self.backupBtn.alpha  = 0;
            self.restoreBtn.frame = CGRectMake(-50,5,118,38); self.restoreBtn.alpha = 0;
        }
    } completion:nil];
}
- (void)bk  { [self toggle]; [ZBManager.shared startBackupFlow]; }
- (void)rs  { [self toggle]; [ZBManager.shared restore]; }
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:nil];
    CGRect f = self.frame;
    UIWindowScene *scene = self.windowScene;
    CGRect s = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    f.origin.x = MAX(8,  MIN(f.origin.x+t.x, s.size.width -72));
    f.origin.y = MAX(50, MIN(f.origin.y+t.y, s.size.height-115));
    self.frame = f; [g setTranslation:CGPointZero inView:nil];
}
@end

static ZBWindow *_w;
__attribute__((constructor))
static void Init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ _w = ZBWindow.new; });
}