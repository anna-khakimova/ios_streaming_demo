//
//  EncoderDemoViewController.m
//  Encoder Demo
//
//  Created by Geraint Davies on 11/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "EncoderDemoViewController.h"
#import "CameraServer.h"
#import "Location.h"
#define MILLISEC_PER_SEC 1000

@implementation EncoderDemoViewController

@synthesize cameraView;
@synthesize serverAddress;

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self startPreview];
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

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
/*    long long currentTime = vmf::getTimestamp();
    NSLog(@"didUpdateToLocation: %@", newLocation);
//[self.signalLabel setBackgroundColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0]];
    NSString *coordinate = [NSString stringWithFormat:@"%.5f lat; %.5f long", newLocation.coordinate.latitude, newLocation.coordinate.longitude];
    //self.signalLabel.text = [NSString stringWithFormat:@"%@", coordinate];
    //self.signalLabel.hidden = NO;
    /*dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.signalLabel.hidden = YES;
    });
    
    LocationData currentData;
    long long timeSec = (currentTime - startUtcRecordTime)/MILLISEC_PER_SEC;
    
    if (newLocation != nil)
    {
        currentData.time = currentTime;
        currentData.coordinate.longitude = newLocation.coordinate.longitude;
        currentData.coordinate.latitude = newLocation.coordinate.latitude;
        currentData.hAccurcy = newLocation.horizontalAccuracy;
        currentData.altitude = newLocation.altitude;
        currentData.speed = newLocation.speed;
        
        /*if (gpsData.size() == 0)
        {
            gpsData.push_back (currentData);
            self.counterLabel.text = [NSString stringWithFormat:@"Locations Recorded: %lu", gpsData.size()];
        }
        else if (((gpsData.size() != 0) && (timeSec != ((gpsData.back ().time - startUtcRecordTime)/MILLISEC_PER_SEC))))
        {
            int32_t bufferSize = buffer.size();
            if (bufferSize != 0)
            {
                CLLocationDegrees sumLongitude = gpsData.back ().coordinate.longitude;
                CLLocationDegrees sumLatitude = gpsData.back().coordinate.latitude;
                CLLocationDistance sumAltitude = gpsData.back().altitude;
                
                for (int i = 0; i < bufferSize; i++)
                {
                    sumLongitude += buffer[i].coordinate.longitude;
                    sumLatitude += buffer[i].coordinate.latitude;
                    sumAltitude += buffer[i].altitude;
                }
                
                LocationData tmp;
                tmp.coordinate.longitude = sumLongitude/bufferSize;
                tmp.coordinate.latitude = sumLatitude/bufferSize;
                tmp.altitude = sumAltitude/bufferSize;
                tmp.hAccurcy = gpsData.back().hAccurcy;
                tmp.time = gpsData.back ().time;
                gpsData.pop_back ();
                gpsData.push_back (tmp);
                
            }
            
            gpsData.push_back (currentData);
            self.counterLabel.text = [NSString stringWithFormat:@"Locations Recorded: %lu", gpsData.size()];
            buffer.clear();
        }
        else if ((gpsData.size() != 0) && (timeSec == ((gpsData.back ().time - startUtcRecordTime)/MILLISEC_PER_SEC)))
        {
            buffer.push_back (currentData);
        }
    }
         */
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
@end
