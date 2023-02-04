//
//  main.mm
//  fm2-objc
//
//  Created by Rick Rothenberg on 2/4/23.
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreFoundation/CoreFoundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        struct pixel {
            float r;
            float g;
            float b;
        };
        
        static const size_t kComponentsPerPixel = 3;
        static const size_t kBytesPerPixel = sizeof(pixel);

        static const int height = 800;
        static const int width = 800;

        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CFShow(rgb);
        
        pixel image[height][width];
        
        for (int row = 0;row < height;row++) {
            for (int col = 0;col < width;col++) {
                image[col][row].r = 1.0*row/height;
                image[col][row].b = 1.0*col/width;
                image[col][row].g = 1.0*row/height*col/width;
            }
        }

        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, image, sizeof(image), NULL);
        CFShow(provider);

        CGImageRef imageRef =
        CGImageCreate(width,
                      height,
                      kBytesPerPixel/kComponentsPerPixel * 8,
                      kBytesPerPixel * 8,
                      kBytesPerPixel * width,
                      rgb,
                      kCGImageAlphaNone | kCGBitmapFloatComponents | kCGBitmapByteOrder32Little,
                      provider,
                      NULL,
                      false,
                      kCGRenderingIntentDefault);
        CFShow(imageRef);
        CFURLRef path = CFURLCreateWithString(NULL, CFStringCreateWithCString(NULL, "file:/Users/rrothenb/dev/fm2-objc/blech.exr", kCFStringEncodingUTF8), NULL);
        CFShow(path);
        CGImageDestinationRef myImageDest = CGImageDestinationCreateWithURL(path , CFStringCreateWithCString(NULL, "com.ilm.openexr-image", kCFStringEncodingUTF8), 1, NULL);
        CFShow(myImageDest);
        CGImageDestinationAddImage(myImageDest, imageRef, nil);
        CFShow(myImageDest);
        bool success = CGImageDestinationFinalize(myImageDest);
        CFRelease(myImageDest);
        NSLog(@"Hello, World!");
    }
    return 0;
}
