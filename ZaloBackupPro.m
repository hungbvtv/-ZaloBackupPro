#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

// ============================================================
// ZBGalleryCell
// ============================================================
@interface ZBGalleryCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *nameLbl;
@end

@implementation ZBGalleryCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.contentView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.contentView.layer.cornerRadius = 8;
    self.contentView.clipsToBounds = YES;

    self.imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.width)];
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    [self.contentView addSubview:self.imageView];

    self.nameLbl = [[UILabel alloc] initWithFrame:CGRectMake(2, frame.size.width, frame.size.width - 4, 16)];
    self.nameLbl.font = [UIFont systemFontOfSize:9];
    self.nameLbl.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    self.nameLbl.textAlignment = NSTextAlignmentCenter;
    self.nameLbl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.contentView addSubview:self.nameLbl];

    return self;
}
@end

// ============================================================
// ZBImageDetailVC - xem ảnh full screen
// ============================================================
@interface ZBImageDetailVC : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) NSString *fileName;
@end

@implementation ZBImageDetailVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.delegate = self;
    scroll.minimumZoomScale = 1.0;
    scroll.maximumZoomScale = 4.0;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:scroll];

    UIImageView *iv = [[UIImageView alloc] initWithImage:self.image];
    iv.tag = 99;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = self.view.bounds;
    [scroll addSubview:iv];

    UILabel *nameLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 50, self.view.bounds.size.width - 100, 24)];
    nameLbl.text = self.fileName;
    nameLbl.font = [UIFont systemFontOfSize:13];
    nameLbl.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    nameLbl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:nameLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(self.view.bounds.size.width - 52, 44, 36, 36);
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    closeBtn.layer.cornerRadius = 18;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];

    UIButton *shareBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    shareBtn.frame = CGRectMake(self.view.bounds.size.width - 96, 44, 36, 36);
    shareBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    shareBtn.layer.cornerRadius = 18;
    [shareBtn setTitle:@"⬆️" forState:UIControlStateNormal];
    shareBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [shareBtn addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:shareBtn];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(doubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [scroll addGestureRecognizer:doubleTap];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv {
    return [sv viewWithTag:99];
}
- (void)doubleTapped:(UITapGestureRecognizer *)gr {
    UIScrollView *sv = (UIScrollView *)gr.view;
    sv.zoomScale = sv.zoomScale > 1.5 ? 1.0 : 3.0;
}
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)shareTapped {
    if (!self.image) return;
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[self.image] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
        avc.popoverPresentationController.sourceView = self.view;
    [self presentViewController:avc animated:YES completion:nil];
}
@end

// ============================================================
// ZBGalleryVC - grid ảnh
// ============================================================
@interface ZBGalleryVC : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *imageEntries;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLbl;
@property (nonatomic, strong) UILabel *countLbl;
@end

@implementation ZBGalleryVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.10 alpha:1];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 56)];
    header.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1];
    [self.view addSubview:header];

    UILabel *title = [UILabel new];
    title.text = @"🖼 Ảnh trong Backup";
    title.font = [UIFont boldSystemFontOfSize:16];
    title.textColor = UIColor.whiteColor;
    title.frame = CGRectMake(16, 16, self.view.bounds.size.width - 100, 24);
    [header addSubview:title];

    self.countLbl = [UILabel new];
    self.countLbl.font = [UIFont systemFontOfSize:12];
    self.countLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    self.countLbl.textAlignment = NSTextAlignmentRight;
    self.countLbl.frame = CGRectMake(self.view.bounds.size.width - 120, 18, 104, 20);
    [header addSubview:self.countLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(self.view.bounds.size.width - 48, 10, 36, 36);
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    closeBtn.layer.cornerRadius = 18;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15];
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];

    CGFloat padding = 12, spacing = 8;
    CGFloat cellW = (self.view.bounds.size.width - padding * 2 - spacing * 2) / 3;
    CGFloat cellH = cellW + 18;

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.itemSize = CGSizeMake(cellW, cellH);
    layout.minimumInteritemSpacing = spacing;
    layout.minimumLineSpacing = spacing;
    layout.sectionInset = UIEdgeInsetsMake(padding, padding, padding, padding);

    self.collectionView = [[UICollectionView alloc]
        initWithFrame:CGRectMake(0, 56, self.view.bounds.size.width, self.view.bounds.size.height - 56)
        collectionViewLayout:layout];
    self.collectionView.backgroundColor = UIColor.clearColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[ZBGalleryCell class] forCellWithReuseIdentifier:@"cell"];
    [self.view addSubview:self.collectionView];

    self.emptyLbl = [UILabel new];
    self.emptyLbl.text = @"Không có ảnh trong backup này";
    self.emptyLbl.font = [UIFont systemFontOfSize:14];
    self.emptyLbl.textColor = [UIColor colorWithWhite:0.4 alpha:1];
    self.emptyLbl.textAlignment = NSTextAlignmentCenter;
    self.emptyLbl.frame = CGRectMake(0, 200, self.view.bounds.size.width, 40);
    self.emptyLbl.hidden = self.imageEntries.count > 0;
    [self.view addSubview:self.emptyLbl];

    self.countLbl.text = [NSString stringWithFormat:@"%ld ảnh", (long)self.imageEntries.count];
}
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    return self.imageEntries.count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    ZBGalleryCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:ip];
    NSDictionary *entry = self.imageEntries[ip.row];
    NSString *b64 = entry[@"data"];
    if (b64) {
        NSData *imgData = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
        cell.imageView.image = imgData ? [UIImage imageWithData:imgData] : nil;
    }
    NSString *name = entry[@"name"] ?: @"";
    if (name.length > 2) name = [name substringFromIndex:2];
    name = [name stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
    cell.nameLbl.text = name.lastPathComponent;
    return cell;
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *entry = self.imageEntries[ip.row];
    NSString *b64 = entry[@"data"];
    if (!b64) return;
    NSData *imgData = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    UIImage *img = imgData ? [UIImage imageWithData:imgData] : nil;
    if (!img) return;

    ZBImageDetailVC *detail = [ZBImageDetailVC new];
    detail.image = img;
    NSString *name = entry[@"name"] ?: @"";
    if (name.length > 2) name = [name substringFromIndex:2];
    detail.fileName = [name stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
    detail.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:detail animated:YES completion:nil];
}
@end

// ============================================================
// ZBManager
// ============================================================
@interface ZBManager : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)backupFrom:(UIViewController *)vc silent:(BOOL)silent;
- (void)restoreFrom:(UIViewController *)vc;
- (void)viewGalleryFrom:(UIViewController *)vc;
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
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (UIViewController *)topVC:(UIViewController *)vc {
    while (vc.presentedViewController) vc = vc.presentedViewController; return vc;
}

- (NSMutableArray *)collectFiles {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *sources = @[
        @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"], @"prefix": @"L|"},
        @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"], @"prefix": @"D|"},
        @{@"path": [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"], @"prefix": @"C|"}
    ];
    NSSet *exts = [NSSet setWithArray:@[
        @"db", @"sqlite", @"sqlite3", @"sqlite-wal", @"sqlite-shm",
        @"db-wal", @"db-shm", @"jpg", @"jpeg", @"png",
        @"mp4", @"mov", @"plist", @"m4a", @"aac", @"mp3"
    ]];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *src in sources) {
        NSString *root = src[@"path"];
        if (![fm fileExistsAtPath:root]) continue;
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
        NSString *f;
        while ((f = en.nextObject)) {
            if ([f containsString:@"ZaloBackupPro"]) continue;
            if ([exts containsObject:f.pathExtension.lowercaseString]) {
                NSString *fullPath = [root stringByAppendingPathComponent:f];
                NSData *d = [NSData dataWithContentsOfFile:fullPath];
                if (!d) continue;
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                NSString *modDate = @"";
                if (attrs[NSFileModificationDate]) {
                    NSDateFormatter *df = [NSDateFormatter new];
                    df.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
                    modDate = [df stringFromDate:attrs[NSFileModificationDate]];
                }
                [entries addObject:@{
                    @"name": [NSString stringWithFormat:@"%@%@", src[@"prefix"],
                        [f stringByReplacingOccurrencesOfString:@"/" withString:@"|"]],
                    @"ext": f.pathExtension.lowercaseString,
                    @"size": @(d.length),
                    @"modified": modDate,
                    @"data": [d base64EncodedStringWithOptions:0]
                }];
            }
        }
    }
    return entries;
}

- (void)backupFrom:(UIViewController *)vc silent:(BOOL)silent {
    if (self.busy) return;
    self.busy = YES;
    if (self.onStateChange) self.onStateChange();
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSMutableArray *entries = [self collectFiles];
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"yyyyMMdd_HHmmss";
        NSString *timestamp = [df stringFromDate:NSDate.date];
        NSDictionary *jsonRoot = @{
            @"version": @"1.0",
            @"created": timestamp,
            @"device": UIDevice.currentDevice.name ?: @"unknown",
            @"fileCount": @(entries.count),
            @"files": entries
        };
        NSError *err = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonRoot
            options:NSJSONWritingPrettyPrinted error:&err];
        NSString *fname = [NSString stringWithFormat:@"ZaloBackup_%@.json", timestamp];
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:fname];
        BOOL ok = !err && [jsonData writeToFile:tmp atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (self.onStateChange) self.onStateChange();
            if (!ok) return;
            if (silent) {
                NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                NSString *dest = [docs stringByAppendingPathComponent:fname];
                [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
                [[NSFileManager defaultManager] copyItemAtPath:tmp toPath:dest error:nil];
            } else {
                UIActivityViewController *avc = [[UIActivityViewController alloc]
                    initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
                if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
                    avc.popoverPresentationController.sourceView = vc.view;
                [[self topVC:vc] presentViewController:avc animated:YES completion:nil];
            }
        });
    });
}

- (void)startAutoBackup:(NSInteger)hours vc:(UIViewController *)vc {
    [self stopAutoBackup];
    self.autoHours = hours;
    self.pendingVC = vc;
    [self backupFrom:vc silent:YES];
    self.autoTimer = [NSTimer scheduledTimerWithTimeInterval:hours * 3600
        target:self selector:@selector(autoFire) userInfo:nil repeats:YES];
    if (self.onStateChange) self.onStateChange();
}
- (void)autoFire { [self backupFrom:self.pendingVC silent:YES]; }
- (void)stopAutoBackup {
    [self.autoTimer invalidate];
    self.autoTimer = nil;
    if (self.onStateChange) self.onStateChange();
}

- (void)restoreFrom:(UIViewController *)vc {
    if (self.busy) return;
    self.pendingVC = vc;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.json", @"public.text", @"public.data"]
        inMode:UIDocumentPickerModeImport];
    objc_setAssociatedObject(p, "zbmode", @"restore", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [[self topVC:vc] presentViewController:p animated:YES completion:nil];
}

- (void)viewGalleryFrom:(UIViewController *)vc {
    self.pendingVC = vc;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.json", @"public.text", @"public.data"]
        inMode:UIDocumentPickerModeImport];
    objc_setAssociatedObject(p, "zbmode", @"gallery", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [[self topVC:vc] presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    UIViewController *vc = self.pendingVC;

    NSString *mode = objc_getAssociatedObject(c, "zbmode") ?: @"restore";

    NSData *jsonData = [NSData dataWithContentsOfURL:url];
    if (!jsonData) return;
    NSError *err = nil;
    NSDictionary *jsonRoot = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&err];

    if (err || !jsonRoot[@"files"]) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Lỗi"
            message:@"File JSON không hợp lệ hoặc bị hỏng."
            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self topVC:vc] presentViewController:ac animated:YES completion:nil];
        return;
    }

    // ---- GALLERY MODE ----
    if ([mode isEqualToString:@"gallery"]) {
        NSArray *allFiles = jsonRoot[@"files"];
        NSSet *imgExts = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png"]];
        NSArray *images = [allFiles filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id _) {
                return [imgExts containsObject:[e[@"ext"] lowercaseString]];
            }]];
        ZBGalleryVC *gallery = [ZBGalleryVC new];
        gallery.imageEntries = images;
        gallery.modalPresentationStyle = UIModalPresentationPageSheet;
        [[self topVC:vc] presentViewController:gallery animated:YES completion:nil];
        return;
    }

    // ---- RESTORE MODE ----
    NSString *created = jsonRoot[@"created"] ?: @"?";
    NSString *device = jsonRoot[@"device"] ?: @"?";
    NSInteger fileCount = [jsonRoot[@"fileCount"] integerValue];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Xác Nhận Khôi Phục"
        message:[NSString stringWithFormat:
            @"File: %@\nNgày tạo: %@\nThiết bị: %@\nSố file: %ld\n\nDữ liệu sẽ bị ghi đè. App tự đóng sau khi xong.",
            url.lastPathComponent, created, device, (long)fileCount]
        preferredStyle:UIAlertControllerStyleAlert];

    [ac addAction:[UIAlertAction actionWithTitle:@"Khôi Phục" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        self.busy = YES;
        if (self.onStateChange) self.onStateChange();
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSArray *files = jsonRoot[@"files"];
            NSFileManager *fm = NSFileManager.defaultManager;
            for (NSDictionary *entry in files) {
                NSString *name = entry[@"name"];
                NSString *b64 = entry[@"data"];
                if (!name || !b64 || name.length < 3) continue;
                NSData *d = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
                if (!d) continue;
                NSString *rel = [[name substringFromIndex:2]
                    stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                NSString *dst = nil;
                if ([name hasPrefix:@"L|"])
                    dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"]
                        stringByAppendingPathComponent:rel];
                else if ([name hasPrefix:@"D|"])
                    dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                        stringByAppendingPathComponent:rel];
                else if ([name hasPrefix:@"C|"])
                    dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"]
                        stringByAppendingPathComponent:rel];
                if (dst) {
                    [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent
                        withIntermediateDirectories:YES attributes:nil error:nil];
                    [d writeToFile:dst atomically:YES];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                if (self.onStateChange) self.onStateChange();
                exit(0);
            });
        });
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [[self topVC:vc] presentViewController:ac animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {}
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
@property (nonatomic, strong) UIView *badgeDot;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *statusLbl;
@property (nonatomic, assign) BOOL panelShown;
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

    CGRect screen = UIScreen.mainScreen.bounds;

    // Floating Button
    self.btn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.btn.frame = CGRectMake(screen.size.width - 70, screen.size.height * 0.52, 56, 56);
    self.btn.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:0.88];
    self.btn.layer.cornerRadius = 28;
    self.btn.layer.borderWidth = 1.5;
    self.btn.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    self.btn.layer.shadowColor = UIColor.blackColor.CGColor;
    self.btn.layer.shadowOpacity = 0.3;
    self.btn.layer.shadowRadius = 8;
    self.btn.layer.shadowOffset = CGSizeMake(0, 4);
    [self.btn setTitle:@"🔐" forState:UIControlStateNormal];
    self.btn.titleLabel.font = [UIFont systemFontOfSize:24];
    [self.btn addTarget:self action:@selector(btnTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.btn addTarget:self action:@selector(btnDown) forControlEvents:UIControlEventTouchDown];
    [self.btn addTarget:self action:@selector(btnUp) forControlEvents:
        UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.btn addGestureRecognizer:pan];
    [self.rootVC.view addSubview:self.btn];

    // Badge dot
    self.badgeDot = [[UIView alloc] initWithFrame:CGRectMake(38, 2, 13, 13)];
    self.badgeDot.backgroundColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
    self.badgeDot.layer.cornerRadius = 6.5;
    self.badgeDot.layer.borderWidth = 2;
    self.badgeDot.layer.borderColor = [UIColor colorWithWhite:0.12 alpha:1].CGColor;
    self.badgeDot.hidden = YES;
    [self.btn addSubview:self.badgeDot];

    [self buildPanel];

    __weak ZBWindow *ws = self;
    [ZBManager shared].onStateChange = ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [ws updateUI]; });
    };

    return self;
}

- (void)buildPanel {
    CGFloat W = 240, rowH = 52, headerH = 54;
    NSInteger rows = 5; // Backup, Restore, Gallery, Auto, Đóng
    CGFloat H = headerH + rowH * rows;

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:0.96];
    self.panel.layer.cornerRadius = 16;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.1].CGColor;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.35;
    self.panel.layer.shadowRadius = 20;
    self.panel.layer.shadowOffset = CGSizeMake(0, 6);
    self.panel.alpha = 0;
    self.panel.hidden = YES;
    self.panel.clipsToBounds = NO;

    UILabel *titleIcon = [UILabel new];
    titleIcon.text = @"🔐";
    titleIcon.font = [UIFont systemFontOfSize:18];
    titleIcon.frame = CGRectMake(14, 14, 28, 26);
    [self.panel addSubview:titleIcon];

    UILabel *titleLbl = [UILabel new];
    titleLbl.text = @"ZaloBackup Pro";
    titleLbl.font = [UIFont boldSystemFontOfSize:14];
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.frame = CGRectMake(46, 10, W - 60, 20);
    [self.panel addSubview:titleLbl];

    self.statusLbl = [UILabel new];
    self.statusLbl.text = @"Sẵn sàng";
    self.statusLbl.font = [UIFont systemFontOfSize:11];
    self.statusLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    self.statusLbl.frame = CGRectMake(46, 30, W - 60, 16);
    [self.panel addSubview:self.statusLbl];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, headerH, W, 0.5)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [self.panel addSubview:div];

    NSArray *rowData = @[
        @{@"icon": @"📦", @"title": @"Backup",      @"tag": @1},
        @{@"icon": @"🔄", @"title": @"Restore",     @"tag": @2},
        @{@"icon": @"🖼", @"title": @"Xem Ảnh",     @"tag": @5},
        @{@"icon": @"⏱", @"title": @"Auto Backup",  @"tag": @3},
        @{@"icon": @"✕",  @"title": @"Đóng",        @"tag": @4},
    ];

    for (int i = 0; i < (int)rowData.count; i++) {
        NSDictionary *rd = rowData[i];
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, headerH + i * rowH, W, rowH);
        row.backgroundColor = UIColor.clearColor;
        row.tag = [rd[@"tag"] integerValue];
        [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addTarget:self action:@selector(rowDown:) forControlEvents:UIControlEventTouchDown];
        [row addTarget:self action:@selector(rowUp:) forControlEvents:
            UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

        UILabel *iconL = [UILabel new];
        iconL.text = rd[@"icon"];
        iconL.font = [UIFont systemFontOfSize:20];
        iconL.frame = CGRectMake(14, 0, 32, rowH);
        iconL.userInteractionEnabled = NO;
        [row addSubview:iconL];

        UILabel *titleL = [UILabel new];
        titleL.text = rd[@"title"];
        titleL.font = [UIFont systemFontOfSize:15];
        titleL.textColor = [rd[@"tag"] integerValue] == 4
            ? [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]
            : [UIColor whiteColor];
        titleL.frame = CGRectMake(54, 0, W - 70, rowH);
        titleL.userInteractionEnabled = NO;
        [row addSubview:titleL];

        if (i < (int)rowData.count - 1) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(54, rowH - 0.5, W - 54, 0.5)];
            sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
            [row addSubview:sep];
        }
        [self.panel addSubview:row];
    }

    [self.rootVC.view addSubview:self.panel];
}

- (void)rowDown:(UIButton *)row {
    [UIView animateWithDuration:0.08 animations:^{
        row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    }];
}
- (void)rowUp:(UIButton *)row {
    [UIView animateWithDuration:0.15 animations:^{
        row.backgroundColor = UIColor.clearColor;
    }];
}
- (void)rowTapped:(UIButton *)row {
    switch (row.tag) {
        case 1:
            [self dismissPanel];
            [[ZBManager shared] backupFrom:self.rootVC silent:NO];
            break;
        case 2:
            [self dismissPanel];
            [[ZBManager shared] restoreFrom:self.rootVC];
            break;
        case 3:
            [self handleAutoBackup];
            break;
        case 4:
            [self dismissPanel];
            break;
        case 5:
            [self dismissPanel];
            [[ZBManager shared] viewGalleryFrom:self.rootVC];
            break;
    }
}

- (void)handleAutoBackup {
    ZBManager *mgr = [ZBManager shared];
    if (mgr.autoTimer) {
        [self dismissPanel];
        [mgr stopAutoBackup];
        return;
    }
    [self dismissPanel];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Auto Backup"
        message:@"Tự động backup mỗi bao lâu?" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *opts = @[@"1 giờ", @"2 giờ", @"4 giờ", @"6 giờ", @"12 giờ", @"24 giờ"];
    NSArray *vals = @[@1, @2, @4, @6, @12, @24];
    for (int i = 0; i < (int)opts.count; i++) {
        NSInteger h = [vals[i] integerValue];
        NSString *t = opts[i];
        [ac addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [mgr startAutoBackup:h vc:self.rootVC];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
        ac.popoverPresentationController.sourceView = self.btn;
    [self.rootVC presentViewController:ac animated:YES completion:nil];
}

- (void)updateUI {
    ZBManager *m = [ZBManager shared];
    self.badgeDot.hidden = !m.autoTimer;
    if (m.busy) {
        self.statusLbl.text = @"Đang xử lý...";
        self.statusLbl.textColor = [UIColor colorWithRed:1 green:0.6 blue:0 alpha:1];
    } else if (m.autoTimer) {
        self.statusLbl.text = [NSString stringWithFormat:@"Auto: mỗi %ldh • Đang chạy", (long)m.autoHours];
        self.statusLbl.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
        for (UIView *v in self.panel.subviews) {
            if ([v isKindOfClass:[UIButton class]] && v.tag == 3) {
                for (UIView *sv in v.subviews) {
                    if ([sv isKindOfClass:[UILabel class]]) {
                        UILabel *l = (UILabel *)sv;
                        if ([l.text isEqualToString:@"Auto Backup"] || [l.text hasPrefix:@"Dừng Auto"])
                            l.text = [NSString stringWithFormat:@"Dừng Auto (%ldh)", (long)m.autoHours];
                    }
                }
            }
        }
    } else {
        self.statusLbl.text = @"Sẵn Sàng";
        self.statusLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1];
        for (UIView *v in self.panel.subviews) {
            if ([v isKindOfClass:[UIButton class]] && v.tag == 3) {
                for (UIView *sv in v.subviews) {
                    if ([sv isKindOfClass:[UILabel class]]) {
                        UILabel *l = (UILabel *)sv;
                        if ([l.text hasPrefix:@"Dừng Auto"]) l.text = @"Auto Backup";
                    }
                }
            }
        }
    }
}

- (void)btnDown {
    [UIView animateWithDuration:0.1 animations:^{
        self.btn.transform = CGAffineTransformMakeScale(0.9, 0.9);
    }];
}
- (void)btnUp {
    [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.5
        initialSpringVelocity:0.5 options:0 animations:^{
        self.btn.transform = CGAffineTransformIdentity;
    } completion:nil];
}
- (void)btnTapped {
    if (self.panelShown) { [self dismissPanel]; return; }
    [self showPanel];
}
- (void)showPanel {
    self.panelShown = YES;
    [self updateUI];
    CGRect bf = self.btn.frame;
    CGRect bounds = self.rootVC.view.bounds;
    CGFloat pw = 240, ph = 54 + 52 * 5;
    CGFloat px = bf.origin.x - pw - 8;
    if (px < 8) px = bf.origin.x + bf.size.width + 8;
    CGFloat py = bf.origin.y;
    if (py + ph > bounds.size.height - 20) py = bounds.size.height - ph - 20;
    self.panel.frame = CGRectMake(px, py, pw, ph);
    self.panel.hidden = NO;
    self.panel.transform = CGAffineTransformMakeScale(0.88, 0.88);
    [self.rootVC.view bringSubviewToFront:self.panel];
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.8
        initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.panel.alpha = 1;
        self.panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}
- (void)dismissPanel {
    self.panelShown = NO;
    [UIView animateWithDuration:0.18 animations:^{
        self.panel.alpha = 0;
        self.panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL f) {
        self.panel.hidden = YES;
        self.panel.transform = CGAffineTransformMakeScale(0.88, 0.88);
    }];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint p = [self.rootVC.view convertPoint:point fromView:self];
    if (!self.panel.hidden && CGRectContainsPoint(self.panel.frame, p))
        return [super hitTest:point withEvent:event];
    if (CGRectContainsPoint(self.btn.frame, p)) return self.btn;
    if (self.rootVC.presentedViewController) return [super hitTest:point withEvent:event];
    return nil;
}
- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.rootVC.view];
    CGRect f = self.btn.frame, b = self.rootVC.view.bounds;
    f.origin.x = MAX(8, MIN(f.origin.x + t.x, b.size.width - f.size.width - 8));
    f.origin.y = MAX(50, MIN(f.origin.y + t.y, b.size.height - f.size.height - 50));
    self.btn.frame = f;
    [p setTranslation:CGPointZero inView:self.rootVC.view];
}
@end

// ============================================================
// Entry point
// ============================================================
static ZBWindow *zWin;
static void launchZPRO() {
    if (zWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive &&
            [s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s; break;
        }
    }
    if (scene) {
        zWin = [[ZBWindow alloc] initWithWindowScene:scene];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ launchZPRO(); });
    }
}
__attribute__((constructor))
static void zbInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ launchZPRO(); });
}
