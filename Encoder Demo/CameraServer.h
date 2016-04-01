//
//  CameraServer.h
//  Encoder Demo
//
//  Created by Geraint Davies on 19/02/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <Foundation/Foundation.h>
#import "AVFoundation/AVCaptureSession.h"
#import "AVFoundation/AVCaptureOutput.h"
#import "AVFoundation/AVCaptureDevice.h"
#import "AVFoundation/AVCaptureInput.h"
#import "AVFoundation/AVCaptureVideoPreviewLayer.h"
#import "AVFoundation/AVMediaFormat.h"
#import "RTSPServer.h"

@protocol CameraServerDelegate;

@interface CameraServer : NSObject
{
    id <CameraServerDelegate> delegate;
}
+ (CameraServer*) server;
- (void) startup;
- (void) shutdown;
- (NSString*) getURL;
- (AVCaptureVideoPreviewLayer*) getPreviewLayer;
@property (readwrite) id <CameraServerDelegate> delegate;
@property (readonly) RTSPServer* rtsp;
@end


@protocol CameraServerDelegate <NSObject>
@required
- (void)setIPAddrLabel:(NSString*) str;
@end