//
//  main.mm
//  fm2-objc
//
//  Created by Rick Rothenberg on 2/4/23.
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Metal/Metal.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        NSError* error = nil;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        id<MTLLibrary> library = [device newDefaultLibrary];
        id<MTLFunction> gradient = [library newFunctionWithName:@"gradient"];
        id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction: gradient error:&error];
        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        id<MTLBuffer> buffer = [device newBufferWithLength: 3000*3000*16 options: MTLResourceStorageModeShared];
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
        [computeEncoder setComputePipelineState:pso];
        [computeEncoder setBuffer:buffer offset:0 atIndex:0];
        MTLSize gridSize = MTLSizeMake(3000, 3000, 1);
        MTLSize threadgroupSize = MTLSizeMake(pso.maxTotalThreadsPerThreadgroup, 1, 1);
        [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [computeEncoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        struct pixel {
            float r;
            float g;
            float b;
            float a;
        };
        
        static const size_t kComponentsPerPixel = 4;
        static const size_t kBytesPerPixel = sizeof(pixel);

        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
                
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer.contents, 3000*3000*16, NULL);

        CGImageRef imageRef =
        CGImageCreate(3000,
                      3000,
                      kBytesPerPixel/kComponentsPerPixel * 8,
                      kBytesPerPixel * 8,
                      kBytesPerPixel * 3000,
                      rgb,
                      kCGImageAlphaNoneSkipLast | kCGBitmapFloatComponents | kCGBitmapByteOrder32Little,
                      provider,
                      NULL,
                      false,
                      kCGRenderingIntentDefault);
        CFURLRef path = CFURLCreateWithString(NULL, CFStringCreateWithCString(NULL, "file:/Users/rrothenb/dev/fm2-objc/fm2-objc/blech.exr", kCFStringEncodingUTF8), NULL);
        CGImageDestinationRef myImageDest = CGImageDestinationCreateWithURL(path , CFStringCreateWithCString(NULL, "com.ilm.openexr-image", kCFStringEncodingUTF8), 1, NULL);
        CGImageDestinationAddImage(myImageDest, imageRef, nil);
        bool success = CGImageDestinationFinalize(myImageDest);
        CFRelease(myImageDest);
    }
    return 0;
}
