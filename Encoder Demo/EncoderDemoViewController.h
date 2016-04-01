//
//  EncoderDemoViewController.h
//  Encoder Demo
//
//  Created by Geraint Davies on 11/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <UIKit/UIKit.h>
#import "CameraServer.h"
//#import <CoreLocation/CoreLocation.h>

@interface EncoderDemoViewController : UIViewController <CameraServerDelegate>
@property (strong, nonatomic) IBOutlet UIView *cameraView;
@property (retain, nonatomic) IBOutlet UIButton *RecordButton;
@property (strong, nonatomic) IBOutlet UILabel *serverAddress;

//- (IBAction)toggleStreaming:(id)sender;
- (void) startPreview;

@end
