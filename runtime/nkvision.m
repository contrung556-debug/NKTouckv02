// NKTouch v0.7.9 Vision Core — immutable per-script screenshot frames.
// Built into the existing statically linked Lua 5.4 runtime; no daemon hooks.
// Uses a single JPEG screenshot delivered by the retained NKTouch screenshot API.
// Copyright (c) NKTouch contributors, GPL-3.0-or-later.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <Vision/Vision.h>
#import <mach/mach.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "lua.h"
#include "lauxlib.h"

#define NV_MT "NKTouch.VisionFrame"
#define NV_MAX_FILE (32u * 1024u * 1024u)
#define NV_MAX_BITMAP (96u * 1024u * 1024u)
#define NV_MAX_TEMPLATE (8u * 1024u * 1024u)
#define NV_MAX_MATCH_EVAL 50000u

typedef struct {
    uint8_t *rgba;
    uint8_t *gray;
    size_t w, h, stride;
    CFDataRef jpeg;
    CGImageRef image;
    int released;
} NVFrame;

static int nv_error(lua_State *L, const char *message, const char *code) {
    lua_pushnil(L);
    lua_pushstring(L, message);
    lua_pushstring(L, code);
    return 3;
}
static void nv_release(NVFrame *f) {
    if (f->rgba) { free(f->rgba); f->rgba = NULL; }
    if (f->gray) { free(f->gray); f->gray = NULL; }
    if (f->jpeg) { CFRelease(f->jpeg); f->jpeg = NULL; }
    if (f->image) { CGImageRelease(f->image); f->image = NULL; }
    f->released = 1;
}
static NVFrame *nv_frame(lua_State *L, int arg) {
    return (NVFrame *)luaL_checkudata(L, arg, NV_MT);
}
static int nv_live(lua_State *L, NVFrame **out) {
    *out = nv_frame(L, 1);
    return (*out)->released ? 0 : 1;
}
static int nv_gc(lua_State *L) {
    NVFrame *f = nv_frame(L, 1);
    nv_release(f);
    return 0;
}
static int nv_close(lua_State *L) {
    NVFrame *f = nv_frame(L, 1);
    nv_release(f);
    lua_pushboolean(L, 1);
    return 1;
}
static int nv_number(lua_State *L, int index, lua_Integer lower, lua_Integer upper,
                     lua_Integer *result) {
    if (!lua_isinteger(L,index)) return 0;
    lua_Integer n=lua_tointeger(L,index);
    if (n<lower || n>upper) return 0;
    *result=n;
    return 1;
}
static int nv_decoded(CGImageRef image, uint8_t **out, size_t *outW,
                      size_t *outH, size_t *outStride, size_t maxBytes) {
    if (!image) return 0;
    size_t w=CGImageGetWidth(image), h=CGImageGetHeight(image);
    if (!w || !h || w > 10000 || h > 10000 || w > SIZE_MAX/4) return 0;
    size_t stride=w*4;
    if (h > SIZE_MAX/stride || stride*h > maxBytes) return 0;
    uint8_t *pixels=(uint8_t *)calloc(h,stride);
    if (!pixels) return 0;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    if (!space) { free(pixels); return 0; }
    CGContextRef ctx=CGBitmapContextCreate(pixels,w,h,8,stride,space,
                       kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) { free(pixels); return 0; }
    CGContextSetInterpolationQuality(ctx,kCGInterpolationNone);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),image);
    CGContextRelease(ctx);
    *out=pixels; *outW=w; *outH=h; *outStride=stride;
    return 1;
}
// Decode full RGBA pixels only when a pixel/color operation requires them.
// OCR-only frames retain a CGImage but avoid ~4 MiB of decoded RGB at
// 750x1334. Frame.close() still owns/frees the buffer if it was allocated.
static int nv_ensure_rgba(NVFrame *f) {
    if (!f || f->released || !f->image) return 0;
    if (f->rgba) return 1;
    uint8_t *rgba=NULL;size_t w=0,h=0,stride=0;
    if (!nv_decoded(f->image,&rgba,&w,&h,&stride,NV_MAX_BITMAP)) return 0;
    if (w!=f->w || h!=f->h || stride!=f->stride) {
        free(rgba);
        return 0;
    }
    f->rgba=rgba;
    return 1;
}
static uint8_t nv_gray(uint8_t r,uint8_t g,uint8_t b) {
    return (uint8_t)((77u*r+150u*g+29u*b+128u)>>8);
}
// Decode grayscale ONLY for template matching. Most scripts call
// getColor/ocr and never findImage; their snapshot does not need a
// permanent second full-screen bitmap (e.g. ~1 MiB at 750x1334).
// Frame owns this allocation; close/__gc releases it even on errors.
static int nv_ensure_gray(NVFrame *f) {
    if (!f || f->released) return 0;
    if (f->gray) return 1;
    if (!nv_ensure_rgba(f)) return 0;
    if (!f->w || !f->h || f->w > SIZE_MAX/f->h) return 0;
    size_t bytes=f->w*f->h;
    if (bytes>NV_MAX_BITMAP) return 0;
    uint8_t *gray=(uint8_t *)malloc(bytes);
    if (!gray) return 0;
    for (size_t y=0;y<f->h;y++)
        for (size_t x=0;x<f->w;x++) {
            const uint8_t *p=f->rgba+y*f->stride+x*4;
            gray[y*f->w+x]=nv_gray(p[0],p[1],p[2]);
        }
    f->gray=gray;
    return 1;
}
// Reserve a collision-resistant per-capture filename with mode 0600.
// Lua must remove it even on failed screenshot, before returning to caller.
static int nv_temp_path(lua_State *L) {
    char path[]="/var/mobile/Library/NKTouch/vision-XXXXXX.jpg";
    int fd=mkstemps(path,4);
    if (fd<0) return nv_error(L,"cannot reserve temporary snapshot","FRAME_IO");
    close(fd);
    lua_pushstring(L,path);
    return 1;
}
static int nv_open(lua_State *L) {
    size_t len=0;
    const char *path=luaL_checklstring(L,1,&len);
    if (!len || len>1024 || memchr(path,'\0',len))
        return nv_error(L,"invalid frame path","INVALID");
    @autoreleasepool {
        NSString *name=[NSString stringWithUTF8String:path];
        if (!name) return nv_error(L,"invalid UTF-8 frame path","INVALID");
        NSDictionary *attr=[[NSFileManager defaultManager] attributesOfItemAtPath:name error:nil];
        unsigned long long size=[attr fileSize];
        if (!size || size>NV_MAX_FILE)
            return nv_error(L,"missing/oversized snapshot file","FRAME_IO");
        NSError *err=nil;
        NSData *data=[NSData dataWithContentsOfFile:name options:NSDataReadingMappedIfSafe error:&err];
        if (!data || ![data length])
            return nv_error(L,"snapshot read failed","FRAME_IO");
        CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
        if (!source) return nv_error(L,"invalid snapshot image","DECODE");
        CGImageRef img=CGImageSourceCreateImageAtIndex(source,0,NULL);
        CFRelease(source);
        if (!img) return nv_error(L,"cannot decode snapshot image","DECODE");
        size_t w=CGImageGetWidth(img),h=CGImageGetHeight(img);
        if (!w || !h || w>10000 || h>10000 ||
            w>SIZE_MAX/4 || h>SIZE_MAX/(w*4) ||
            w*4*h>NV_MAX_BITMAP) {
            CGImageRelease(img);
            return nv_error(L,"snapshot dimensions/bitmap memory invalid","MEMORY");
        }
        // The CGImage is sufficient for OCR. Full RGBA + gray are
        // allocated lazily by getColor/findColor/findImage when needed.
        // This avoids holding both decoded buffers for OCR-only scripts.
        size_t stride=w*4;
        NVFrame *f=(NVFrame *)lua_newuserdatauv(L,sizeof(NVFrame),0);
        memset(f,0,sizeof(*f));
        f->rgba=NULL; f->gray=NULL; f->w=w; f->h=h; f->stride=stride;
        f->jpeg=(CFDataRef)CFRetain((__bridge CFDataRef)data);
        f->image=img;
        luaL_getmetatable(L,NV_MT);
        lua_setmetatable(L,-2);
        return 1;
    }
}
static int nv_info(lua_State *L) {
    NVFrame *f=NULL;
    if (!nv_live(L,&f)) return nv_error(L,"snapshot already released","CLOSED");
    lua_createtable(L,0,5);
    lua_pushinteger(L,(lua_Integer)f->w); lua_setfield(L,-2,"width");
    lua_pushinteger(L,(lua_Integer)f->h); lua_setfield(L,-2,"height");
    lua_pushinteger(L,(lua_Integer)CFDataGetLength(f->jpeg)); lua_setfield(L,-2,"bytes");
    lua_pushliteral(L,"jpeg"); lua_setfield(L,-2,"format");
    lua_pushboolean(L,1); lua_setfield(L,-2,"immutable");
    // Count only allocations directly owned by NVFrame. This is NOT
    // total process RSS (CGImage and Vision frameworks may cache memory).
    lua_pushinteger(L,(lua_Integer)(f->rgba ? f->stride*f->h : 0));
    lua_setfield(L,-2,"rgba_bytes");
    lua_pushinteger(L,(lua_Integer)(f->gray ? f->w*f->h : 0));
    lua_setfield(L,-2,"gray_bytes");
    return 1;
}
static int nv_save(lua_State *L) {
    NVFrame *f=NULL;
    if (!nv_live(L,&f)) return nv_error(L,"snapshot already released","CLOSED");
    size_t len=0;
    const char *path=luaL_checklstring(L,2,&len);
    if (!len || len>1024 || memchr(path,'\0',len))
        return nv_error(L,"invalid save path","INVALID");
    @autoreleasepool {
        NSString *name=[NSString stringWithUTF8String:path];
        if (!name) return nv_error(L,"invalid UTF-8 save path","INVALID");
        NSData *d=(__bridge NSData *)f->jpeg;
        if (![d writeToFile:name atomically:YES])
            return nv_error(L,"failed to save frame","FRAME_IO");
        lua_pushboolean(L,1);
        return 1;
    }
}
static void nv_push_rgb(lua_State *L,size_t x,size_t y,const uint8_t *p,int includePos) {
    lua_createtable(L,0,includePos?6:4);
    if (includePos) {
        lua_pushinteger(L,(lua_Integer)x); lua_setfield(L,-2,"x");
        lua_pushinteger(L,(lua_Integer)y); lua_setfield(L,-2,"y");
    }
    lua_pushinteger(L,p[0]); lua_setfield(L,-2,"red");
    lua_pushinteger(L,p[1]); lua_setfield(L,-2,"green");
    lua_pushinteger(L,p[2]); lua_setfield(L,-2,"blue");
    lua_pushinteger(L,(lua_Integer)((uint32_t)p[0]*65536u+(uint32_t)p[1]*256u+p[2]));
    lua_setfield(L,-2,"packed");
}
static int nv_get_color(lua_State *L) {
    NVFrame *f=NULL;
    if (!nv_live(L,&f)) return nv_error(L,"snapshot already released","CLOSED");
    lua_Integer x=0,y=0;
    if (!nv_number(L,2,0,10000,&x) || !nv_number(L,3,0,10000,&y))
        return nv_error(L,"invalid pixel coordinate","INVALID");
    if ((size_t)x>=f->w || (size_t)y>=f->h)
        return nv_error(L,"pixel outside frame","OUT_OF_BOUNDS");
    if (!nv_ensure_rgba(f))
        return nv_error(L,"cannot allocate frame RGBA for pixel read","MEMORY");
    const uint8_t *p=f->rgba+(size_t)y*f->stride+(size_t)x*4;
    nv_push_rgb(L,(size_t)x,(size_t)y,p,0);
    return 1;
}
static int nv_find_color(lua_State *L) {
    NVFrame *f=NULL;
    if (!nv_live(L,&f)) return nv_error(L,"snapshot already released","CLOSED");
    lua_Integer v[11]={0};
    for (int i=0;i<10;i++) {
        lua_Integer max=(i>=4)?255:10000;
        if (!nv_number(L,i+2,0,max,&v[i]))
            return nv_error(L,"invalid color search value","INVALID");
    }
    if (!lua_isnoneornil(L,12) && !nv_number(L,12,0,1000,&v[10]))
        return nv_error(L,"invalid pixel skip","INVALID");
    if (v[4]>v[5] || v[6]>v[7] || v[8]>v[9])
        return nv_error(L,"min RGB exceeds max RGB","INVALID");
    size_t x=(size_t)v[0], y=(size_t)v[1], w=(size_t)v[2], h=(size_t)v[3];
    if (x>=f->w || y>=f->h)
        return nv_error(L,"color search outside frame","OUT_OF_BOUNDS");
    if (!w || w>f->w-x) w=f->w-x;
    if (!h || h>f->h-y) h=f->h-y;
    if (!nv_ensure_rgba(f))
        return nv_error(L,"cannot allocate frame RGBA for color search","MEMORY");
    size_t inc=(size_t)v[10]+1;
    for (size_t row=y;row<y+h;row+=inc)
        for (size_t col=x;col<x+w;col+=inc) {
            const uint8_t *p=f->rgba+row*f->stride+col*4;
            if (p[0]>=v[4] && p[0]<=v[5] &&
                p[1]>=v[6] && p[1]<=v[7] &&
                p[2]>=v[8] && p[2]<=v[9]) {
                nv_push_rgb(L,col,row,p,1);
                return 1;
            }
        }
    return nv_error(L,"color not found in captured frame","NOT_FOUND");
}
// Do not include recognized text in native diagnostics. Limit error text
// to prevent private paths or arbitrary framework output from flooding logs.
static NSString *nv_ocr_failure_detail(NSError *err, NSException *exception) {
    if (exception) {
        return [NSString stringWithFormat:@"exception=%@",exception.name ?: @"unknown"];
    }
    if (!err) return @"error=unavailable";
    NSString *description=err.localizedDescription ?: @"";
    description=[description stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    description=[description stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    if (description.length>160) description=[description substringToIndex:160];
    NSError *inner=err.userInfo[NSUnderlyingErrorKey];
    if (inner) {
        return [NSString stringWithFormat:@"%@:%ld underlying=%@:%ld %@",
            err.domain ?: @"unknown",(long)err.code,
            inner.domain ?: @"unknown",(long)inner.code,description];
    }
    return [NSString stringWithFormat:@"%@:%ld %@",
        err.domain ?: @"unknown",(long)err.code,description];
}
static int nv_ocr(lua_State *L) {
    NVFrame *f=NULL;
    if (!nv_live(L,&f)) return nv_error(L,"snapshot already released","CLOSED");
    lua_Integer x=0,y=0,w=0,h=0;
    if (!nv_number(L,2,0,10000,&x) || !nv_number(L,3,0,10000,&y) ||
        !nv_number(L,4,1,10000,&w) || !nv_number(L,5,1,10000,&h))
        return nv_error(L,"OCR rectangle must have positive integer dimensions","INVALID");
    if ((size_t)x>=f->w || (size_t)y>=f->h ||
        (size_t)w>f->w-(size_t)x || (size_t)h>f->h-(size_t)y)
        return nv_error(L,"OCR rectangle outside frame","OUT_OF_BOUNDS");
    size_t len=0;
    const char *language=luaL_optlstring(L,6,"",&len);
    if (len>64 || memchr(language,'\0',len))
        return nv_error(L,"invalid OCR languages","INVALID");
    @autoreleasepool {
        CGImageRef crop=CGImageCreateWithImageInRect(f->image,
            CGRectMake((CGFloat)x,(CGFloat)y,(CGFloat)w,(CGFloat)h));
        if (!crop) return nv_error(L,"cannot crop frame for OCR","DECODE");
        // The established live OCR backend uses a CIImage + Revision 2.
        // Try that on the existing immutable frame first; never recapture.
        CIImage *ciImage=[[CIImage alloc] initWithCGImage:crop];
        VNRecognizeTextRequest *req=[[VNRecognizeTextRequest alloc]init];
        req.recognitionLevel=VNRequestTextRecognitionLevelAccurate;
        req.usesLanguageCorrection=YES;
        if (@available(iOS 14.0, *)) req.revision=2;
        NSError *primaryError=nil;
        NSException *primaryException=nil;
        BOOL success=NO;
        NSMutableArray<NSString *> *requestedLanguages=[NSMutableArray array];
        if (len) {
            NSString *requested=[NSString stringWithUTF8String:language];
            if (requested) {
                NSArray<NSString *> *supported=
                    [req supportedRecognitionLanguagesAndReturnError:nil];
                for (NSString *part in [requested componentsSeparatedByString:@","]) {
                    NSString *lang=[part stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (lang.length && (!supported || [supported containsObject:lang]))
                        [requestedLanguages addObject:lang];
                }
            }
        }
        if (requestedLanguages.count) {
            req.recognitionLanguages=requestedLanguages;
        } else if (@available(iOS 16.0, *)) {
            req.automaticallyDetectsLanguage=YES;
        }
        if (ciImage) {
            @try {
                VNImageRequestHandler *primary=[[VNImageRequestHandler alloc]
                    initWithCIImage:ciImage options:@{}];
                success=[primary performRequests:@[req] error:&primaryError];
            } @catch (NSException *ex) {
                primaryException=ex;
                success=NO;
            }
        }
        NSError *fallbackError=nil;
        NSException *fallbackException=nil;
        if (!success) {
            // Fallback is read-only, uses the SAME crop, and does not call
            // nk.screenshot/tap/inputText. Preserve previous CGImage behavior.
            VNRecognizeTextRequest *fallback=[[VNRecognizeTextRequest alloc]init];
            fallback.recognitionLevel=VNRequestTextRecognitionLevelAccurate;
            fallback.usesLanguageCorrection=YES;
            if (requestedLanguages.count) {
                fallback.recognitionLanguages=requestedLanguages;
            } else if (@available(iOS 16.0, *)) {
                fallback.automaticallyDetectsLanguage=YES;
            }
            @try {
                VNImageRequestHandler *second=[[VNImageRequestHandler alloc]
                    initWithCGImage:crop options:@{}];
                success=[second performRequests:@[fallback] error:&fallbackError];
                if (success) req=fallback;
            } @catch (NSException *ex) {
                fallbackException=ex;
                success=NO;
            }
        }
        CGImageRelease(crop);
        // v0.8.1: Both crop paths returned CoreVideo -6662 on iPhone
        // (750x220 420f CVPixelBuffer allocation failed), while IPC live OCR
        // in the host service succeeded. Try a different Vision pipeline
        // from the ALREADY-CAPTURED immutable JPEG bytes, not a new screenshot.
        // ROI must use Vision's bottom-left normalized coordinates, whereas
        // NKTouch pixel coordinates use top-left origin.
        NSError *jpegError=nil;
        NSException *jpegException=nil;
        if (!success) {
            VNRecognizeTextRequest *jpegRequest=[[VNRecognizeTextRequest alloc]init];
            if (@available(iOS 13.0, *)) jpegRequest.revision=1;
            jpegRequest.recognitionLevel=VNRequestTextRecognitionLevelFast;
            jpegRequest.usesLanguageCorrection=YES;
            // CPU-only/fast is a compatibility attempt, not proof that iOS
            // CoreVideo/Sandbox allows OCR in the Lua task process.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            jpegRequest.usesCPUOnly=YES;
#pragma clang diagnostic pop
            if (requestedLanguages.count) {
                NSArray<NSString *> *supported=
                    [jpegRequest supportedRecognitionLanguagesAndReturnError:nil];
                NSMutableArray<NSString *> *compatible=[NSMutableArray array];
                for (NSString *candidate in requestedLanguages) {
                    if (supported && [supported containsObject:candidate])
                        [compatible addObject:candidate];
                }
                if (compatible.count) jpegRequest.recognitionLanguages=compatible;
            }
            // Reject out-of-frame region before entering Vision (above).
            // The normalized y origin is at the BOTTOM of the source image.
            CGFloat rx=(CGFloat)x/(CGFloat)f->w;
            CGFloat ry=(CGFloat)(f->h-(size_t)y-(size_t)h)/(CGFloat)f->h;
            CGFloat rw=(CGFloat)w/(CGFloat)f->w;
            CGFloat rh=(CGFloat)h/(CGFloat)f->h;
            jpegRequest.regionOfInterest=CGRectMake(rx,ry,rw,rh);
            @try {
                NSData *originalJPEG=(__bridge NSData *)f->jpeg;
                VNImageRequestHandler *third=[[VNImageRequestHandler alloc]
                    initWithData:originalJPEG options:@{}];
                success=[third performRequests:@[jpegRequest] error:&jpegError];
                if (success) req=jpegRequest;
            } @catch (NSException *ex) {
                jpegException=ex;
                success=NO;
            }
        }
        if (!success) {
            NSString *p=ciImage ?
                nv_ocr_failure_detail(primaryError,primaryException) :
                @"CIImage initialization failed";
            NSString *q=nv_ocr_failure_detail(fallbackError,fallbackException);
            NSString *r=nv_ocr_failure_detail(jpegError,jpegException);
            NSString *message=[NSString stringWithFormat:
                @"Vision OCR failed (CIImage/rev2: %@; CGImage: %@; JPEG/ROI/rev1/CPU: %@)",p,q,r];
            return nv_error(L,[message UTF8String],"OCR");
        }
        NSMutableArray<NSString *> *texts=[NSMutableArray array];
        for (VNRecognizedTextObservation *observation in req.results) {
            VNRecognizedText *best=[[observation topCandidates:1] firstObject];
            if (best.string) [texts addObject:best.string];
        }
        NSString *result=[texts componentsJoinedByString:@"\n"];
        lua_pushstring(L,[result UTF8String] ?: "");
        return 1;
    }
}
static int nv_score(const uint8_t *screen,size_t sw,size_t x,size_t y,
                    const uint8_t *templateGray,size_t tw,size_t th,size_t sample) {
    // Return a signed normalized-correlation score in [-10000,10000].
    // Limit samples for bounded execution even for large templates.
    double a=0,b=0,aa=0,bb=0,ab=0,n=0;
    for (size_t ry=0;ry<th;ry+=sample)
        for (size_t rx=0;rx<tw;rx+=sample) {
            double t=templateGray[ry*tw+rx],s=screen[(y+ry)*sw+(x+rx)];
            a+=t;b+=s;aa+=t*t;bb+=s*s;ab+=t*s;n++;
        }
    if (n<4) return -10000;
    double d1=n*aa-a*a,d2=n*bb-b*b;
    if (d1<=1 || d2<=1) return -10000;
    double score=(n*ab-a*b)/sqrt(d1*d2);
    if (!isfinite(score)) return -10000;
    if (score>1) score=1; if(score< -1) score=-1;
    return (int)lrint(score*10000.0);
}
static int nv_find_image(lua_State *L) {
    NVFrame *f=NULL;
    if (!nv_live(L,&f)) return nv_error(L,"snapshot already released","CLOSED");
    size_t len=0;
    const char *path=luaL_checklstring(L,2,&len);
    if (!len || len>1024 || memchr(path,'\0',len))
        return nv_error(L,"invalid template path","INVALID");
    lua_Integer maxTry=luaL_optinteger(L,3,2);
    double confidence=luaL_optnumber(L,4,0.8),scale=luaL_optnumber(L,5,0.8);
    if (maxTry<0 || maxTry>4 || !isfinite(confidence) ||
        confidence<0.5 || confidence>1.0 || !isfinite(scale) ||
        scale<=0.05 || scale>=1.0)
        return nv_error(L,"invalid matching parameters","INVALID");
    @autoreleasepool {
        NSString *name=[NSString stringWithUTF8String:path];
        if (!name) return nv_error(L,"invalid template UTF-8","INVALID");
        NSDictionary *attr=[[NSFileManager defaultManager]attributesOfItemAtPath:name error:nil];
        unsigned long long bytes=[attr fileSize];
        if (!bytes || bytes>NV_MAX_TEMPLATE)
            return nv_error(L,"missing/oversized template image","IMAGE_IO");
        CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)
                                 [NSURL fileURLWithPath:name],NULL);
        if (!source) return nv_error(L,"cannot open template image","IMAGE_IO");
        CGImageRef templateImage=CGImageSourceCreateImageAtIndex(source,0,NULL);
        CFRelease(source);
        if (!templateImage) return nv_error(L,"cannot decode template","DECODE");
        uint8_t *rgba=NULL;size_t iw=0,ih=0,stride=0;
        if (!nv_decoded(templateImage,&rgba,&iw,&ih,&stride,NV_MAX_TEMPLATE)) {
            CGImageRelease(templateImage);
            return nv_error(L,"template too large or invalid","MEMORY");
        }
        CGImageRelease(templateImage);
        uint8_t *gray=(uint8_t *)malloc(iw*ih);
        if (!gray) {free(rgba);return nv_error(L,"template allocation failed","MEMORY");}
        for (size_t y=0;y<ih;y++)
            for (size_t x=0;x<iw;x++) {
                const uint8_t *p=rgba+y*stride+x*4;
                gray[y*iw+x]=nv_gray(p[0],p[1],p[2]);
            }
        free(rgba);
        if (!nv_ensure_gray(f)) {
            free(gray);
            return nv_error(L,"cannot allocate frame grayscale for template matching","MEMORY");
        }
        int bestScore=-10001;size_t bestX=0,bestY=0,bestW=0,bestH=0;
        size_t budget=NV_MAX_MATCH_EVAL;
        int variants=1+(int)maxTry*2;
        for (int variant=0;variant<variants && budget>1;variant++) {
            double factor=(variant==0)?1.0:
                 (variant%2 ? pow(scale,(variant+1)/2) : pow(2.0-scale,variant/2));
            size_t tw=(size_t)llround(iw*factor),th=(size_t)llround(ih*factor);
            if (tw<3 || th<3 || tw>f->w || th>f->h ||
                tw>SIZE_MAX/th || tw*th>NV_MAX_TEMPLATE) continue;
            uint8_t *pattern=(uint8_t*)malloc(tw*th);
            if (!pattern) continue;
            for (size_t y=0;y<th;y++)
                for (size_t x=0;x<tw;x++) {
                    size_t sx=(size_t)((double)x/factor);
                    size_t sy=(size_t)((double)y/factor);
                    if (sx>=iw) sx=iw-1;
                    if (sy>=ih) sy=ih-1;
                    pattern[y*tw+x]=gray[sy*iw+sx];
                }
            size_t step=(tw<th?tw:th)/8;
            if(step<1) step=1;
            size_t searchW=f->w-tw+1, searchH=f->h-th+1;
            // Bound total correlation evaluations across ALL scales.
            // Reserve up to 625 local refinements plus one full verification.
            size_t target=budget/(size_t)(variants-variant);
            if (target<2) target=2;
            size_t gridTarget=target>650?target-626:target/2;
            if (gridTarget<1) gridTarget=1;
            size_t maxStep=searchW>searchH?searchW:searchH;
            while (((searchW+step-1)/step)*((searchH+step-1)/step)>gridTarget
                   && step<maxStep) {
                size_t next=step+step/2+1;
                step=next>maxStep?maxStep:next;
            }
            size_t sample=(tw<th?tw:th)/12;
            if(sample<1) sample=1;
            int localScore=-10001;size_t localX=0,localY=0;
            size_t gridCount=0;
            for(size_t y=0;y<searchH && gridCount<gridTarget && budget>1;y+=step)
                for(size_t x=0;x<searchW && gridCount<gridTarget && budget>1;x+=step) {
                    int score=nv_score(f->gray,f->w,x,y,pattern,tw,th,sample);
                    gridCount++;
                    budget--;
                    if(score>localScore){localScore=score;localX=x;localY=y;}
                }
            // Refine the grid winner without exceeding our shared CPU budget.
            size_t radius=step>12?12:step;
            size_t x1=localX>radius?localX-radius:0;
            size_t y1=localY>radius?localY-radius:0;
            size_t x2=localX+radius<searchW?localX+radius:searchW-1;
            size_t y2=localY+radius<searchH?localY+radius:searchH-1;
            size_t refineSample=sample>2?sample/2:1;
            size_t refinedLimit=target>gridCount+1?target-gridCount-1:0;
            if(refinedLimit>625) refinedLimit=625;
            size_t refinedCount=0;
            int refinedScore=-10001;size_t refinedX=localX,refinedY=localY;
            for(size_t y=y1;y<=y2 && refinedCount<refinedLimit && budget>1;y++)
                for(size_t x=x1;x<=x2 && refinedCount<refinedLimit && budget>1;x++) {
                    int score=nv_score(f->gray,f->w,x,y,pattern,tw,th,refineSample);
                    budget--;
                    refinedCount++;
                    if(score>refinedScore){
                        refinedScore=score;refinedX=x;refinedY=y;
                    }
                }
            // One full-resolution check before accepting the match.
            budget--;
            int verifiedScore=nv_score(f->gray,f->w,refinedX,refinedY,pattern,tw,th,1);
            if(verifiedScore>bestScore){
                bestScore=verifiedScore;bestX=refinedX;bestY=refinedY;
                bestW=tw;bestH=th;
            }
            free(pattern);
            if(bestScore>=(int)ceil(confidence*10000.0)) break;
        }
        free(gray);
        if(bestScore<(int)ceil(confidence*10000.0))
            return nv_error(L,"template not found in captured frame","NOT_FOUND");
        lua_createtable(L,0,5);
        lua_pushinteger(L,(lua_Integer)bestX);lua_setfield(L,-2,"x");
        lua_pushinteger(L,(lua_Integer)bestY);lua_setfield(L,-2,"y");
        lua_pushinteger(L,(lua_Integer)bestW);lua_setfield(L,-2,"width");
        lua_pushinteger(L,(lua_Integer)bestH);lua_setfield(L,-2,"height");
        lua_pushnumber(L,(double)bestScore/10000.0);lua_setfield(L,-2,"confidence");
        return 1;
    }
}
static const luaL_Reg nv_methods[]={
    {"getColor",nv_get_color},{"findColor",nv_find_color},
    {"findImage",nv_find_image},{"ocr",nv_ocr},
    {"save",nv_save},{"info",nv_info},{"close",nv_close},{NULL,NULL}
};
// Read-only process resident memory (RSS). No cache eviction or other-app
// controls. Memory-pressure tests must not equate this with freed iOS RAM.
static int nv_memory_stats(lua_State *L) {
    mach_task_basic_info_data_t info = {0};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                     (task_info_t)&info, &count);
    if (result != KERN_SUCCESS) {
        return nv_error(L, "mach task_info unavailable", "RSS_UNAVAILABLE");
    }
    lua_createtable(L, 0, 4);
    lua_pushinteger(L, (lua_Integer)info.resident_size);
    lua_setfield(L, -2, "rss_bytes");
    lua_pushinteger(L, (lua_Integer)info.virtual_size);
    lua_setfield(L, -2, "virtual_bytes");
    lua_pushliteral(L, "MACH_TASK_BASIC_INFO");
    lua_setfield(L, -2, "source");
    lua_pushliteral(L, "PROCESS");
    lua_setfield(L, -2, "scope");
    return 1;
}
static const luaL_Reg nv_module[]={{"open",nv_open},{"tempPath",nv_temp_path},
                                 {"memoryStats",nv_memory_stats},{NULL,NULL}};
int luaopen_nkvision_native(lua_State *L) {
    luaL_newmetatable(L,NV_MT);
    lua_pushcfunction(L,nv_gc);
    lua_setfield(L,-2,"__gc");
    lua_newtable(L);
    luaL_setfuncs(L,nv_methods,0);
    lua_setfield(L,-2,"__index");
    lua_pop(L,1);
    luaL_newlib(L,nv_module);
    return 1;
}
