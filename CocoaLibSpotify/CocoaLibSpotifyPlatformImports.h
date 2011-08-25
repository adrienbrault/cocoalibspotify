#if TARGET_OS_IPHONE
#import "api.h"
#import <UIKit/UIKit.h>
#define SPPlatformNativeImage UIImage
#else
#import <Cocoa/Cocoa.h>
#import <libspotify/api.h>
#define SPPlatformNativeImage NSImage
#endif