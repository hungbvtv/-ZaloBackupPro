#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <zlib.h>

#define ZB_CHUNK 16384

// ============================================================
// ZaloBackup Pro - Final
// - Giu nguyen v8 (UIWindow rieng, nut ZPRO noi)
// - Backup ra file .zip that
// - Auto backup theo lich (chon so gio)
// ============================================================

@interface ZBZip : NSObject
+ (BOOL)zipFiles:(NSArray<NSDictionary *> *)files toPath:(NSString *)zipPath;
+ (NSDictionary *)unzipFile:(NSString *)zipPath;
@end

@implementation ZBZip
+ (NSData *)gzipCompress:(NSData *)data {
    if (!data.length) return nil;
    z_stream s; s.zalloc=Z_NULL; s.zfree=Z_NULL; s.opaque=Z_NULL;
    if (deflateInit2(&s,Z_DEFAULT_COMPRESSION,Z_DEFLATED,15+16,8,Z_DEFAULT_STRATEGY)!=Z_OK) return nil;
    NSMutableData *out=[NSMutableData dataWithLength:ZB_CHUNK];
    s.next_in=(Bytef*)data.bytes; s.avail_in=(uInt)data.length;
    do {
        if (s.total_out>=out.length) [out increaseLengthBy:ZB_CHUNK];
        s.next_out=(Bytef*)out.mutableBytes+s.total_out;
        s.avail_out=(uInt)(out.length-s.total_out);
        deflate(&s,Z_FINISH);
    } while (s.avail_out==0);
    deflateEnd(&s); out.length=s.total_out; return out;
}
+ (NSData *)gzipDecompress:(NSData *)data {
    if (!data.length) return nil;
    z_stream s; s.zalloc=Z_NULL; s.zfree=Z_NULL;
    s.avail_in=(uInt)data.length; s.next_in=(Bytef*)data.bytes;
    if (inflateInit2(&s,15+16)!=Z_OK) return nil;
    NSMutableData *out=[NSMutableData dataWithLength:data.length*4];
    do {
        if (s.total_out>=out.length) [out increaseLengthBy:data.length*2];
        s.next_out=(Bytef*)out.mutableBytes+s.total_out;
        s.avail_out=(uInt)(out.length-s.total_out);
        int r=inflate(&s,Z_SYNC_FLUSH);
        if (r==Z_STREAM_END) break;
        if (r!=Z_OK){inflateEnd(&s);return nil;}
    } while (s.avail_out==0);
    inflateEnd(&s); out.length=s.total_out; return out;
}
+ (BOOL)zipFiles:(NSArray<NSDictionary *> *)files toPath:(NSString *)zipPath {
    NSMutableData *archive=[NSMutableData data];
    for (NSDictionary *e in files) {
        NSString *name=e[@"name"]; NSData *data=e[@"data"];
        if (!name||!data) continue;
        NSData *c=[self gzipCompress:data]?:[data copy];
        uint32_t nl=(uint32_t)name.length, dl=(uint32_t)c.length;
        [archive appendBytes:&nl length:4];
        [archive appendData:[name dataUsingEncoding:NSUTF8StringEncoding]];
        [archive appendBytes:&dl length:4];
        [archive appendData:c];
    }
    return [archive writeToFile:zipPath atomically:YES];
}
+ (NSDictionary *)unzipFile:(NSString *)zipPath {
    NSData *archive=[NSData dataWithContentsOfFile:zipPath];
    if (!archive) return @{};
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    NSUInteger offset=0;
    while (offset+8<=archive.length) {
        uint32_t nl=0; [archive getBytes:&nl range:NSMakeRange(offset,4)]; offset+=4;
        if (offset+nl>archive.length) break;
        NSString *name=[[NSString alloc] initWithData:[archive subdataWithRange:NSMakeRange(offset,nl)] encoding:NSUTF8StringEncoding];
        offset+=nl;
        uint32_t dl=0; [archive getBytes:&dl range:NSMakeRange(offset,4)]; offset+=4;
        if (offset+dl>archive.length) break;
        NSData *d=[archive subdataWithRange:NSMakeRange(offset,dl)]; offset+=dl;
        NSData *dec=[self gzipDecompress:d]?:[d copy];
        if (name) result[name]=dec;
    }
    return result;
}
@end

@interface ZBManager : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)backupFrom:(UIViewController *)vc silent:(BOOL)silent;
- (void)restoreFrom:(UIViewController *)vc;
- (void)startAutoBackup:(NSInteger)hours vc:(UIViewController *)vc;
- (void)stopAutoBackup;
@property (nonatomic, strong) UIViewController *pendingVC;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) NSTimer *autoTimer;
@property (nonatomic, assign) NSInteger autoHours;
@end

@implementation ZBManager
+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t,^{s=[ZBManager new];}); return s;
}
- (UIViewController *)topVC:(UIViewController *)vc {
    while (vc.presentedViewController) vc=vc.presentedViewController; return vc;
}

- (NSMutableArray *)collectFiles {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSArray *sources=@[
        @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"],@"prefix":@"L|"},
        @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],@"prefix":@"D|"},
        @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"],@"prefix":@"C|"}
    ];
    NSSet *exts=[NSSet setWithArray:@[@"db",@"sqlite",@"sqlite3",@"sqlite-wal",@"sqlite-shm",@"db-wal",@"db-shm",@"jpg",@"jpeg",@"png",@"mp4",@"mov",@"plist",@"m4a",@"aac",@"mp3"]];
    NSMutableArray *entries=[NSMutableArray array];
    for (NSDictionary *src in sources) {
        NSString *root=src[@"path"];
        if (![fm fileExistsAtPath:root]) continue;
        NSDirectoryEnumerator *en=[fm enumeratorAtPath:root];
        NSString *f;
        while ((f=en.nextObject)) {
            if ([f containsString:@"ZaloBackupPro"]) continue;
            if ([exts containsObject:f.pathExtension.lowercaseString]) {
                NSData *d=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:f]];
                if (!d) continue;
                [entries addObject:@{
                    @"name":[NSString stringWithFormat:@"%@%@",src[@"prefix"],[f stringByReplacingOccurrencesOfString:@"/" withString:@"|"]],
                    @"data":d
                }];
            }
        }
    }
    return entries;
}

- (void)backupFrom:(UIViewController *)vc silent:(BOOL)silent {
    if (self.busy) return; self.busy=YES;
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSMutableArray *entries=[self collectFiles];
        NSDateFormatter *df=[NSDateFormatter new]; df.dateFormat=@"yyyyMMdd_HHmmss";
        NSString *fname=[NSString stringWithFormat:@"ZaloBackup_%@.zip",[df stringFromDate:NSDate.date]];
        NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:fname];
        BOOL ok=[ZBZip zipFiles:entries toPath:tmp];
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO;
            if (!ok) {
                if (!silent) {
                    UIAlertController *err=[UIAlertController alertControllerWithTitle:@"Loi" message:@"Khong the tao file backup." preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [[self topVC:vc] presentViewController:err animated:YES completion:nil];
                }
                return;
            }
            if (silent) {
                // Auto backup: luu vao Documents, khong can share
                NSString *docsDir=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject];
                NSString *dest=[docsDir stringByAppendingPathComponent:fname];
                [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
                [[NSFileManager defaultManager] copyItemAtPath:tmp toPath:dest error:nil];
                // Hien thong bao nhe
                UIAlertController *done=[UIAlertController alertControllerWithTitle:@"Auto Backup Xong"
                    message:[NSString stringWithFormat:@"Da luu: %@\nTiep theo sau %ld gio.",fname,(long)self.autoHours]
                    preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                    if (vc.presentedViewController==done) [done dismissViewControllerAnimated:YES completion:nil];
                });
                [[self topVC:vc] presentViewController:done animated:YES completion:nil];
            } else {
                // Manual backup: mo share sheet
                UIActivityViewController *avc=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
                if (UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)
                    avc.popoverPresentationController.sourceView=vc.view;
                [[self topVC:vc] presentViewController:avc animated:YES completion:nil];
            }
        });
    });
}

- (void)startAutoBackup:(NSInteger)hours vc:(UIViewController *)vc {
    [self stopAutoBackup];
    self.autoHours=hours;
    self.pendingVC=vc;
    // Backup ngay lan dau
    [self backupFrom:vc silent:YES];
    // Dat timer
    self.autoTimer=[NSTimer scheduledTimerWithTimeInterval:hours*3600
        target:self selector:@selector(autoBackupFire) userInfo:nil repeats:YES];
}

- (void)autoBackupFire {
    UIViewController *vc=self.pendingVC;
    if (!vc) return;
    [self backupFrom:vc silent:YES];
}

- (void)stopAutoBackup {
    [self.autoTimer invalidate];
    self.autoTimer=nil;
}

- (void)restoreFrom:(UIViewController *)vc {
    if (self.busy) return; self.pendingVC=vc;
    UIDocumentPickerViewController *picker;
    picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data",@"public.item"] inMode:UIDocumentPickerModeImport];
    picker.delegate=self; picker.allowsMultipleSelection=NO;
    [[self topVC:vc] presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject; if (!url) return;
    UIViewController *vc=self.pendingVC;
    UIAlertController *ac=[UIAlertController alertControllerWithTitle:@"Xac Nhan"
        message:[NSString stringWithFormat:@"Khoi phuc tu:\n%@\n\nApp se tu dong sau khi xong.",url.lastPathComponent]
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Khoi Phuc" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){
        self.busy=YES;
        dispatch_async(dispatch_get_global_queue(0,0),^{
            NSDictionary *entries=[ZBZip unzipFile:url.path];
            NSFileManager *fm=NSFileManager.defaultManager;
            for (NSString *name in entries) {
                if (name.length<3) continue;
                NSData *d=entries[name];
                NSString *rel=[[name substringFromIndex:2] stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                NSString *dst=nil;
                if ([name hasPrefix:@"L|"]) dst=[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:rel];
                else if ([name hasPrefix:@"D|"]) dst=[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:rel];
                else if ([name hasPrefix:@"C|"]) dst=[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:rel];
                if (dst) {
                    [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                    [d writeToFile:dst atomically:YES];
                }
            }
            dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; exit(0); });
        });
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC:vc] presentViewController:ac animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {}
@end

// ============================================================
// ZBWindow - giu nguyen v8, co them menu Auto Backup
// ============================================================
@interface ZBRootVC : UIViewController @end
@implementation ZBRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, strong) ZBRootVC *rootVC;
@end

@implementation ZBWindow
- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self = [super initWithWindowScene:scene];
    if (!self) return nil;
    self.frame = scene.coordinateSpace.bounds;
    self.windowLevel = UIWindowLevelNormal + 1;
    self.backgroundColor = UIColor.clearColor;
    self.rootVC = [ZBRootVC new];
    self.rootViewController = self.rootVC;
    self.hidden = NO;

    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    CGRect screen = UIScreen.mainScreen.bounds;
    self.btn.frame = CGRectMake(screen.size.width-78, screen.size.height*0.55, 62, 62);
    self.btn.backgroundColor = [UIColor colorWithRed:0 green:0.47 blue:1 alpha:0.88];
    self.btn.layer.cornerRadius = 31;
    self.btn.layer.borderWidth = 2;
    self.btn.layer.borderColor = UIColor.whiteColor.CGColor;
    self.btn.layer.shadowColor = UIColor.blackColor.CGColor;
    self.btn.layer.shadowOpacity = 0.35;
    self.btn.layer.shadowOffset = CGSizeMake(0,3);
    [self.btn setTitle:@"ZPRO" forState:UIControlStateNormal];
    self.btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.btn addGestureRecognizer:pan];
    [self.rootVC.view addSubview:self.btn];
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint p=[self.rootVC.view convertPoint:point fromView:self];
    if (CGRectContainsPoint(self.btn.frame,p)) return self.btn;
    if (self.rootVC.presentedViewController) return [super hitTest:point withEvent:event];
    return nil;
}
- (void)btnTapped {
    ZBManager *mgr=[ZBManager shared];
    NSString *autoTitle = mgr.autoTimer
        ? [NSString stringWithFormat:@"Dung Auto Backup (%ldh)",(long)mgr.autoHours]
        : @"Bat Auto Backup...";

    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"ZaloBackup Pro"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        [[ZBManager shared] backupFrom:self.rootVC silent:NO];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        [[ZBManager shared] restoreFrom:self.rootVC];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:autoTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        if (mgr.autoTimer) {
            [mgr stopAutoBackup];
            UIAlertController *done=[UIAlertController alertControllerWithTitle:@"Da Tat Auto Backup" message:nil preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self.rootVC presentViewController:done animated:YES completion:nil];
        } else {
            [self showAutoBackupPicker];
        }
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Dong" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)
        menu.popoverPresentationController.sourceView=self.btn;
    [self.rootVC presentViewController:menu animated:YES completion:nil];
}
- (void)showAutoBackupPicker {
    UIAlertController *ac=[UIAlertController alertControllerWithTitle:@"Auto Backup Moi Bao Lau?"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts=@[@"1 gio",@"2 gio",@"4 gio",@"6 gio",@"12 gio",@"24 gio"];
    NSArray *vals=@[@1,@2,@4,@6,@12,@24];
    for (int i=0;i<opts.count;i++) {
        NSInteger h=[vals[i] integerValue];
        NSString *t=opts[i];
        [ac addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [[ZBManager shared] startAutoBackup:h vc:self.rootVC];
            UIAlertController *done=[UIAlertController alertControllerWithTitle:@"Auto Backup Bat"
                message:[NSString stringWithFormat:@"Se tu dong backup moi %@ va luu vao Documents.",t]
                preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self.rootVC presentViewController:done animated:YES completion:nil];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)
        ac.popoverPresentationController.sourceView=self.btn;
    [self.rootVC presentViewController:ac animated:YES completion:nil];
}
- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint t=[p translationInView:self.rootVC.view];
    CGRect f=self.btn.frame, b=self.rootVC.view.bounds;
    f.origin.x=MAX(8,MIN(f.origin.x+t.x,b.size.width-f.size.width-8));
    f.origin.y=MAX(50,MIN(f.origin.y+t.y,b.size.height-f.size.height-50));
    self.btn.frame=f;
    [p setTranslation:CGPointZero inView:self.rootVC.view];
}
@end

static ZBWindow *zWin;
static void launchZPRO() {
    if (zWin) return;
    dispatch_async(dispatch_get_main_queue(),^{
        UIWindowScene *scene=nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (s.activationState==UISceneActivationStateForegroundActive &&
                [s isKindOfClass:[UIWindowScene class]]) { scene=(UIWindowScene*)s; break; }
        }
        if (scene) {
            zWin=[[ZBWindow alloc] initWithWindowScene:scene];
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),
                dispatch_get_main_queue(),^{ launchZPRO(); });
        }
    });
}
__attribute__((constructor))
static void zbInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),
        dispatch_get_main_queue(),^{ launchZPRO(); });
}
