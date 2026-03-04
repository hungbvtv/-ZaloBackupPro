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
- (void)backupFrom:(UIViewController *)vc silent:(BOOL)silent;
- (void)restoreFrom:(UIViewController *)vc;
- (void)startAutoBackup:(NSInteger)hours vc:(UIViewController *)vc;
- (void)stopAutoBackup;
@property (nonatomic, strong) UIViewController *pendingVC;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) NSTimer *autoTimer;
@property (nonatomic, assign) NSInteger autoHours;
@property (nonatomic, copy) void(^onStateChange)(void);
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
    if (self.onStateChange) self.onStateChange();
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSMutableArray *entries=[self collectFiles];
        NSDateFormatter *df=[NSDateFormatter new]; df.dateFormat=@"yyyyMMdd_HHmmss";
        NSString *fname=[NSString stringWithFormat:@"ZaloBackup_%@.zip",[df stringFromDate:NSDate.date]];
        NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:fname];
        BOOL ok=[ZBZip zipFiles:entries toPath:tmp];
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO;
            if (self.onStateChange) self.onStateChange();
            if (!ok) { return; }
            if (silent) {
                NSString *docs=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject];
                NSString *dest=[docs stringByAppendingPathComponent:fname];
                [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
                [[NSFileManager defaultManager] copyItemAtPath:tmp toPath:dest error:nil];
            } else {
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
    self.autoHours=hours; self.pendingVC=vc;
    [self backupFrom:vc silent:YES];
    self.autoTimer=[NSTimer scheduledTimerWithTimeInterval:hours*3600 target:self selector:@selector(autoFire) userInfo:nil repeats:YES];
    if (self.onStateChange) self.onStateChange();
}
- (void)autoFire { [self backupFrom:self.pendingVC silent:YES]; }
- (void)stopAutoBackup {
    [self.autoTimer invalidate]; self.autoTimer=nil;
    if (self.onStateChange) self.onStateChange();
}
- (void)restoreFrom:(UIViewController *)vc {
    if (self.busy) return; self.pendingVC=vc;
    UIDocumentPickerViewController *p=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data",@"public.item"] inMode:UIDocumentPickerModeImport];
    p.delegate=self; p.allowsMultipleSelection=NO;
    [[self topVC:vc] presentViewController:p animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject; if (!url) return;
    UIViewController *vc=self.pendingVC;
    UIAlertController *ac=[UIAlertController alertControllerWithTitle:@"Xac nhan khoi phuc"
        message:[NSString stringWithFormat:@"%@\nDu lieu se bi ghi de. App tu dong sau khi xong.",url.lastPathComponent]
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
// ZBRootVC + ZBWindow - simple, no blur, iOS native colors
// ============================================================
@interface ZBRootVC : UIViewController @end
@implementation ZBRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, strong) UIView *badgeDot;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *statusLbl;
@property (nonatomic, assign) BOOL panelShown;
@property (nonatomic, strong) ZBRootVC *rootVC;
@end

@implementation ZBWindow

- (instancetype)initWithWindowScene:(UIWindowScene *)scene {
    self=[super initWithWindowScene:scene];
    if (!self) return nil;
    self.frame=scene.coordinateSpace.bounds;
    self.windowLevel=UIWindowLevelNormal+1;
    self.backgroundColor=UIColor.clearColor;
    self.rootVC=[ZBRootVC new];
    self.rootViewController=self.rootVC;
    self.hidden=NO;

    CGRect screen=UIScreen.mainScreen.bounds;

    // --- Floating Button ---
    self.btn=[UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame=CGRectMake(screen.size.width-70, screen.size.height*0.52, 56, 56);
    self.btn.backgroundColor=[UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:0.88];
    self.btn.layer.cornerRadius=28;
    self.btn.layer.borderWidth=1.5;
    self.btn.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.2].CGColor;
    self.btn.layer.shadowColor=UIColor.blackColor.CGColor;
    self.btn.layer.shadowOpacity=0.3;
    self.btn.layer.shadowRadius=8;
    self.btn.layer.shadowOffset=CGSizeMake(0,4);
    [self.btn setTitle:@"🔐" forState:UIControlStateNormal];
    self.btn.titleLabel.font=[UIFont systemFontOfSize:24];
    [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.btn addTarget:self action:@selector(btnDown) forControlEvents:UIControlEventTouchDown];
    [self.btn addTarget:self action:@selector(btnUp) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.btn addGestureRecognizer:pan];
    [self.rootVC.view addSubview:self.btn];

    // Badge dot
    self.badgeDot=[[UIView alloc] initWithFrame:CGRectMake(38,2,13,13)];
    self.badgeDot.backgroundColor=[UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
    self.badgeDot.layer.cornerRadius=6.5;
    self.badgeDot.layer.borderWidth=2;
    self.badgeDot.layer.borderColor=[UIColor colorWithWhite:0.12 alpha:1].CGColor;
    self.badgeDot.hidden=YES;
    [self.btn addSubview:self.badgeDot];

    // --- Panel ---
    [self buildPanel];

    // State change callback
    __weak ZBWindow *ws=self;
    [ZBManager shared].onStateChange=^{
        dispatch_async(dispatch_get_main_queue(),^{ [ws updateUI]; });
    };

    return self;
}

- (void)buildPanel {
    CGFloat W=240, rowH=52, headerH=54;
    NSInteger rows=4;
    CGFloat H=headerH+rowH*rows;

    self.panel=[[UIView alloc] initWithFrame:CGRectMake(0,0,W,H)];
    self.panel.backgroundColor=[UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:0.96];
    self.panel.layer.cornerRadius=16;
    self.panel.layer.borderWidth=1;
    self.panel.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.1].CGColor;
    self.panel.layer.shadowColor=UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity=0.35;
    self.panel.layer.shadowRadius=20;
    self.panel.layer.shadowOffset=CGSizeMake(0,6);
    self.panel.alpha=0;
    self.panel.hidden=YES;
    self.panel.clipsToBounds=NO;

    // Header
    UILabel *titleIcon=[UILabel new];
    titleIcon.text=@"🔐";
    titleIcon.font=[UIFont systemFontOfSize:18];
    titleIcon.frame=CGRectMake(14,14,28,26);
    [self.panel addSubview:titleIcon];

    UILabel *titleLbl=[UILabel new];
    titleLbl.text=@"ZaloBackup Pro";
    titleLbl.font=[UIFont boldSystemFontOfSize:14];
    titleLbl.textColor=[UIColor whiteColor];
    titleLbl.frame=CGRectMake(46,10,W-60,20);
    [self.panel addSubview:titleLbl];

    self.statusLbl=[UILabel new];
    self.statusLbl.text=@"San sang";
    self.statusLbl.font=[UIFont systemFontOfSize:11];
    self.statusLbl.textColor=[UIColor colorWithWhite:0.5 alpha:1];
    self.statusLbl.frame=CGRectMake(46,30,W-60,16);
    [self.panel addSubview:self.statusLbl];

    // Divider
    UIView *div=[[UIView alloc] initWithFrame:CGRectMake(0,headerH,W,0.5)];
    div.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08];
    [self.panel addSubview:div];

    // Rows data: icon, title, tag
    NSArray *rowData=@[
        @{@"icon":@"📦",@"title":@"Backup",@"tag":@1},
        @{@"icon":@"🔄",@"title":@"Restore",@"tag":@2},
        @{@"icon":@"⏱",@"title":@"Auto Backup",@"tag":@3},
        @{@"icon":@"✕",@"title":@"Dong",@"tag":@4},
    ];
    for (int i=0;i<rowData.count;i++) {
        NSDictionary *rd=rowData[i];
        UIButton *row=[UIButton buttonWithType:UIButtonTypeCustom];
        row.frame=CGRectMake(0,headerH+i*rowH,W,rowH);
        row.backgroundColor=UIColor.clearColor;
        row.tag=[rd[@"tag"] integerValue];
        [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown];
        [row addTarget:self action:@selector(rowUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];

        UILabel *iconL=[UILabel new];
        iconL.text=rd[@"icon"];
        iconL.font=[UIFont systemFontOfSize:20];
        iconL.frame=CGRectMake(14,0,32,rowH);
        iconL.userInteractionEnabled=NO;
        [row addSubview:iconL];

        UILabel *titleL=[UILabel new];
        titleL.text=rd[@"title"];
        titleL.font=[UIFont systemFontOfSize:15];
        titleL.textColor=[rd[@"tag"] integerValue]==4?[UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]:[UIColor whiteColor];
        titleL.frame=CGRectMake(54,0,W-70,rowH);
        titleL.userInteractionEnabled=NO;
        [row addSubview:titleL];

        if (i<rowData.count-1) {
            UIView *sep=[[UIView alloc] initWithFrame:CGRectMake(54,rowH-0.5,W-54,0.5)];
            sep.backgroundColor=[UIColor colorWithWhite:1 alpha:0.06];
            [row addSubview:sep];
        }
        row.tag=[rd[@"tag"] integerValue];
        [self.panel addSubview:row];
    }

    [self.rootVC.view addSubview:self.panel];
}

- (void)rowDown:(UIButton *)row {
    [UIView animateWithDuration:0.08 animations:^{
        row.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08];
    }];
}
- (void)rowUp:(UIButton *)row {
    [UIView animateWithDuration:0.15 animations:^{
        row.backgroundColor=UIColor.clearColor;
    }];
}
- (void)rowTapped:(UIButton *)row {
    switch(row.tag) {
        case 1: // Backup
            [self dismissPanel];
            [[ZBManager shared] backupFrom:self.rootVC silent:NO];
            break;
        case 2: // Restore
            [self dismissPanel];
            [[ZBManager shared] restoreFrom:self.rootVC];
            break;
        case 3: // Auto Backup
            [self handleAutoBackup];
            break;
        case 4: // Dong
            [self dismissPanel];
            break;
    }
}

- (void)handleAutoBackup {
    ZBManager *mgr=[ZBManager shared];
    if (mgr.autoTimer) {
        [self dismissPanel];
        [mgr stopAutoBackup];
        return;
    }
    [self dismissPanel];
    UIAlertController *ac=[UIAlertController alertControllerWithTitle:@"Auto Backup"
        message:@"Tu dong backup moi bao lau?" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts=@[@"1 gio",@"2 gio",@"4 gio",@"6 gio",@"12 gio",@"24 gio"];
    NSArray *vals=@[@1,@2,@4,@6,@12,@24];
    for (int i=0;i<opts.count;i++) {
        NSInteger h=[vals[i] integerValue]; NSString *t=opts[i];
        [ac addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [mgr startAutoBackup:h vc:self.rootVC];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)
        ac.popoverPresentationController.sourceView=self.btn;
    [self.rootVC presentViewController:ac animated:YES completion:nil];
}

- (void)updateUI {
    ZBManager *m=[ZBManager shared];
    self.badgeDot.hidden=!m.autoTimer;
    if (m.busy) {
        self.statusLbl.text=@"Dang xu ly...";
        self.statusLbl.textColor=[UIColor colorWithRed:1 green:0.6 blue:0 alpha:1];
    } else if (m.autoTimer) {
        self.statusLbl.text=[NSString stringWithFormat:@"Auto: moi %ldh • Dang chay",(long)m.autoHours];
        self.statusLbl.textColor=[UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
        // Cap nhat title row auto
        for (UIView *v in self.panel.subviews) {
            if ([v isKindOfClass:[UIButton class]] && v.tag==3) {
                for (UIView *sv in v.subviews) {
                    if ([sv isKindOfClass:[UILabel class]]) {
                        UILabel *l=(UILabel*)sv;
                        if ([l.text isEqualToString:@"Auto Backup"] ||
                            [l.text hasPrefix:@"Dung Auto"] ||
                            [l.text isEqualToString:@"Auto Backup"])
                            l.text=[NSString stringWithFormat:@"Dung Auto (%ldh)",(long)m.autoHours];
                    }
                }
            }
        }
    } else {
        self.statusLbl.text=@"San sang";
        self.statusLbl.textColor=[UIColor colorWithWhite:0.5 alpha:1];
        for (UIView *v in self.panel.subviews) {
            if ([v isKindOfClass:[UIButton class]] && v.tag==3) {
                for (UIView *sv in v.subviews) {
                    if ([sv isKindOfClass:[UILabel class]]) {
                        UILabel *l=(UILabel*)sv;
                        if ([l.text hasPrefix:@"Dung Auto"]) l.text=@"Auto Backup";
                    }
                }
            }
        }
    }
}

- (void)btnDown {
    [UIView animateWithDuration:0.1 animations:^{
        self.btn.transform=CGAffineTransformMakeScale(0.9,0.9);
    }];
}
- (void)btnUp {
    [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.5 options:0 animations:^{
        self.btn.transform=CGAffineTransformIdentity;
    } completion:nil];
}
- (void)btnTapped {
    if (self.panelShown) { [self dismissPanel]; return; }
    [self showPanel];
}
- (void)showPanel {
    self.panelShown=YES;
    [self updateUI];
    CGRect bf=self.btn.frame;
    CGRect bounds=self.rootVC.view.bounds;
    CGFloat pw=240, ph=54+52*4;
    CGFloat px=bf.origin.x-pw-8;
    if (px<8) px=bf.origin.x+bf.size.width+8;
    CGFloat py=bf.origin.y;
    if (py+ph>bounds.size.height-20) py=bounds.size.height-ph-20;
    self.panel.frame=CGRectMake(px,py,pw,ph);
    self.panel.hidden=NO;
    self.panel.transform=CGAffineTransformMakeScale(0.88,0.88);
    [self.rootVC.view bringSubviewToFront:self.panel];
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.panel.alpha=1;
        self.panel.transform=CGAffineTransformIdentity;
    } completion:nil];
}
- (void)dismissPanel {
    self.panelShown=NO;
    [UIView animateWithDuration:0.18 animations:^{
        self.panel.alpha=0;
        self.panel.transform=CGAffineTransformMakeScale(0.9,0.9);
    } completion:^(BOOL f){
        self.panel.hidden=YES;
        self.panel.transform=CGAffineTransformMakeScale(0.88,0.88);
    }];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint p=[self.rootVC.view convertPoint:point fromView:self];
    if (!self.panel.hidden && CGRectContainsPoint(self.panel.frame,p))
        return [super hitTest:point withEvent:event];
    if (CGRectContainsPoint(self.btn.frame,p)) return self.btn;
    if (self.rootVC.presentedViewController) return [super hitTest:point withEvent:event];
    return nil;
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
}
__attribute__((constructor))
static void zbInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),
        dispatch_get_main_queue(),^{ launchZPRO(); });
}
