#import "ImagePickerUtils.h"
#import <CoreServices/CoreServices.h>
#import <PhotosUI/PhotosUI.h>
#import <ffmpegkit/FFmpegKit.h>
#import <AVFoundation/AVFoundation.h>

@implementation ImagePickerUtils

+ (void) setupPickerFromOptions:(UIImagePickerController *)picker options:(NSDictionary *)options target:(RNImagePickerTarget)target
{
    if ([[options objectForKey:@"mediaType"] isEqualToString:@"video"]) {
        //        if ([[options objectForKey:@"videoQuality"] isEqualToString:@"high"]) {
        //            picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
        //        }
        //        else if ([[options objectForKey:@"videoQuality"] isEqualToString:@"low"]) {
        //            picker.videoQuality = UIImagePickerControllerQualityTypeLow;
        //        }
        //        else {
        //            picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
        //        }
        picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    }
    
    if (target == camera) {
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        
        if (options[@"durationLimit"] > 0) {
            picker.videoMaximumDuration = [options[@"durationLimit"] doubleValue];
        }
        
        if ([options[@"cameraType"] isEqualToString:@"front"]) {
            picker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
        } else {
            picker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
        }
    } else {
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    
    if ([options[@"mediaType"] isEqualToString:@"video"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    } else if ([options[@"mediaType"] isEqualToString:@"photo"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeImage];
    } else if ((target == library) && ([options[@"mediaType"] isEqualToString:@"mixed"])) {
        picker.mediaTypes = @[(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie];
    }
    
    picker.modalPresentationStyle = UIModalPresentationCurrentContext;
}

+ (PHPickerConfiguration *)makeConfigurationFromOptions:(NSDictionary *)options target:(RNImagePickerTarget)target API_AVAILABLE(ios(14))
{
#if __has_include(<PhotosUI/PHPicker.h>)
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    configuration.selectionLimit = [options[@"selectionLimit"] integerValue];
    
    if ([options[@"mediaType"] isEqualToString:@"video"]) {
        configuration.filter = [PHPickerFilter videosFilter];
        
        //        if ([[options objectForKey:@"mediaType"] isEqualToString:@"video"]) {
        //
        //            if ([[options objectForKey:@"videoQuality"] isEqualToString:@"high"]) {
        //                picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
        //            }
        //            else if ([[options objectForKey:@"videoQuality"] isEqualToString:@"low"]) {
        //                picker.videoQuality = UIImagePickerControllerQualityTypeLow;
        //            }
        //            else {
        //                picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
        //            }
        //        }
        
    } else if ([options[@"mediaType"] isEqualToString:@"photo"]) {
        configuration.filter = [PHPickerFilter imagesFilter];
    } else if ((target == library) && ([options[@"mediaType"] isEqualToString:@"mixed"])) {
        configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters: @[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
    }
    return configuration;
#else
    return nil;
#endif
}


+ (BOOL) isSimulator
{
#if TARGET_OS_SIMULATOR
    return YES;
#endif
    return NO;
}

+ (NSString*) getFileType:(NSData *)imageData
{
    const uint8_t firstByteJpg = 0xFF;
    const uint8_t firstBytePng = 0x89;
    const uint8_t firstByteGif = 0x47;
    
    uint8_t firstByte;
    [imageData getBytes:&firstByte length:1];
    switch (firstByte) {
        case firstByteJpg:
            return @"jpg";
        case firstBytePng:
            return @"png";
        case firstByteGif:
            return @"gif";
        default:
            return @"jpg";
    }
}

+ (NSString *) getFileTypeFromUrl:(NSURL *)url {
    CFStringRef fileExtension = (__bridge CFStringRef)[url pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    return (__bridge_transfer NSString *)MIMEType;
}

+ (UIImage*)resizeImage:(UIImage*)image maxWidth:(float)maxWidth maxHeight:(float)maxHeight
{
    if ((maxWidth == 0) || (maxHeight == 0)) {
        return image;
    }
    
    if (image.size.width <= maxWidth && image.size.height <= maxHeight) {
        return image;
    }
    
    CGSize newSize = CGSizeMake(image.size.width, image.size.height);
    if (maxWidth < newSize.width) {
        newSize = CGSizeMake(maxWidth, (maxWidth / newSize.width) * newSize.height);
    }
    if (maxHeight < newSize.height) {
        newSize = CGSizeMake((maxHeight / newSize.height) * newSize.width, maxHeight);
    }
    
    newSize.width = (int)newSize.width;
    newSize.height = (int)newSize.height;
    
    UIGraphicsBeginImageContext(newSize);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    if (newImage == nil) {
        NSLog(@"could not scale image");
    }
    UIGraphicsEndImageContext();
    
    return newImage;
}

// get image data by imageIO api
+ (NSData * )getImageData:(UIImage *)image{
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceShouldCache : @NO,
                              (__bridge NSString *)kCGImageSourceShouldCacheImmediately : @NO
    };
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destRef = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, kUTTypeJPEG, 1, (__bridge CFDictionaryRef)options);
    CGImageDestinationAddImage(destRef, image.CGImage, (__bridge CFDictionaryRef)options);
    CGImageDestinationFinalize(destRef);
    CFRelease(destRef);
    return data;
}


// get video command
+(NSString * ) getVideoCommandPath:(NSString *) path outPath:(NSString *)outPath width:(int) width height:(int)height rotate:(int) rotate{
    
    NSString *scaleStr = @"";
    
    if (width > height) {
        if (rotate == 0 || rotate == 180 ||  rotate == -180) {
            scaleStr = @"scale=-1:720";
        } else {
            scaleStr = @"scale=-1:1280";
        }
    } else {
        if (rotate == 0 || rotate == 180 ||  rotate == -180) {
            scaleStr = @"scale=720:-1";
        } else {
            scaleStr = @"scale=1280:-1";
        }
    }
    
    NSString * command =  [NSString stringWithFormat:@"-i %@ -b 2097k -r 30 -vcodec mpeg4 -vf %@ -preset superfast %@",path,scaleStr,outPath];
    
    return  command;
}


// get thumb command
+(NSString * ) getThumbCommandPath:(NSString *) path outPath:(NSString *)outPath screenshotWidth:(int) screenshotWidth{
    
    NSString *scaleStr = [NSString stringWithFormat:@"scale=%d:-1",screenshotWidth];
    
    NSString * command = [NSString stringWithFormat:@"-i %@ -frames:v 1 -vf %@ -q:v 3 -preset superfast %@",path,scaleStr,outPath];
    
    return  command;
}

// get special thumb command
+(NSString * ) getThumbCommandSpecPath:(NSString *) path outPath:(NSString *)outPath width:(int) width height:(int)height rotate:(int) rotate{
    
    NSString *sizeStr = @"";
    
    if (width >= 1280 || height >= 1280) {
        
        if (width > height) {
            if (rotate == 0 || rotate == 180 ||  rotate == -180) {
                int w = width * 720 / height;
                sizeStr = [NSString stringWithFormat:@"%dx720",w];
            } else {
                int h = width * 720 / height;
                sizeStr = [NSString stringWithFormat:@"720x%d",h];
            }
        } else {
            if (rotate == 0 || rotate == 180 ||  rotate == -180) {
                int h = height * 720 / width;
                sizeStr = [NSString stringWithFormat:@"720x%d",h];
            } else {
                int w = height * 720 / width;
                sizeStr = [NSString stringWithFormat:@"%dx720",w];
            }
        }
    } else {
        sizeStr = [NSString stringWithFormat:@"%dx%d",width,height];
    }
    
    NSString * command = [NSString stringWithFormat:@"-i %@ -vf select='eq(pict_type\\,I)' -frames:v 1 -vsync vfr -s %@ -f image2 -preset superfast %@",path,sizeStr,outPath];
    
    return command;
}

+(NSDictionary * )getMediaInfoPath:(NSString *)path {
    MediaInformationSession *session = [FFprobeKit getMediaInformation:path];
    MediaInformation *mediaInfo = [session getMediaInformation];
    
    NSDictionary * allPro = mediaInfo.getAllProperties;
    NSDictionary * infoStreams = allPro[@"streams"];

    NSMutableDictionary * infoDic = [[NSMutableDictionary alloc] init];
    
    infoDic[@"size"] = mediaInfo.getSize;
    infoDic[@"bitrate"] = mediaInfo.getBitrate;
    infoDic[@"duration"] = mediaInfo.getDuration;
    
    NSString * nameStr = mediaInfo.getFilename;
    NSArray * nameStrArray = [nameStr componentsSeparatedByString:@"/"];
    infoDic[@"filename"] = [nameStrArray lastObject];
    
    NSString * rotation = @"0";
    NSString * width = @"";
    NSString * height = @"";
    
    for (NSDictionary * item in infoStreams) {
        if (item[@"width"]) {
            width = item[@"width"];
            break;
        }
    }
    
    for (NSDictionary * item in infoStreams) {
        if (item[@"height"]) {
            height = item[@"height"];
            break;
        }
    }
    
    for (NSDictionary * item in infoStreams) {
        if (item[@"side_data_list"]) {
            NSDictionary * side_data_list = item[@"side_data_list"];
            for (NSDictionary * item2 in side_data_list) {
                if (item2[@"rotation"]) {
                    rotation = item2[@"rotation"];
                    break;
                }
            }
            break;
        }
    }
    
    infoDic[@"width"] = width;
    infoDic[@"height"] = height;
    infoDic[@"rotation"] = rotation;
    
    return infoDic;
}

// get thumb info by origin info
+(NSDictionary * ) getScreenshotInfoOriginWidth:(int)width originHeight:(int)height OriginRotate:(int) rotate fileName:(NSString *) fileName{

    int screenshotWidth = width;
    int screenshotHeight = height;
    
    if (width >= 1280 || height >= 1280) {
        if (width > height) {
            if (rotate == 0 || rotate == 180 ||  rotate == -180) {
                int w = width * 720 / height;
                screenshotWidth = w;
                screenshotHeight = 720;
            } else {
                int h = width * 720 / height;
                screenshotWidth = 720;
                screenshotHeight = h;
            }
        } else {
            if (rotate == 0 || rotate == 180 ||  rotate == -180) {
                int h = height * 720 / width;
                screenshotWidth = 720;
                screenshotHeight = h;
            } else {
                int w = height * 720 / width;
                screenshotWidth = w;
                screenshotHeight = 720;
            }
        }
    } else {
        screenshotWidth = width;
        screenshotHeight = height;
    }
    
    NSArray * fileNameArr = [fileName componentsSeparatedByString:@"."];
    
    NSString * screenshotPath = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"thumb_%@.png",fileNameArr[0]]];
    
    return @{@"screenshotWidth":@(screenshotWidth),@"screenshotHeight":@(screenshotHeight),@"screenshotPath":screenshotPath};
}

+(void) clearCache:(NSString *) outPath{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:outPath]) {
        [fileManager removeItemAtURL:[NSURL fileURLWithPath:outPath] error:nil];
    }
}


@end
