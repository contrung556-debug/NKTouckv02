    else if (taskType == TASK_NK_FRAME_OCR)
    {
        // This experimental privileged OCR IPC must never accept remote peers.
        // SocketServer already records whether the connection is loopback.
        if (!zxSocketClientIsLoopback(writeStreamRef)) {
            notifyClient((UInt8 *)"-1;;NK_FRAME_OCR_LOOPBACK_ONLY\r\n",writeStreamRef);
        } else {
        // NKTouch v0.8.2: OCR the caller's ALREADY-CAPTURED JPEG.
        // No call to Screen/createScreenShot. This executes Vision in the
        // same SpringBoard service that already passes live OCR on-device.
        @autoreleasepool {
            NSString *output=nil;
            BOOL valid=NO;
            @try {
                NSString *raw=[[NSString alloc] initWithUTF8String:(const char *)eventData];
                NSArray<NSString *> *parts=[raw componentsSeparatedByString:@";;"];
                if (parts.count==6) {
                    NSMutableArray<NSNumber *> *nums=[NSMutableArray array];
                    NSCharacterSet *invalidDigits=[[NSCharacterSet decimalDigitCharacterSet] invertedSet];
                    for (NSUInteger n=0;n<4;n++) {
                        NSString *word=parts[n];
                        if (word.length==0 || word.length>5 ||
                            [word rangeOfCharacterFromSet:invalidDigits].location!=NSNotFound) break;
                        [nums addObject:@([word integerValue])];
                    }
                    NSString *lang=parts[4];
                    // Socket messages are terminated by CRLF; strip only line breaks
                    // so strict Base64 decoding accepts the intended payload.
                    NSString *encoded=[parts[5] stringByTrimmingCharactersInSet:
                        [NSCharacterSet newlineCharacterSet]];
                    BOOL languageSafe=lang.length<=64 &&
                        [lang rangeOfCharacterFromSet:
                             [[NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_,"]
                                 invertedSet]].location==NSNotFound;
                    if (nums.count==4 && languageSafe && encoded.length>0 &&
                        encoded.length<=1400000) {
                        NSData *jpeg=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
                        if (jpeg.length>0 && jpeg.length<=1024*1024) {
                            CGImageSourceRef source=CGImageSourceCreateWithData(
                                (__bridge CFDataRef)jpeg,NULL);
                            CGImageRef image=source ?
                                CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
                            if (source) CFRelease(source);
                            if (image) {
                                NSUInteger iw=CGImageGetWidth(image),ih=CGImageGetHeight(image);
                                NSUInteger x=[nums[0] unsignedIntegerValue];
                                NSUInteger y=[nums[1] unsignedIntegerValue];
                                NSUInteger w=[nums[2] unsignedIntegerValue];
                                NSUInteger h=[nums[3] unsignedIntegerValue];
                                if (iw>=1 && ih>=1 && iw<=10000 && ih<=10000 &&
                                    w>0 && h>0 && x<iw && y<ih && w<=iw-x && h<=ih-y) {
                                    // JPEG from NKTouch has already been
                                    // oriented and decoded into screen pixels.
                                    VKOcrManager *ocr=[[VKOcrManager alloc]
                                        initWithCGImage:image
                                        area:CGRectMake(x,y,w,h) orientation:1];
                                    if (lang.length>0)
                                        [ocr setLanguages:[lang componentsSeparatedByString:@","]];
                                    [ocr setRecognitionLevel:VNRequestTextRecognitionLevelAccurate];
                                    [ocr setCorrection:YES];
                                    NSError *err=nil;
                                    NSString *result=[ocr recognize:&err];
                                    if (result && !err) {
                                        NSMutableArray<NSString *> *words=[NSMutableArray array];
                                        for (NSString *part in
                                              [result componentsSeparatedByString:@";;"]) {
                                            NSRange position=[part rangeOfString:@",,"];
                                            NSString *text=(position.location==NSNotFound) ?
                                                part : [part substringToIndex:position.location];
                                            text=[[[text stringByReplacingOccurrencesOfString:@"\n"
                                                                                  withString:@" "]
                                                       stringByReplacingOccurrencesOfString:@"\r"
                                                                                  withString:@" "]
                                                  stringByReplacingOccurrencesOfString:@";;"
                                                                               withString:@" "];
                                            if (text.length) [words addObject:text];
                                        }
                                        NSString *joined=[words componentsJoinedByString:@" "];
                                        if ([joined lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=16000) {
                                            valid=YES;
                                            output=joined;
                                        }
                                    }
                                }
                                CGImageRelease(image);
                            }
                        }
                    }
                }
            } @catch (NSException *ex) {
                // No private OCR text or JPEG bytes are ever written to logs.
                valid=NO;
            }
            NSString *reply=valid ?
                [NSString stringWithFormat:@"0;;%@\r\n",output ?: @""] :
                @"-1;;NK_FRAME_OCR_UNAVAILABLE\r\n";
            notifyClient((UInt8 *)[reply UTF8String],writeStreamRef);
        }
        }
    }
