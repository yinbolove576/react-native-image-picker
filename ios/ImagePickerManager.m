#import "ImagePickerManager.h"
#import "ImagePickerUtils.h"
#import <React/RCTConvert.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#include <ffmpegkit/FFmpegKit.h>

@import MobileCoreServices;

@interface ImagePickerManager ()

@property (nonatomic, strong) RCTResponseSenderBlock callback;
@property (nonatomic, copy) NSDictionary *options;

@end

@interface ImagePickerManager (UIImagePickerControllerDelegate) <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@interface ImagePickerManager (UIAdaptivePresentationControllerDelegate) <UIAdaptivePresentationControllerDelegate>
@end

#if __has_include(<PhotosUI/PHPicker.h>)
@interface ImagePickerManager (PHPickerViewControllerDelegate) <PHPickerViewControllerDelegate>
@end
#endif

@implementation ImagePickerManager

NSString *errCameraUnavailable = @"camera_unavailable";
NSString *errPermission = @"permission";
NSString *errOthers = @"others";
RNImagePickerTarget target;

RCT_EXPORT_MODULE();

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"VideoCompressEvent"];
}

RCT_EXPORT_METHOD(launchCamera:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    target = camera;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self launchImagePicker:options callback:callback];
    });
}

RCT_EXPORT_METHOD(launchImageLibrary:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    target = library;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self launchImagePicker:options callback:callback];
    });
}

//cancel FFmpegKit
RCT_EXPORT_METHOD(exitCmd){
    [FFmpegKit cancel];
}

- (void)launchImagePicker:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback
{
    self.callback = callback;
    
    if (target == camera && [ImagePickerUtils isSimulator]) {
        self.callback(@[@{@"errorCode": errCameraUnavailable}]);
        return;
    }
    
    self.options = options;
    
#if __has_include(<PhotosUI/PHPicker.h>)
    if (@available(iOS 14, *)) {
        if (target == library) {
            PHPickerConfiguration *configuration = [ImagePickerUtils makeConfigurationFromOptions:options target:target];
            PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
            picker.delegate = self;
            picker.presentationController.delegate = self;
            
            [self showPickerViewController:picker];
            return;
        }
    }
#endif
    
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    [ImagePickerUtils setupPickerFromOptions:picker options:self.options target:target];
    picker.delegate = self;
    
    [self checkPermission:^(BOOL granted) {
        if (!granted) {
            self.callback(@[@{@"errorCode": errPermission}]);
            return;
        }
        [self showPickerViewController:picker];
    }];
}

- (void) showPickerViewController:(UIViewController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = RCTPresentedViewController();
        [root presentViewController:picker animated:YES completion:nil];
    });
}

#pragma mark - Helpers

-(NSMutableDictionary *)mapImageToAsset:(UIImage *)image data:(NSData *)data originFileName:(NSString *)originFileName {
    NSString *fileType = [ImagePickerUtils getFileType:data];
    
    NSData *originData = [NSData dataWithData:data];
    
    if ((target == camera) && [self.options[@"saveToPhotos"] boolValue]) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    }
    if (![fileType isEqualToString:@"gif"]) {
        image = [ImagePickerUtils resizeImage:image
                                     maxWidth:[self.options[@"maxWidth"] floatValue]
                                    maxHeight:[self.options[@"maxHeight"] floatValue]];
    }
    if ([fileType isEqualToString:@"jpg"] || [fileType isEqualToString:@"png"]) {
        float imageW = image.size.width;
        float imageH = image.size.height;
        float screenshotWidth = [self.options[@"screenshotWidth"] floatValue];
        float screenshotHeight = (imageH/imageW)*screenshotWidth;
        
        if (screenshotWidth > 0) {
            //缩略图方案
            image = [ImagePickerUtils resizeImage:image
                                         maxWidth:screenshotWidth
                                        maxHeight:screenshotHeight];
            data = [ImagePickerUtils getImageData:image];
        }else{
            //压缩图方案
            data = UIImageJPEGRepresentation(image, 0.5);
        }
    }
    
    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    asset[@"type"] = [@"image/" stringByAppendingString:fileType];
    
    NSString *fileName = originFileName;
    
    NSString *path = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:fileName];
    [data writeToFile:path atomically:YES];
    
    NSString *originPath = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"origin_%@",fileName]];
    [originData writeToFile:originPath atomically:YES];
    
    if ([self.options[@"includeBase64"] boolValue]) {
        asset[@"base64"] = [data base64EncodedStringWithOptions:0];
    }
    
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    asset[@"uri"] = [fileURL absoluteString];
    
    if ([self.options[@"screenshotWidth"] floatValue] > 0) {
        asset[@"thumb"] = [fileURL absoluteString];
    }
    
    NSURL *originFileURL = [NSURL fileURLWithPath:originPath];
    asset[@"sourceURL"] = [originFileURL absoluteString];
    
    NSNumber *fileSizeValue = nil;
    NSError *fileSizeError = nil;
    [fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:&fileSizeError];
    if (fileSizeValue){
        asset[@"fileSize"] = fileSizeValue;
    }
    
    NSNumber *originFileSizeValue = nil;
    NSError *originFileSizeError = nil;
    [originFileURL getResourceValue:&originFileSizeValue forKey:NSURLFileSizeKey error:&originFileSizeError];
    if (originFileSizeValue){
        asset[@"sourceFileSize"] = originFileSizeValue;
    }
    
    asset[@"fileName"] = fileName;
    asset[@"width"] = @(image.size.width);
    asset[@"height"] = @(image.size.height);
    
    NSLog(@"===asset:%@",asset);
    
    return asset;
}

-(NSMutableDictionary *)mapVideoToAsset:(NSURL *)url error:(NSError **)error {
    NSString *fileName = [url lastPathComponent];
    NSString *path = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:fileName];
    NSURL *videoDestinationURL = [NSURL fileURLWithPath:path];
    
    if ((target == camera) && [self.options[@"saveToPhotos"] boolValue]) {
        UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil);
    }
    
    if (![url.URLByResolvingSymlinksInPath.path isEqualToString:videoDestinationURL.URLByResolvingSymlinksInPath.path]) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // Delete file if it already exists
        if ([fileManager fileExistsAtPath:videoDestinationURL.path]) {
            [fileManager removeItemAtURL:videoDestinationURL error:nil];
        }
        
        if (url) { // Protect against reported crash
            
            BOOL didSucceed = NO;
            // If we have write access to the source file, move it. Otherwise use copy.
            if ([fileManager isWritableFileAtPath:[url path]]) {
                didSucceed = [fileManager moveItemAtURL:url toURL:videoDestinationURL error:error];
            } else {
                didSucceed = [fileManager copyItemAtURL:url toURL:videoDestinationURL error:error];
            }
            
            if (didSucceed != YES) {
                return nil;
            }
        }
    }
    
    
    NSDictionary * originInfo = [ImagePickerUtils getMediaInfoPath:path];
    
    NSLog(@"===originInfo:%@",originInfo);
    
    int originSize = [originInfo[@"size"] intValue];
    int originWidth = [originInfo[@"width"] intValue];
    int originHeight = [originInfo[@"height"] intValue];
    int originRotation = [originInfo[@"rotation"] intValue];
    int originBitrate = [originInfo[@"bitrate"] intValue];
    float originDuration = [originInfo[@"duration"] floatValue];
    NSString * orginName = originInfo[@"filename"];
    
    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    
    asset[@"sourceURL"] = videoDestinationURL.absoluteString;
    asset[@"sourceFileSize"] = [NSNumber numberWithDouble:originSize];
    asset[@"originVidWidth"] = [NSNumber numberWithDouble:originWidth];
    asset[@"originVidHeight"] = [NSNumber numberWithDouble:originHeight];
    asset[@"duration"] = [NSNumber numberWithDouble:originDuration];
    asset[@"fileName"] = orginName;
    asset[@"type"] = [ImagePickerUtils getFileTypeFromUrl:videoDestinationURL];
    asset[@"uri"] = videoDestinationURL.absoluteString;
    
    NSArray * fileNameArr = [orginName componentsSeparatedByString:@"."];
    NSString * screenshotPath = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"thumb_%@.png",fileNameArr[0]]];

    NSString * thumCommand = [ImagePickerUtils getThumbCommandSpecPath:path outPath:screenshotPath width:originWidth height:originHeight rotate:originRotation];
    
    if ([self.options[@"screenshotWidth"] intValue] > 0) {
        asset[@"thumb"] = screenshotPath;
        thumCommand = [ImagePickerUtils getThumbCommandPath:path outPath:screenshotPath screenshotWidth:[self.options[@"screenshotWidth"] intValue]];
    }
    
    NSLog(@"===thumCommand:%@",thumCommand);
    
    // Delete file if it already exists
    [ImagePickerUtils clearCache:thumCommand];
    
    // get thumb
    FFmpegSession *session = [FFmpegKit execute:thumCommand];
    NSLog(@"===thumb session:%d",[ReturnCode isSuccess:[session getReturnCode]]);
    
    NSDictionary * thumbInfo = [ImagePickerUtils getMediaInfoPath:screenshotPath];
    
    NSLog(@"===thumbInfo:%@",thumbInfo);
    
    int thumbWidth = [thumbInfo[@"width"] intValue];
    int thumbHeight = [thumbInfo[@"height"] intValue];
    
    asset[@"screenshotWidth"] = [NSNumber numberWithDouble:thumbWidth];
    asset[@"screenshotHeight"] = [NSNumber numberWithDouble:thumbHeight];
    asset[@"screenshotPath"] = screenshotPath;
    
    
    BOOL isCompressVideo = [self.options[@"isCompressVideo"] boolValue];
    
    if (isCompressVideo) {
        
        BOOL isCompress = (originWidth >= 1280 || originHeight >= 1280) && originBitrate / 1024 > 3200;
        asset[@"isCompress"] = [NSNumber numberWithBool:isCompress];
        
        if (isCompress) {
            // compress video
            NSArray * fileNameArr = [fileName componentsSeparatedByString:@"."];
            NSString * compressVidPath = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"compress_%@.mp4",fileNameArr[0]]];
            
            // Delete file if it already exists
            [ImagePickerUtils clearCache:compressVidPath];
            
            NSString * videoCommand = [ImagePickerUtils getVideoCommandPath:path outPath:compressVidPath width:originWidth height:originHeight rotate:originRotation];
            
            NSLog(@"===videoCommand:%@",videoCommand);
            
            [self compressVideo:videoCommand path:(NSString *)path outPath:(NSString *)compressVidPath duration:originDuration originSize:originSize];
            
            asset[@"compressVidPath"] = compressVidPath;
        }
    }
    
    NSLog(@"===asset:%@",asset);
    
    return asset;
}


-(void)compressVideo:(NSString *) command path:(NSString *)path outPath:(NSString *)outPath  duration:(float) duration originSize:(int)originSize {
    [FFmpegKit executeAsync:command withCompleteCallback:^(FFmpegSession *session) {
        
        ReturnCode *returnCode = [session getReturnCode];
        
        if ([ReturnCode isSuccess:returnCode]) {
            NSLog(@"===returnCode:%@",returnCode);
            
            NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
            params[@"mode"] =  @"compressVideo";
            params[@"status"] =  @(2);
            
            NSDictionary * compressInfo = [ImagePickerUtils getMediaInfoPath:outPath];
            
            NSLog(@"===compressInfo:%@",compressInfo);
            
            int compressSize = [compressInfo[@"size"] intValue];
            
            if (compressSize > originSize) {
                params[@"compressVidPath"] =  path;
            }
            
            [self sendEventWithName:@"VideoCompressEvent" body:params];
            
        } else if ([ReturnCode isCancel:returnCode]) {
            
            NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
            params[@"mode"] =  @"compressVideo";
            params[@"status"] =  @(0);
            params[@"msg"] =  @"cancel";
            
            [self sendEventWithName:@"VideoCompressEvent" body:params];
            
        } else {
            
            NSString *message = [NSString stringWithFormat:@"Command failed with state %@ and rc %@.%@",[FFmpegKitConfig sessionStateToString:[session getState]], returnCode, [session getFailStackTrace]];
            
            NSLog(@"===error message:%@",message);
            
            NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
            params[@"mode"] =  @"compressVideo";
            params[@"status"] =  @(-1);
            params[@"msg"] =  message;
            
            [self sendEventWithName:@"VideoCompressEvent" body:params];
            
        }
    } withLogCallback:^(Log *log) {
    } withStatisticsCallback:^(Statistics *statistics) {
        int progressTime = statistics.getTime;
        float durationF = duration*1000;
        int progress = ceil(progressTime/durationF*100);
        if (progress<0) {
            progress = 0;
        }
        if (progress>100) {
            progress = 100;
        }
        NSLog(@"===statistics:%d %d %f",progress,progressTime,durationF);
        
        NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
        params[@"mode"] =  @"compressVideo";
        params[@"status"] =  @(1);
        params[@"progress"] =  @(progress);
        params[@"progressTime"] =  [NSString stringWithFormat:@"%f",(float)progressTime/1000];
        
        [self sendEventWithName:@"VideoCompressEvent" body:params];
    }];
}



- (void)checkCameraPermissions:(void(^)(BOOL granted))callback
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    }
    else if (status == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            callback(granted);
            return;
        }];
    }
    else {
        callback(NO);
    }
}

- (void)checkPhotosPermissions:(void(^)(BOOL granted))callback
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                callback(YES);
                return;
            }
            else {
                callback(NO);
                return;
            }
        }];
    }
    else {
        callback(NO);
    }
}

// Both camera and photo write permission is required to take picture/video and store it to public photos
- (void)checkCameraAndPhotoPermission:(void(^)(BOOL granted))callback
{
    [self checkCameraPermissions:^(BOOL cameraGranted) {
        if (!cameraGranted) {
            callback(NO);
            return;
        }
        
        [self checkPhotosPermissions:^(BOOL photoGranted) {
            if (!photoGranted) {
                callback(NO);
                return;
            }
            callback(YES);
        }];
    }];
}

- (void)checkPermission:(void(^)(BOOL granted)) callback
{
    void (^permissionBlock)(BOOL) = ^(BOOL permissionGranted) {
        if (!permissionGranted) {
            callback(NO);
            return;
        }
        callback(YES);
    };
    
    if (target == camera && [self.options[@"saveToPhotos"] boolValue]) {
        [self checkCameraAndPhotoPermission:permissionBlock];
    }
    else if (target == camera) {
        [self checkCameraPermissions:permissionBlock];
    }
    else {
        if (@available(iOS 11.0, *)) {
            callback(YES);
        }
        else {
            [self checkPhotosPermissions:permissionBlock];
        }
    }
}

- (NSString *)getImageFileName:(NSString *)fileType
{
    NSString *fileName = [[NSUUID UUID] UUIDString];
    fileName = [fileName stringByAppendingString:@"."];
    return [fileName stringByAppendingString:fileType];
}

+ (UIImage *)getUIImageFromInfo:(NSDictionary *)info
{
    UIImage *image = info[UIImagePickerControllerEditedImage];
    if (!image) {
        image = info[UIImagePickerControllerOriginalImage];
    }
    return image;
}

+ (NSURL *)getNSURLFromInfo:(NSDictionary *)info {
    if (@available(iOS 11.0, *)) {
        return info[UIImagePickerControllerImageURL];
    }
    else {
        return info[UIImagePickerControllerReferenceURL];
    }
}

//获取当前时间
- (NSString *)currentDateStr{
    NSDate *currentDate = [NSDate date];//获取当前时间，日期
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];// 创建一个时间格式化对象
    [dateFormatter setDateFormat:@"YYYYMMDDHHmmSS"];//设定时间格式,这里可以设置成自己需要的格式
    NSString *dateString = [dateFormatter stringFromDate:currentDate];//将时间转化成字符串
    return dateString;
}

@end

@implementation ImagePickerManager (UIImagePickerControllerDelegate)

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    dispatch_block_t dismissCompletionBlock = ^{
        NSMutableArray<NSDictionary *> *assets = [[NSMutableArray alloc] initWithCapacity:1];
        
        if ([info[UIImagePickerControllerMediaType] isEqualToString:(NSString *) kUTTypeImage]) {
            UIImage *image = [ImagePickerManager getUIImageFromInfo:info];
            NSString *fileName;
            
            if( [picker sourceType] == UIImagePickerControllerSourceTypeCamera ){
                fileName =[NSString stringWithFormat:@"%@.png",[self currentDateStr]];
            }else{
                NSURL *imageUrl = info[UIImagePickerControllerReferenceURL];
                PHFetchResult *result = [PHAsset fetchAssetsWithALAssetURLs:@[imageUrl] options:nil];
                PHAsset *phAsset = result.firstObject;
                fileName =[phAsset valueForKey:@"filename"];
            }
            [assets addObject:[self mapImageToAsset:image data:[ImagePickerUtils getImageData:image] originFileName:fileName]];
        } else {
            NSError *error;
            NSDictionary *asset = [self mapVideoToAsset:info[UIImagePickerControllerMediaURL] error:&error];
            if (asset == nil) {
                self.callback(@[@{@"errorCode": errOthers, @"errorMessage":  error.localizedFailureReason}]);
                return;
            }
            [assets addObject:asset];
        }
        
        NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
        response[@"assets"] = assets;
        self.callback(@[response]);
    };
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:dismissCompletionBlock];
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:^{
            self.callback(@[@{@"didCancel": @YES}]);
        }];
    });
}

@end

@implementation ImagePickerManager (presentationControllerDidDismiss)

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController
{
    self.callback(@[@{@"didCancel": @YES}]);
}

@end

#if __has_include(<PhotosUI/PHPicker.h>)
@implementation ImagePickerManager (PHPickerViewControllerDelegate)

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14))
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    if (results.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.callback(@[@{@"didCancel": @YES}]);
        });
        return;
    }
    
    dispatch_group_t completionGroup = dispatch_group_create();
    NSMutableArray<NSDictionary *> *assets = [[NSMutableArray alloc] initWithCapacity:results.count];
    
    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        dispatch_group_enter(completionGroup);
        
        if ([provider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeImage]) {
            [provider loadFileRepresentationForTypeIdentifier:(NSString *)kUTTypeImage completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                NSData *data = [NSData dataWithContentsOfURL:url];
                UIImage *image = [UIImage imageWithData:data];
                NSString *fileName = [url lastPathComponent];
                [assets addObject:[self mapImageToAsset:image data:data originFileName:fileName]];
                dispatch_group_leave(completionGroup);
            }];
        }
        
        if ([provider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie]) {
            [provider loadFileRepresentationForTypeIdentifier:(NSString *)kUTTypeMovie completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                [assets addObject:[self mapVideoToAsset:url error:nil]];
                dispatch_group_leave(completionGroup);
            }];
        }
    }
    
    dispatch_group_notify(completionGroup, dispatch_get_main_queue(), ^{
        //  mapVideoToAsset can fail and return nil.
        for (NSDictionary *asset in assets) {
            if (nil == asset) {
                self.callback(@[@{@"errorCode": errOthers}]);
                return;
            }
        }
        
        NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
        [response setObject:assets forKey:@"assets"];
        
        self.callback(@[response]);
    });
}

@end
#endif
