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
#import "Renderer.h"
#import "Transforms.h"
#import "ShaderTypes.h"
#import "Scene.h"
#import <simd/simd.h>

using namespace simd;


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<id <MTLDevice>> *devices = MTLCopyAllDevices();
        id <MTLDevice> device = devices[0];
        NSLog(@"Metal device: %@", device.name);
        id <MTLLibrary> library = [device newDefaultLibrary];
        id <MTLCommandQueue> queue = [device newCommandQueue];
        NSLog(@"Metal queue: %@", queue.description);
        NSError *error = NULL;
        
        // Create compute pipelines will will execute code on the GPU
        MTLComputePipelineDescriptor *computeDescriptor = [[MTLComputePipelineDescriptor alloc] init];

        // Set to YES to allow compiler to make certain optimizations
        computeDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = YES;
        
        // Generates rays according to view/projection matrices
        computeDescriptor.computeFunction = [library newFunctionWithName:@"rayKernel"];
        
        id <MTLComputePipelineState> rayPipeline = [device newComputePipelineStateWithDescriptor:computeDescriptor
                                                              options:0
                                                           reflection:nil
                                                                error:&error];
        NSLog(@"Metal rayPipeline: %@", rayPipeline.description);
        if (!rayPipeline)
            NSLog(@"Failed to create pipeline state: %@", error);
            
        // Consumes ray/scene intersection test results to perform shading
        computeDescriptor.computeFunction = [library newFunctionWithName:@"shadeKernel"];
        
        id <MTLComputePipelineState> shadePipeline = [device newComputePipelineStateWithDescriptor:computeDescriptor
                                                              options:0
                                                           reflection:nil
                                                                error:&error];
        
        if (!shadePipeline)
            NSLog(@"Failed to create pipeline state: %@", error);
        
        // Consumes shadow ray intersection tests to update the output image
        computeDescriptor.computeFunction = [library newFunctionWithName:@"shadowKernel"];
        
        id <MTLComputePipelineState> shadowPipeline = [device newComputePipelineStateWithDescriptor:computeDescriptor
                                                                 options:0
                                                              reflection:nil
                                                                   error:&error];
        
        if (!shadowPipeline)
            NSLog(@"Failed to create pipeline state: %@", error);

        // Averages the current frame's output image with all previous frames
        computeDescriptor.computeFunction = [library newFunctionWithName:@"accumulateKernel"];
        
        id <MTLComputePipelineState> accumulatePipeline = [device newComputePipelineStateWithDescriptor:computeDescriptor
                                                                     options:0
                                                                  reflection:nil
                                                                       error:&error];
        
        if (!accumulatePipeline)
            NSLog(@"Failed to create pipeline state: %@", error);

        // Copies rendered scene into the MTKView
        MTLRenderPipelineDescriptor *renderDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        renderDescriptor.vertexFunction = [library newFunctionWithName:@"copyVertex"];
        renderDescriptor.fragmentFunction = [library newFunctionWithName:@"copyFragment"];

        id <MTLRenderPipelineState> copyPipeline = [device newRenderPipelineStateWithDescriptor:renderDescriptor error:&error];
        
        if (!copyPipeline)
            NSLog(@"Failed to create pipeline state, error %@", error);

        float4x4 transform = matrix4x4_translation(0.0f, 1.0f, 0.0f) * matrix4x4_scale(0.5f, 1.98f, 0.5f);
        
        // Light source
        createCube(FACE_MASK_POSITIVE_Y, vector3(1.0f, 1.0f, 1.0f), transform, true,
                   TRIANGLE_MASK_LIGHT);
        
        transform = matrix4x4_translation(0.0f, 1.0f, 0.0f) * matrix4x4_scale(2.0f, 2.0f, 2.0f);
        
        // Top, bottom, and back walls
        createCube(FACE_MASK_NEGATIVE_Y | FACE_MASK_POSITIVE_Y | FACE_MASK_NEGATIVE_Z, vector3(0.725f, 0.71f, 0.68f), transform, true, TRIANGLE_MASK_GEOMETRY);
        
        // Left wall
        createCube(FACE_MASK_NEGATIVE_X, vector3(0.63f, 0.065f, 0.05f), transform, true,
                   TRIANGLE_MASK_GEOMETRY);
        
        // Right wall
        createCube(FACE_MASK_POSITIVE_X, vector3(0.14f, 0.45f, 0.091f), transform, true,
                   TRIANGLE_MASK_GEOMETRY);
        
        transform = matrix4x4_translation(0.3275f, 0.3f, 0.3725f) *
        matrix4x4_rotation(-0.3f, vector3(0.0f, 1.0f, 0.0f)) *
        matrix4x4_scale(0.6f, 0.6f, 0.6f);
        
        // Short box
        createCube(FACE_MASK_ALL, vector3(0.725f, 0.71f, 0.68f), transform, false,
                   TRIANGLE_MASK_GEOMETRY);
        
        transform = matrix4x4_translation(-0.335f, 0.6f, -0.29f) *
        matrix4x4_rotation(0.3f, vector3(0.0f, 1.0f, 0.0f)) *
        matrix4x4_scale(0.6f, 1.2f, 0.6f);
        
        // Tall box
        createCube(FACE_MASK_ALL, vector3(0.725f, 0.71f, 0.68f), transform, false,
                   TRIANGLE_MASK_GEOMETRY);
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
        
        pixel image[height][width];
        
        for (int row = 0;row < height;row++) {
            for (int col = 0;col < width;col++) {
                image[col][row].r = 1.0*row/height;
                image[col][row].b = 1.0*col/width;
                image[col][row].g = 1.0*row/height*col/width;
            }
        }

        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, image, sizeof(image), NULL);

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
        CFURLRef path = CFURLCreateWithString(NULL, CFStringCreateWithCString(NULL, "file:/Users/rrothenb/dev/fm2-objc/blech.exr", kCFStringEncodingUTF8), NULL);
        CGImageDestinationRef myImageDest = CGImageDestinationCreateWithURL(path , CFStringCreateWithCString(NULL, "com.ilm.openexr-image", kCFStringEncodingUTF8), 1, NULL);
        CGImageDestinationAddImage(myImageDest, imageRef, nil);
        bool success = CGImageDestinationFinalize(myImageDest);
        CFRelease(myImageDest);
    }
    return 0;
}
