#include <metal_stdlib>
using namespace metal;

constant uint height = 3000;
constant uint width = 3000;

kernel void gradient(
                device float3  *out,
                uint2 id [[ thread_position_in_grid ]]) {
                    uint row = id.x;
                    uint col = id.y;
                    uint index = row*3000 + col;
                    out[index].r = 1.0*row/height;
                    out[index].b = 1.0*col/width;
                    out[index].g = 1.0*row/height*col/width;
}

