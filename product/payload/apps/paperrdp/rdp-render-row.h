#pragma once
#include <algorithm>
#include <cstdint>
#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

namespace rdp_render {
struct Damage { int left,right; };
inline uint16_t pixel(const uint8_t* p) {
    const unsigned v=(77*p[2]+150*p[1]+29*p[0])>>8;
    return uint16_t(((v>>3)<<11)|((v>>2)<<5)|(v>>3));
}
// Exact BGRA -> weighted gray -> RGB565. No reads beyond count, including
// partial edge tiles. Alpha deliberately ignored, as in the scalar renderer.
inline Damage contiguous(const uint8_t* src,uint16_t* dst,int count) {
    Damage damage{count,0};int i=0;
#ifdef __ARM_NEON
    for(;i+8<=count;i+=8) {
        const auto bgra=vld4_u8(src+i*4);
        auto sum=vmull_u8(bgra.val[2],vdup_n_u8(77));
        sum=vmlal_u8(sum,bgra.val[1],vdup_n_u8(150));
        sum=vmlal_u8(sum,bgra.val[0],vdup_n_u8(29));
        const auto gray=vshrq_n_u16(sum,8);
        const auto value=vorrq_u16(vorrq_u16(vshlq_n_u16(vshrq_n_u16(gray,3),11),
                                           vshlq_n_u16(vshrq_n_u16(gray,2),5)),vshrq_n_u16(gray,3));
        const auto old=vld1q_u16(dst+i);
        const auto equal=vreinterpretq_u32_u16(vceqq_u16(old,value));
        const uint32_t e0=vgetq_lane_u32(equal,0),e1=vgetq_lane_u32(equal,1),
                       e2=vgetq_lane_u32(equal,2),e3=vgetq_lane_u32(equal,3);
        if((e0&e1&e2&e3)==0xffffffffu)continue;
        if((e0|e1|e2|e3)==0) {damage.left=std::min(damage.left,i);damage.right=i+8;}
        else {
            uint16_t before[8],after[8];vst1q_u16(before,old);vst1q_u16(after,value);
            for(int lane=0;lane<8;++lane)if(before[lane]!=after[lane]) {
                damage.left=std::min(damage.left,i+lane);damage.right=i+lane+1;
            }
        }
        vst1q_u16(dst+i,value);
    }
#endif
    for(;i<count;++i) {
        const auto value=pixel(src+i*4);
        if(dst[i]!=value){dst[i]=value;damage.left=std::min(damage.left,i);damage.right=i+1;}
    }
    return damage;
}
}
