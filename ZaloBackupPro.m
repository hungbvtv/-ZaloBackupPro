#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <zlib.h>

#define ZB_CHUNK 16384

@interface ZBZip : NSObject
+ (BOOL)zipFiles:(NSArray<NSDictionary *> *)files toPath:(NSString *)zipPath;
+ (NSDictionary *)unzipFile:(NSString *)zipPath;
@end

@implementation ZBZip

+ (NSData *)gzipCompress:(NSData *)data {
    if (!data.length) return nil;
    z_stream stream;
    stream.zalloc = Z_NULL; stream.zfree = Z_NULL; stream.opaque = Z_NULL;
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15+16, 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:ZB_CHUNK];
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;
    do {
        if (stream.total_out >= out.length) [out increaseLengthBy:ZB_CHUNK];
        stream.next_out = (Bytef *)out.mutableBytes + stream.total_out;
        stream.avail_out = (uInt)(out.length - stream.total_out);
        deflate(&stream, Z_FINISH);
    } while (stream.avail_out == 0);
    deflateEnd(&stream);
    out.length = stream.total_out;
    return out;
}

+ (NSData *)gzipDecompress:(NSData *)data {
    if (!data.length) return nil;
    z_stream stream;
    stream.zalloc = Z_NULL; stream.zfree = Z_NULL;
    stream.avail_in = (uInt)data.length;
    stream.next_in = (Bytef *)data.bytes;
    if (inflateInit2(&stream, 15+16) != Z_OK) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:data.length * 4];
    do {
        if (stream.total_out >= out.length) [out increaseLengthBy:data.length * 2];
        stream.next_out = (Bytef *)out.mutableBytes + stream.total_out;
        stream.avail_out = (uInt)(out.length - stream.total_out);
        int st = inflate(&stream, Z_SYNC_FLUSH);
        if (st == Z_STREAM_END) break;
        if (st != Z_OK) { inflateEnd(&stream); return nil; }
    } while (stream.avail_out == 0);
    inflateEnd(&stream);
    out.length = stream.total_out;
    return out;
}

+ (BOOL)zipFiles:(NSArray<NSDictionary *> *)files toPath:(NSString *)zipPath {
    NSMutableData *archive = [NSMutableData data];
    for (NSDictionary *entry in files) {
        NSString *name = entry[@"name"];
        NSData *data = entry[@"data"];
        if (!name || !data) continue;
        NSData *compressed = [self gzipCompress:data] ?: data;
        uint32_t nameLen = (uint32_t)name.length;
        uint32_t dataLen = (uint32_t)compressed.length;
        [archive appendBytes:&nameLen length:4];
        [archive appendData:[name dataUsingEncoding:NSUTF8StringEncoding]];
        [archive appendBytes:&dataLen length:4];
        [archive appendData:compressed];
    }
    return [archive writeToFile:zipPath atomically:YES];
}

+ (NSDictionary *)unzipFile:(NSString *)zipPath {
    NSData *archive = [NSData dataWithContentsOfFile:zipPath];
    if (!archive) return @{};
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSUInteger offset = 0;
    while (offset + 8 <= archive.length) {
        uint32_t nameLen = 0;
        [archive getBytes:&nameLen range:NSMakeRange(offset, 4)]; offset += 4;
        if (offset + nameLen > archive.length) break;
        NSData *nameData = [archive subdataWithRange:NSMakeRange(offset, nameLen)]; offset += nameLen;
        NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
        uint32_t dataLen = 0;
        [archive getBytes:&dataLen range:NSMakeRange(offset, 4)]; offset += 4;
        if (offset + dataLen > archive.length) break;
        NSData *compressed = [archive subdataWithRange:NSMakeRange(offset, dataLen)]; offset += dataLen;
        NSData *decompressed = [self gzipDecompress:compressed] ?: compressed;
        if (name) result[name] = decompressed;
    }
    return result;
}
@end

@interface ZBRootVC : UIViewController @end
@implementation ZBRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface ZBManager : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
- (void)startBackupFrom:(UIViewController *)vc;
- (void)startRestoreFrom:(UIViewController *)vc;
@property (nonatomic, strong) UIViewController *pendingVC;
@property (nonatomic, assign) BOOL isProcessing;
@end

@implementation ZBManager

+ (instancetype)shared {
    static ZBManager *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [ZBManager new]; }); return s;
}

- (UIViewController *)topFrom:(UIViewController *)vc {
    UIViewController *top = vc;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

- (void)startBackupFrom:(UIViewController *)vc {
    if (self.isProcessing) return;
    self.isProcessing = YES;
    self.pendingVC = vc;

    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSArray *sources = @[
            @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"], @"prefix":@"L|"},
            @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"], @"prefix":@"D|"},
            @{@"path":[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"], @"prefix":@"C|"}
        ];
        NSSet *exts = [NSSet setWithArray:@[@"db",@"sqlite",@"sqlite3",@"sqlite-wal",@"sqlite-shm",
                                             @"db-wal",@"db-shm",@"jpg",@"jpeg",@"png",@"mp4",
                                             @"mov",@"plist",@"m4a",@"aac",@"mp3"]];
        NSMutableArray *entries = [NSMutableArray array];
        for (NSDictionary *source in sources) {
            NSString *root = source[@"path"];
            if (![fm fileExistsAtPath:root]) continue;
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
            NSString *file;
            while ((file = en.nextObject)) {
                if ([file containsString:@"ZaloBackupPro"]) continue;
                if ([exts containsObject:file.pathExtension.lowercaseString]) {
                    NSString *src = [root stringByAppendingPathComponent:file];
                    NSData *data = [NSData dataWithContentsOfFile:src];
                    if (!data) continue;
                    NSString *entryName = [NSString stringWithFormat:@"%@%@",
                        source[@"prefix"],
                        [file stringByReplacingOccurrencesOfString:@"/" withString:@"|"]];
                    [entries addObject:@{@"name":entryName, @"data":data}];
                }
            }
        }

        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"yyyyMMdd_HHmmss";
        NSString *fname = [NSString stringWithFormat:@"ZaloBackup_%@.zbak", [df stringFromDate:NSDate.date]];
        NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fname];
        BOOL ok = [ZBZip zipFiles:entries toPath:tmpPath];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            if (ok) {
                NSURL *url = [NSURL fileURLWithPath:tmpPath];
                UIActivityViewController *avc = [[UIActivityViewController alloc]
                    initWithActivityItems:@[url] applicationActivities:nil];
                if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                    avc.popoverPresentationController.sourceView = vc.view;
                }
                [[self topFrom:vc] presentViewController:avc animated:YES completion:nil];
            } else {
                UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Loi"
                    message:@"Khong the tao file backup." preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [[self topFrom:vc] presentViewController:err animated:YES completion:nil];
            }
        });
    });
}

- (void)startRestoreFrom:(UIViewController *)vc {
    if (self.isProcessing) return;
    self.pendingVC = vc;
    UIDocumentPickerViewController *picker;
    if (@available(iOS 14.0, *)) {
        UTType *zbakType = [UTType typeWithFilenameExtension:@"zbak"];
        NSArray *types = zbakType ? @[zbakType] : @[UTTypeData];
        picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc]
                  initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [[self topFrom:vc] presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    UIViewController *vc = self.pendingVC;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Xac Nhan Khoi Phuc"
        message:[NSString stringWithFormat:@"File: %@\nDu lieu se bi ghi de. App se tu dong sau khi xong.", url.lastPathComponent]
        preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Khoi Phuc" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        self.isProcessing = YES;
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            NSDictionary *entries = [ZBZip unzipFile:url.path];
            NSFileManager *fm = NSFileManager.defaultManager;
            for (NSString *name in entries) {
                if (name.length < 3) continue;
                NSData *data = entries[name];
                NSString *rel = [[name substringFromIndex:2] stringByReplacingOccurrencesOfString:@"|" withString:@"/"];
                NSString *dst = nil;
                if ([name hasPrefix:@"L|"])
                    dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:rel];
                else if ([name hasPrefix:@"D|"])
                    dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:rel];
                else if ([name hasPrefix:@"C|"])
                    dst = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:rel];
                if (dst) {
                    [fm createDirectoryAtPath:dst.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                    [data writeToFile:dst atomically:YES];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isProcessing = NO;
                exit(0);
            });
        });
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Huy" style:UIAlertActionStyleCancel handler:nil]];
    [[self topFrom:vc] presentViewController:confirm animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}
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
    self.btn.layer.shadowOffset = CGSizeMake(0,3);
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
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"ZaloBackup Pro"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Backup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startBackupFrom:self.rootVC];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[ZBManager shared] startRestoreFrom:self.rootVC];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        menu.popoverPresentationController.sourceView = self.btn;
        menu.popoverPresentationController.sourceRect = self.btn.bounds;
    }
    [self.rootVC presentViewController:menu animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.rootVC.view];
    CGRect f = self.btn.frame;
    CGRect bounds = self.rootVC.view.bounds;
    f.origin.x = MAX(8, MIN(f.origin.x+t.x, bounds.size.width-f.size.width-8));
    f.origin.y = MAX(50, MIN(f.origin.y+t.y, bounds.size.height-f.size.height-50));
    self.btn.frame = f;
    [p setTranslation:CGPointZero inView:self.rootVC.view];
}
@end

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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ launchZaloPro(); });
        }
    });
}

__attribute__((constructor))
static void zbInit() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ launchZaloPro(); });
}
