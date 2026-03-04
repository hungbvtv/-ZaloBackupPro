#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <zlib.h>

#define ZB_CHUNK 16384

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
- (void)backupFrom:(UIViewController *)vc;
- (void)restoreFrom:(UIViewController *)vc;
@property (nonatomic, strong) UIViewController *pendingVC;
@property (nonatomic, assign) BOOL busy;
@end

@implementation ZBManager
+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t,^{s=[ZBManager new];}); return s;
}
- (UIViewController *)topVC:(UIViewController *)vc {
    while (vc.presentedViewController) vc=vc.presentedViewController; return vc;
}
- (void)backupFrom:(UIViewController *)vc {
    if (self.busy) return; self.busy=YES;
    dispatch_async(dispatch_get_global_queue(0,0),^{
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
        NSDateFormatter *df=[NSDateFormatter new]; df.dateFormat=@"yyyyMMdd_HHmmss";
        NSString *fname=[NSString stringWithFormat:@"ZaloBackup_%@.zbak",[df stringFromDate:NSDate.date]];
        NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:fname];
        BOOL ok=[ZBZip zipFiles:entries toPath:tmp];
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO;
            if (ok) {
                UIActivityViewController *avc=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
                if (UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)
                    avc.popoverPresentationController.sourceView=vc.view;
                [[self topVC:vc] presentViewController:avc animated:YES completion:nil];
            } else {
                UIAlertController *err=[UIAlertController alertControllerWithTitle:@"Loi" message:@"Khong the tao file backup." preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [[self topVC:vc] presentViewController:err animated:YES completion:nil];
            }
        });
    });
}
- (void)restoreFrom:(UIViewController *)vc {
    if (self.busy) return; self.pendingVC=vc;
    // Dung public.data string de tranh loi UTType forward declaration
    UIDocumentPickerViewController *picker;
    picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data", @"public.item", @"public.content"] inMode:UIDocumentPickerModeImport];
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
// Inject nut ZPRO thang vao Zalo window - KHONG tao UIWindow moi
// ============================================================

@interface UIButton (ZBActions)
- (void)zbTapped;
- (void)zbPan:(UIPanGestureRecognizer *)p;
@end

@implementation UIButton (ZBActions)
- (void)zbTapped {
    // Lay topVC tu Zalo window chinh
    UIWindow *win = self.window;
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;

    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"ZaloBackup Pro"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        [[ZBManager shared] backupFrom:vc];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        [[ZBManager shared] restoreFrom:vc];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Dong" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)
        menu.popoverPresentationController.sourceView=self;
    [vc presentViewController:menu animated:YES completion:nil];
}
- (void)zbPan:(UIPanGestureRecognizer *)p {
    CGPoint t=[p translationInView:self.superview];
    CGRect f=self.frame, b=self.superview.bounds;
    f.origin.x=MAX(8,MIN(f.origin.x+t.x,b.size.width-f.size.width-8));
    f.origin.y=MAX(50,MIN(f.origin.y+t.y,b.size.height-f.size.height-50));
    self.frame=f;
    [p setTranslation:CGPointZero inView:self.superview];
}
@end

static UIButton *_zbBtn=nil;

static void injectButton() {
    if (_zbBtn && _zbBtn.superview) return;
    UIWindowScene *scene=nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (s.activationState==UISceneActivationStateForegroundActive && [s isKindOfClass:[UIWindowScene class]])
        { scene=(UIWindowScene *)s; break; }
    }
    UIWindow *mainWin=nil;
    for (UIWindow *w in scene.windows) {
        if (!w.isHidden && w.alpha>0) { mainWin=w; break; }
    }
    if (!mainWin) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{injectButton();});
        return;
    }
    CGRect screen=UIScreen.mainScreen.bounds;
    _zbBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    _zbBtn.frame=CGRectMake(screen.size.width-78, screen.size.height*0.55, 62, 62);
    _zbBtn.backgroundColor=[UIColor colorWithRed:0 green:0.47 blue:1 alpha:0.88];
    _zbBtn.layer.cornerRadius=31;
    _zbBtn.layer.borderWidth=2;
    _zbBtn.layer.borderColor=UIColor.whiteColor.CGColor;
    _zbBtn.layer.shadowColor=UIColor.blackColor.CGColor;
    _zbBtn.layer.shadowOpacity=0.35;
    _zbBtn.layer.shadowOffset=CGSizeMake(0,3);
    _zbBtn.layer.zPosition=9999;
    [_zbBtn setTitle:@"ZPRO" forState:UIControlStateNormal];
    _zbBtn.titleLabel.font=[UIFont boldSystemFontOfSize:12];
    [_zbBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_zbBtn addTarget:_zbBtn action:@selector(zbTapped) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:_zbBtn action:@selector(zbPan:)];
    [_zbBtn addGestureRecognizer:pan];
    [mainWin addSubview:_zbBtn];
}

__attribute__((constructor))
static void zbInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{ injectButton(); });
}
