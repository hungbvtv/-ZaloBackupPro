#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <zlib.h>

#define ZB_CHUNK 16384

// ============================================================
// ZaloBackup Pro - iOS Native Style
// - Nut tron dep, icon + badge trang thai auto backup
// - Menu custom panel (khong dung ActionSheet)
// - Animation muot
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

// ============================================================
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
            if (!ok) {
                if (!silent) {
                    UIAlertController *err=[UIAlertController alertControllerWithTitle:@"Loi" message:@"Khong the tao file backup." preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [[self topVC:vc] presentViewController:err animated:YES completion:nil];
                }
                return;
            }
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
    self.autoHours=hours;
    self.pendingVC=vc;
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
        message:[NSString stringWithFormat:@"%@\n\nDu lieu se bi ghi de. App tu dong sau khi xong.",url.lastPathComponent]
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
// ZBPanel - Custom menu panel iOS style
// ============================================================
@interface ZBPanelRow : UIControl
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *separator;
- (instancetype)initWithIcon:(NSString*)icon title:(NSString*)title subtitle:(NSString*)sub;
@end
@implementation ZBPanelRow
- (instancetype)initWithIcon:(NSString*)icon title:(NSString*)title subtitle:(NSString*)sub {
    self=[super init];
    self.backgroundColor=UIColor.clearColor;
    // Icon
    self.iconLabel=[UILabel new];
    self.iconLabel.text=icon;
    self.iconLabel.font=[UIFont systemFontOfSize:22];
    self.iconLabel.textAlignment=NSTextAlignmentCenter;
    [self addSubview:self.iconLabel];
    // Title
    self.titleLabel=[UILabel new];
    self.titleLabel.text=title;
    self.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.titleLabel.textColor=[UIColor labelColor];
    [self addSubview:self.titleLabel];
    // Subtitle
    if (sub.length) {
        self.subtitleLabel=[UILabel new];
        self.subtitleLabel.text=sub;
        self.subtitleLabel.font=[UIFont systemFontOfSize:12];
        self.subtitleLabel.textColor=[UIColor secondaryLabelColor];
        [self addSubview:self.subtitleLabel];
    }
    // Separator
    self.separator=[[UIView alloc] init];
    self.separator.backgroundColor=[UIColor separatorColor];
    [self addSubview:self.separator];
    // Highlight
    [self addTarget:self action:@selector(highlight) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(unhighlight) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchDragExit|UIControlEventTouchCancel];
    return self;
}
- (void)highlight { [UIView animateWithDuration:0.1 animations:^{ self.backgroundColor=[UIColor colorWithWhite:0.5 alpha:0.12]; }]; }
- (void)unhighlight { [UIView animateWithDuration:0.2 animations:^{ self.backgroundColor=UIColor.clearColor; }]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W=self.bounds.size.width, H=self.bounds.size.height;
    self.iconLabel.frame=CGRectMake(16,0,36,H);
    CGFloat tx=62, th=self.subtitleLabel?20:H;
    CGFloat ty=self.subtitleLabel?(H/2-th):0;
    self.titleLabel.frame=CGRectMake(tx,ty,W-tx-16,th);
    if (self.subtitleLabel) self.subtitleLabel.frame=CGRectMake(tx,ty+th+1,W-tx-16,16);
    self.separator.frame=CGRectMake(tx,H-0.5,W-tx,0.5);
}
@end

@interface ZBPanel : UIView
@property (nonatomic, copy) void(^onBackup)(void);
@property (nonatomic, copy) void(^onRestore)(void);
@property (nonatomic, copy) void(^onAutoBackup)(void);
@property (nonatomic, copy) void(^onClose)(void);
- (void)updateState;
@end
@implementation ZBPanel {
    UIView *_bg;
    UILabel *_titleLbl;
    UILabel *_statusLbl;
    ZBPanelRow *_backupRow;
    ZBPanelRow *_restoreRow;
    ZBPanelRow *_autoRow;
    ZBPanelRow *_closeRow;
}
- (instancetype)init {
    self=[super init];
    self.backgroundColor=UIColor.clearColor;
    // Blur background
    UIBlurEffect *blur=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurV=[[UIVisualEffectView alloc] initWithEffect:blur];
    blurV.layer.cornerRadius=16;
    blurV.clipsToBounds=YES;
    blurV.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self addSubview:blurV];
    _bg=blurV;

    // Title bar
    UIView *titleBar=[[UIView alloc] initWithFrame:CGRectMake(0,0,260,52)];
    titleBar.backgroundColor=UIColor.clearColor;
    [blurV.contentView addSubview:titleBar];

    // Icon tren title
    UILabel *appIcon=[UILabel new];
    appIcon.text=@"🔐";
    appIcon.font=[UIFont systemFontOfSize:20];
    appIcon.frame=CGRectMake(16,12,30,28);
    [titleBar addSubview:appIcon];

    _titleLbl=[UILabel new];
    _titleLbl.text=@"ZaloBackup Pro";
    _titleLbl.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLbl.textColor=[UIColor labelColor];
    _titleLbl.frame=CGRectMake(50,8,160,20);
    [titleBar addSubview:_titleLbl];

    _statusLbl=[UILabel new];
    _statusLbl.font=[UIFont systemFontOfSize:11];
    _statusLbl.textColor=[UIColor secondaryLabelColor];
    _statusLbl.frame=CGRectMake(50,28,160,16);
    [titleBar addSubview:_statusLbl];

    // Duong ke ngang
    UIView *div=[[UIView alloc] initWithFrame:CGRectMake(0,52,260,0.5)];
    div.backgroundColor=[UIColor separatorColor];
    [blurV.contentView addSubview:div];

    // Rows
    _backupRow=[[ZBPanelRow alloc] initWithIcon:@"📦" title:@"Backup" subtitle:@"Luu du lieu ra file .zip"];
    _restoreRow=[[ZBPanelRow alloc] initWithIcon:@"🔄" title:@"Restore" subtitle:@"Khoi phuc tu file .zip"];
    _autoRow=[[ZBPanelRow alloc] initWithIcon:@"⏱" title:@"Auto Backup" subtitle:@"Chua bat"];
    _closeRow=[[ZBPanelRow alloc] initWithIcon:@"✕" title:@"Dong" subtitle:nil];
    _closeRow.titleLabel.textColor=[UIColor systemRedColor];

    for (ZBPanelRow *r in @[_backupRow,_restoreRow,_autoRow,_closeRow])
        [blurV.contentView addSubview:r];

    [_backupRow addTarget:self action:@selector(tapBackup) forControlEvents:UIControlEventTouchUpInside];
    [_restoreRow addTarget:self action:@selector(tapRestore) forControlEvents:UIControlEventTouchUpInside];
    [_autoRow addTarget:self action:@selector(tapAuto) forControlEvents:UIControlEventTouchUpInside];
    [_closeRow addTarget:self action:@selector(tapClose) forControlEvents:UIControlEventTouchUpInside];

    self.layer.shadowColor=UIColor.blackColor.CGColor;
    self.layer.shadowOpacity=0.18;
    self.layer.shadowRadius=20;
    self.layer.shadowOffset=CGSizeMake(0,4);

    [self updateState];
    return self;
}
- (void)updateState {
    ZBManager *m=[ZBManager shared];
    if (m.busy) {
        _statusLbl.text=@"Dang xu ly...";
        _statusLbl.textColor=[UIColor systemOrangeColor];
    } else if (m.autoTimer) {
        _statusLbl.text=[NSString stringWithFormat:@"Auto: moi %ldh",(long)m.autoHours];
        _statusLbl.textColor=[UIColor systemGreenColor];
        _autoRow.subtitleLabel.text=[NSString stringWithFormat:@"Dang chay • moi %ldh",(long)m.autoHours];
        _autoRow.iconLabel.text=@"⏱";
    } else {
        _statusLbl.text=@"San sang";
        _statusLbl.textColor=[UIColor secondaryLabelColor];
        _autoRow.subtitleLabel.text=@"Chua bat";
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _bg.frame=self.bounds;
    CGFloat W=260, rowH=56;
    NSArray *rows=@[_backupRow,_restoreRow,_autoRow,_closeRow];
    for (int i=0;i<rows.count;i++)
        [rows[i] setFrame:CGRectMake(0,52+i*rowH,W,rowH)];
    // An separator dong cuoi
    _closeRow.separator.hidden=YES;
}
- (void)tapBackup { if(self.onBackup) self.onBackup(); }
- (void)tapRestore { if(self.onRestore) self.onRestore(); }
- (void)tapAuto { if(self.onAutoBackup) self.onAutoBackup(); }
- (void)tapClose { if(self.onClose) self.onClose(); }
@end

// ============================================================
// ZBRootVC + ZBWindow
// ============================================================
@interface ZBRootVC : UIViewController @end
@implementation ZBRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface ZBWindow : UIWindow
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, strong) UIView *badgeView;
@property (nonatomic, strong) ZBRootVC *rootVC;
@property (nonatomic, strong) ZBPanel *panel;
@property (nonatomic, assign) BOOL panelShown;
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

    // Main button - tron, blur style
    self.btn=[UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame=CGRectMake(screen.size.width-74, screen.size.height*0.52, 58, 58);

    // Blur effect cho nut
    UIBlurEffect *blur=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *blurBtn=[[UIVisualEffectView alloc] initWithEffect:blur];
    blurBtn.frame=CGRectMake(0,0,58,58);
    blurBtn.layer.cornerRadius=29;
    blurBtn.clipsToBounds=YES;
    blurBtn.userInteractionEnabled=NO;
    [self.btn addSubview:blurBtn];

    // Icon
    UILabel *icon=[UILabel new];
    icon.text=@"🔐";
    icon.font=[UIFont systemFontOfSize:24];
    icon.textAlignment=NSTextAlignmentCenter;
    icon.frame=CGRectMake(0,0,58,58);
    icon.userInteractionEnabled=NO;
    [self.btn addSubview:icon];

    self.btn.layer.cornerRadius=29;
    self.btn.layer.shadowColor=UIColor.blackColor.CGColor;
    self.btn.layer.shadowOpacity=0.25;
    self.btn.layer.shadowRadius=8;
    self.btn.layer.shadowOffset=CGSizeMake(0,3);

    [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.btn addTarget:self action:@selector(btnHighlight) forControlEvents:UIControlEventTouchDown];
    [self.btn addTarget:self action:@selector(btnUnhighlight) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];

    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.btn addGestureRecognizer:pan];
    [self.rootVC.view addSubview:self.btn];

    // Badge dot (auto backup indicator)
    self.badgeView=[[UIView alloc] initWithFrame:CGRectMake(40,2,14,14)];
    self.badgeView.backgroundColor=[UIColor systemGreenColor];
    self.badgeView.layer.cornerRadius=7;
    self.badgeView.layer.borderWidth=2;
    self.badgeView.layer.borderColor=UIColor.whiteColor.CGColor;
    self.badgeView.hidden=YES;
    [self.btn addSubview:self.badgeView];

    // Panel
    self.panel=[[ZBPanel alloc] initWithFrame:CGRectMake(0,0,260,52+56*4)];
    self.panel.alpha=0;
    self.panel.transform=CGAffineTransformMakeScale(0.85,0.85);
    self.panel.hidden=YES;
    [self.rootVC.view addSubview:self.panel];

    __weak ZBWindow *ws=self;
    self.panel.onBackup=^{
        [ws dismissPanel];
        [[ZBManager shared] backupFrom:ws.rootVC silent:NO];
    };
    self.panel.onRestore=^{
        [ws dismissPanel];
        [[ZBManager shared] restoreFrom:ws.rootVC];
    };
    self.panel.onAutoBackup=^{ [ws handleAutoBackup]; };
    self.panel.onClose=^{ [ws dismissPanel]; };

    [ZBManager shared].onStateChange=^{
        dispatch_async(dispatch_get_main_queue(),^{
            [ws.panel updateState];
            ws.badgeView.hidden=![ZBManager shared].autoTimer;
        });
    };

    return self;
}

- (void)btnHighlight {
    [UIView animateWithDuration:0.1 animations:^{
        self.btn.transform=CGAffineTransformMakeScale(0.92,0.92);
    }];
}
- (void)btnUnhighlight {
    [UIView animateWithDuration:0.15 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:0 animations:^{
        self.btn.transform=CGAffineTransformIdentity;
    } completion:nil];
}

- (void)btnTapped {
    if (self.panelShown) { [self dismissPanel]; return; }
    [self showPanel];
}

- (void)showPanel {
    self.panelShown=YES;
    [self.panel updateState];
    // Posisi panel
    CGRect bf=self.btn.frame;
    CGRect bounds=self.rootVC.view.bounds;
    CGFloat px=bf.origin.x-270;
    if (px<8) px=bf.origin.x+bf.size.width+8;
    CGFloat py=bf.origin.y;
    if (py+self.panel.bounds.size.height>bounds.size.height-20)
        py=bounds.size.height-self.panel.bounds.size.height-20;
    self.panel.frame=CGRectMake(px,py,260,52+56*4);
    self.panel.hidden=NO;
    [self.rootVC.view bringSubviewToFront:self.panel];
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.panel.alpha=1;
        self.panel.transform=CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismissPanel {
    self.panelShown=NO;
    [UIView animateWithDuration:0.2 animations:^{
        self.panel.alpha=0;
        self.panel.transform=CGAffineTransformMakeScale(0.9,0.9);
    } completion:^(BOOL f){ self.panel.hidden=YES; self.panel.transform=CGAffineTransformMakeScale(0.85,0.85); }];
}

- (void)handleAutoBackup {
    ZBManager *mgr=[ZBManager shared];
    if (mgr.autoTimer) {
        [mgr stopAutoBackup];
        [self.panel updateState];
        return;
    }
    // Chon tan suat
    UIAlertController *ac=[UIAlertController alertControllerWithTitle:@"Auto Backup"
        message:@"Tu dong backup moi bao lau?" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts=@[@"1 gio",@"2 gio",@"4 gio",@"6 gio",@"12 gio",@"24 gio"];
    NSArray *vals=@[@1,@2,@4,@6,@12,@24];
    for (int i=0;i<opts.count;i++) {
        NSInteger h=[vals[i] integerValue]; NSString *t=opts[i];
        [ac addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [mgr startAutoBackup:h vc:self.rootVC];
            [self.panel updateState];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)
        ac.popoverPresentationController.sourceView=self.btn;
    [self.rootVC presentViewController:ac animated:YES completion:nil];
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
