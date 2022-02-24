#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RNImagePickerTarget) {
  camera = 1,
  library
};

@interface ImagePickerManager : RCTEventEmitter <RCTBridgeModule>

@end
