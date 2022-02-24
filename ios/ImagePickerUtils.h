#import "ImagePickerManager.h"

@class PHPickerConfiguration;

@interface ImagePickerUtils : NSObject

+ (BOOL)isSimulator;

+ (void)setupPickerFromOptions:(UIImagePickerController *)picker options:(NSDictionary *)options target:(RNImagePickerTarget)target;

+ (PHPickerConfiguration *)makeConfigurationFromOptions:(NSDictionary *)options target:(RNImagePickerTarget)target API_AVAILABLE(ios(14));

+ (NSString*)getFileType:(NSData*)imageData;

+ (UIImage*)resizeImage:(UIImage*)image maxWidth:(float)maxWidth maxHeight:(float)maxHeight;

+ (NSString *) getFileTypeFromUrl:(NSURL *)url;

+ (NSData *) getImageData:(UIImage *)image;

+(NSString * ) getVideoCommandPath:(NSString *) path outPath:(NSString *)outPath width:(int) width height:(int)height rotate:(int) rotat;

+(NSString * ) getThumbCommandPath:(NSString *) path outPath:(NSString *)outPath screenshotWidth:(int) screenshotWidth;

+(NSString * ) getThumbCommandSpecPath:(NSString *) path outPath:(NSString *)outPath width:(int) width height:(int)height rotate:(int) rotate;

+(NSDictionary * )getMediaInfoPath:(NSString *)path;

+(NSDictionary * ) getScreenshotInfoOriginWidth:(int)width originHeight:(int)height OriginRotate:(int) rotate fileName:(NSString *) fileName;

+(void) clearCache:(NSString *) outPath;
    
@end
