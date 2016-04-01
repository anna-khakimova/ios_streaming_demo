//
//  EncoderDemoViewController.m
//  Encoder Demo
//
//  Created by Geraint Davies on 11/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "EncoderDemoViewController.h"
#import "CameraServer.h"


@implementation EncoderDemoViewController

@synthesize cameraView;
@synthesize serverAddress;

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self startPreview];
    [CameraServer server].delegate = self;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    // this is not the most beautiful animation...
    AVCaptureVideoPreviewLayer* preview = [[CameraServer server] getPreviewLayer];
    preview.frame = self.cameraView.bounds;
    
    //[[preview connection] setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    
    switch (toInterfaceOrientation)
    {
        case UIInterfaceOrientationPortraitUpsideDown:
            [[preview connection] setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
            break;
            
        case UIInterfaceOrientationPortrait:
            [[preview connection] setVideoOrientation:AVCaptureVideoOrientationPortrait];
            break;
            
        case UIInterfaceOrientationLandscapeLeft:
            [[preview connection] setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft];
            break;
            
        case UIInterfaceOrientationLandscapeRight:
            [[preview connection] setVideoOrientation:AVCaptureVideoOrientationLandscapeRight];
            break;
        
        default:
            break;
    }
}

- (void) startPreview
{
    AVCaptureVideoPreviewLayer* preview = [[CameraServer server] getPreviewLayer];
    [preview removeFromSuperlayer];
    preview.frame = self.cameraView.bounds;
    [[preview connection] setVideoOrientation:AVCaptureVideoOrientationPortrait];//UIInterfaceOrientationPortrait];
    
    [self.cameraView.layer addSublayer:preview];
    
    self.serverAddress.text = [[CameraServer server] getURL];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark CameraServerDelegate

- (void)setIPAddrLabel: (NSString*) str
{
    self.serverAddress.text = str;
}

@end
