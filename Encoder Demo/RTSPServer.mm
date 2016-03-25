//
//  RTSPServer.m
//  Encoder Demo
//
//  Created by Geraint Davies on 17/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "RTSPServer.h"
#import "RTSPClientConnection.h"
#import "ifaddrs.h"
#import "arpa/inet.h"
#import <CoreLocation/CoreLocation.h>
#import "Location.h"
#define MILLISEC_PER_SEC 1000

@interface RTSPServer () <CLLocationManagerDelegate>

{
    CFSocketRef _listener;
    CFSocketRef _listenerVMF;
    
    CFSocketRef _vmfDataSocket;
    BOOL vmfDataSocketSetup;
    CFRunLoopSourceRef _vmfRls;
    BOOL vmfMetadataSessionSetup;
    
    NSMutableArray* _connections;
    NSData* _configData;
    int _bitrate;
    double _firstpts;
    
    CLLocationManager *locationManager;
    std::vector<LocationData> gpsDataVector;
    std::vector<LocationData> buffer;
    //time in milliseconds
    long long startStreamingMetadataTime;
    
    NSTimer *locationGenerationTimer;
    std::vector<LocationData> gpsGeneratedData;
    size_t generatedDataIndex;
}

- (RTSPServer*) init:(NSData*) configData;
- (void) onAccept:(CFSocketNativeHandle) childHandle;
- (void) onVmfAccept:(CFSocketNativeHandle) childHandle;
- (void) onVmfData:(CFDataRef) data;
- (void) sendNewLocationOnTimer:(NSTimer*)timer;

@property (readonly, getter=isVmfDataSocketSetup) BOOL vmfDataSocketSetup;
@property (readonly, getter=isVmfMetadataSessionSetup) BOOL vmfMetadataSessionSetup;


@end


static void onSocket (
                 CFSocketRef s,
                 CFSocketCallBackType callbackType,
                 CFDataRef address,
                 const void *data,
                 void *info
                 )
{
    RTSPServer* server = (__bridge RTSPServer*)info;
    switch (callbackType)
    {
        case kCFSocketAcceptCallBack:
        {
            CFSocketNativeHandle* pH = (CFSocketNativeHandle*) data;
            [server onAccept:*pH];
            break;
        }
        default:
            NSLog(@"unexpected socket event");
            break;
    }
    
}

static void onVmfSocket (
                      CFSocketRef s,
                      CFSocketCallBackType callbackType,
                      CFDataRef address,
                      const void *data,
                      void *info
                      )
{
    
    
    RTSPServer* server = (__bridge RTSPServer*)info;
    
    if ([server isVmfDataSocketSetup])
        return;
    
    switch (callbackType)
    {
        case kCFSocketAcceptCallBack:
        {
            CFSocketNativeHandle* pH = (CFSocketNativeHandle*) data;
            [server onVmfAccept:*pH];
            break;
        }
        default:
            NSLog(@"unexpected socket event");
            break;
    }
    
}

static void onVmfDataSocket (
                      CFSocketRef s,
                      CFSocketCallBackType callbackType,
                      CFDataRef address,
                      const void *data,
                      void *info
                      )
{
    RTSPServer* server = (__bridge RTSPServer*)info;
    switch (callbackType)
    {
        case kCFSocketDataCallBack:
            [server onVmfData:(CFDataRef) data];
            break;
            
        default:
            NSLog(@"unexpected socket event");
            break;
    }
    
}

@implementation RTSPServer

@synthesize bitrate = _bitrate;
@synthesize firstpts = _firstpts;
@synthesize vmfDataSocketSetup;
@synthesize vmfMetadataSessionSetup;

+ (RTSPServer*) setupListener:(NSData*) configData
{
    RTSPServer* obj = [RTSPServer alloc];
    if (![obj init:configData])
    {
        return nil;
    }
    return obj;
}

- (RTSPServer*) init:(NSData*) configData
{
    _configData = configData;
    _connections = [NSMutableArray arrayWithCapacity:10];
    _vmfDataSocket = nil;
    _vmfRls = nil;
    vmfDataSocketSetup = FALSE;
    vmfMetadataSessionSetup = FALSE;
    startStreamingMetadataTime = -1;
    locationGenerationTimer = nil;
    generatedDataIndex = 0;
    gpsGeneratedData.clear();
    
    locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    locationManager.distanceFilter = kCLDistanceFilterNone;
    locationManager.pausesLocationUpdatesAutomatically = NO;
    
    CFSocketContext info;
    memset(&info, 0, sizeof(info));
    info.info = (void*)CFBridgingRetain(self);
    
    _listener = CFSocketCreate(nil, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, onSocket, &info);
    _listenerVMF = CFSocketCreate(nil, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, onVmfSocket, &info);
    
    // must set SO_REUSEADDR in case a client is still holding this address
    int t = 1;
    setsockopt(CFSocketGetNative(_listener), SOL_SOCKET, SO_REUSEADDR, &t, sizeof(t));
    setsockopt(CFSocketGetNative(_listenerVMF), SOL_SOCKET, SO_REUSEADDR, &t, sizeof(t));
    
    struct sockaddr_in addr;
    struct sockaddr_in addrVmf;
    
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(554);
    CFDataRef dataAddr = CFDataCreate(nil, (const uint8_t*)&addr, sizeof(addr));
    CFSocketError e = CFSocketSetAddress(_listener, dataAddr);
    CFRelease(dataAddr);
    
    if (e)
    {
        NSLog(@"bind error %d", (int) e);
    }
    
    addrVmf.sin_addr.s_addr = INADDR_ANY;
    addrVmf.sin_family = AF_INET;
    addrVmf.sin_port = htons(4321);
    CFDataRef dataAddrVmf = CFDataCreate(nil, (const uint8_t*)&addrVmf, sizeof(addrVmf));
    CFSocketError vmfSocketSetAddrErr = CFSocketSetAddress(_listenerVMF, dataAddrVmf);
    CFRelease(dataAddrVmf);
    
    if (vmfSocketSetAddrErr)
    {
        NSLog(@"Failed vmf socket address setting: %d", (int) vmfSocketSetAddrErr);
    }
    
    CFRunLoopSourceRef rls = CFSocketCreateRunLoopSource(nil, _listener, 0);
    CFRunLoopSourceRef rlsVmf = CFSocketCreateRunLoopSource(nil, _listenerVMF, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), rls, kCFRunLoopCommonModes);
    CFRunLoopAddSource(CFRunLoopGetMain(), rlsVmf, kCFRunLoopCommonModes);
    CFRelease(rls);
    CFRelease(rlsVmf);
    
    LocationData newLocation;
    newLocation.coordinate.latitude = 37.388350;
    newLocation.coordinate.longitude = -121.964500;
    
    for (size_t i = 0; i < 10; i++)
    {
        newLocation.coordinate.latitude -= 0.000045;
        newLocation.coordinate.longitude -= 0.000130;
        gpsGeneratedData.push_back(newLocation);
    }
    
    for (size_t i = 0; i < 10; i++)
    {
        newLocation.coordinate.latitude -= 0.000090;
        newLocation.coordinate.longitude += 0.000050;
        gpsGeneratedData.push_back(newLocation);
    }
    
    for (size_t i = 0; i < 10; i++)
    {
        newLocation.coordinate.latitude += 0.000060;
        newLocation.coordinate.longitude += 0.000150;
        gpsGeneratedData.push_back(newLocation);
    }
    
    for (size_t i = 0; i < 10; i++)
    {
        newLocation.coordinate.latitude += 0.000025;
        newLocation.coordinate.longitude -= 0.000070;
        gpsGeneratedData.push_back(newLocation);
    }
    
    return self;
}

- (NSData*) getConfigData
{
    return _configData;
}

- (void) onAccept:(CFSocketNativeHandle) childHandle
{
    RTSPClientConnection* conn = [RTSPClientConnection createWithSocket:childHandle server:self];
    if (conn != nil)
    {
        @synchronized(self)
        {
            NSLog(@"Client connected");
            [_connections addObject:conn];
        }
    }
    
}

- (void) onVmfAccept:(CFSocketNativeHandle) childHandle
{
    CFSocketContext info;
    memset(&info, 0, sizeof(info));
    info.info = (void*)CFBridgingRetain(self);
    
    _vmfDataSocket = CFSocketCreateWithNative(nil, childHandle, kCFSocketDataCallBack, onVmfDataSocket, &info);
    
    _vmfRls = CFSocketCreateRunLoopSource(nil, _vmfDataSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _vmfRls, kCFRunLoopCommonModes);
    
    if (_vmfDataSocket != nil)
        vmfDataSocketSetup = true;
    
    NSString *msg = @"VMF";
    NSData* msgData = [msg dataUsingEncoding:NSUTF8StringEncoding];
    CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgData), 2);
    if (e)
    {
        NSLog(@"send %ld", e);
    }
}

- (void) onVmfData:(CFDataRef) data
{
    if (CFDataGetLength(data) == 0)
    {
        @synchronized(self)
        {
            if (_vmfDataSocket)
                CFSocketInvalidate(_vmfDataSocket);
            
            _vmfDataSocket = nil;
            vmfDataSocketSetup = FALSE;
            vmfMetadataSessionSetup = FALSE;
            gpsDataVector.clear();
            buffer.clear();
            
            if (locationManager)
                [locationManager stopUpdatingLocation];
            
            generatedDataIndex = 0;
            
        }
        return;
    }
    
    NSString* msg = [[NSString alloc] initWithData:(__bridge NSData*)data encoding:NSUTF8StringEncoding];
    NSArray* lines = [msg componentsSeparatedByString:@"\r\n"];
    if ([lines count] > 1)
    {
        NSLog(@"msg parse error");
    }
    
    NSArray* lineone = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
    if ([lineone count] > 1)
    {
        NSLog(@"msg parse error");
    }
    
    NSString* clientResponse = [lineone objectAtIndex:0];
    
    if (([clientResponse caseInsensitiveCompare:@"VMF"] == NSOrderedSame))
    {
        NSString *msg = @"XML";
        NSData* msgData = [msg dataUsingEncoding:NSUTF8StringEncoding];
        CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgData), 2);
        if (e)
        {
            NSLog(@"send %ld", e);
        }
    }
    else if (([clientResponse caseInsensitiveCompare:@"OK"] == NSOrderedSame))
    {
        buffer.clear();
        gpsDataVector.clear();
        
        if (locationManager)
            [locationManager startUpdatingLocation];
        
        generatedDataIndex = 0;
        
        if (locationGenerationTimer)
        {
            [locationGenerationTimer invalidate];
            locationGenerationTimer = nil;
        }
        
        locationGenerationTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0 target: self selector:@selector(sendNewLocationOnTimer:) userInfo: nil repeats:YES];
        
        vmfMetadataSessionSetup = true;
        //NSString *msg = [NSString stringWithFormat:@""];
        startStreamingMetadataTime = vmf::getTimestamp();
        
        
        vmf::MetadataStream::VideoSegment segment ("iOS", 0, startStreamingMetadataTime, 0, 720, 480);
        std::shared_ptr<vmf::MetadataSchema> spSchema = vmf::MetadataSchema::getStdSchema();
    }
    else
    {
        
    }
}

- (void) sendNewLocationOnTimer:(NSTimer*)timer
{
    if (generatedDataIndex == gpsGeneratedData.size())
        generatedDataIndex -= gpsGeneratedData.size();
    
    LocationData newLocation = gpsGeneratedData[generatedDataIndex];
    
    std::shared_ptr<vmf::MetadataSchema> spSchema = vmf::MetadataSchema::getStdSchema();
    
    auto spLocationMetadata = std::make_shared<vmf::Metadata>(spSchema->findMetadataDesc("location"));
    
    spLocationMetadata->setFieldValue("longitude", newLocation.coordinate.longitude);
    spLocationMetadata->setFieldValue("latitude", newLocation.coordinate.latitude);
    spLocationMetadata->setFieldValue("altitude", 8);
    spLocationMetadata->setFieldValue("accuracy", 100);
    spLocationMetadata->setFieldValue("speed", 2);
    spLocationMetadata->setTimestamp(vmf::getTimestamp());
    
    generatedDataIndex++;
}

- (void) onVideoData:(NSArray*) data time:(double) pts
{
    @synchronized(self)
    {
        for (RTSPClientConnection* conn in _connections)
        {
            [conn onVideoData:data time:pts];
        }
    }
}

- (void) shutdownConnection:(id)conn
{
    @synchronized(self)
    {
        NSLog(@"Client disconnected");
        [_connections removeObject:conn];
    }
}

- (void) shutdownServer
{
    @synchronized(self)
    {
        for (RTSPClientConnection* conn in _connections)
        {
            [conn shutdown];
        }
        _connections = [NSMutableArray arrayWithCapacity:10];
        
        if (locationGenerationTimer)
        {
            [locationGenerationTimer invalidate];
            locationGenerationTimer = nil;
        }
        
        if (_vmfDataSocket != nil)
        {
            CFSocketInvalidate(_vmfDataSocket);
            _vmfDataSocket = nil;
            vmfDataSocketSetup = false;
            vmfMetadataSessionSetup = false;
        }
        
        if (_listener != nil)
        {
            CFSocketInvalidate(_listener);
            _listener = nil;
        }
        
        if (_listenerVMF != nil)
        {
            CFSocketInvalidate(_listenerVMF);
            _listener = nil;
        }
        
        if (_vmfRls != nil)
        {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), _vmfRls, kCFRunLoopCommonModes);
            CFRelease(_vmfRls);
        }
    }
}

+ (NSString*) getIPAddress
{
    NSString* address;
    struct ifaddrs *interfaces = nil;
    
    // get all our interfaces and find the one that corresponds to wifi
    if (!getifaddrs(&interfaces))
    {
        for (struct ifaddrs* addr = interfaces; addr != NULL; addr = addr->ifa_next)
        {
            if (([[NSString stringWithUTF8String:addr->ifa_name] isEqualToString:@"en0"]) &&
                (addr->ifa_addr->sa_family == AF_INET))
            {
                struct sockaddr_in* sa = (struct sockaddr_in*) addr->ifa_addr;
                address = [NSString stringWithUTF8String:inet_ntoa(sa->sin_addr)];
                break;
            }
        }
    }
    freeifaddrs(interfaces);
    return address;
}

//#pragma mark CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSLog(@"didFailWithError: %@", error);
    UIAlertView *errorAlert = [[UIAlertView alloc]
                               initWithTitle:@"Error" message:@"Failed to Get Your Location" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [errorAlert show];
}


- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
    long long currentTime = vmf::getTimestamp();
    NSLog(@"didUpdateToLocation: %@", newLocation);
    /*[self.signalLabel setBackgroundColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.0]];
     NSString *coordinate = [NSString stringWithFormat:@"%.5f lat; %.5f long", newLocation.coordinate.latitude, newLocation.coordinate.longitude];
     self.signalLabel.text = [NSString stringWithFormat:@"%@", coordinate];
     self.signalLabel.hidden = NO;
     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
     self.signalLabel.hidden = YES;
     });*/
    
    LocationData currentLocation;
    long long timeSinceStartInSecond = (currentTime - startStreamingMetadataTime)/MILLISEC_PER_SEC;
    
    if (newLocation == nil)
    {
        NSLog(@"newLocation is null pointer");
        return;
    }
    
    NSLog(@"Time stamp from vmf::getTimestamp() = %lld", currentTime);
    NSLog(@"Time stamp from newLocation = %lf", newLocation.timestamp.timeIntervalSince1970);
    currentLocation.time = currentTime;
    //currentData.time = newLocation.timestamp.timeIntervalSince1970 * MILLISEC_PER_SEC;
    currentLocation.coordinate.longitude = newLocation.coordinate.longitude;
    currentLocation.coordinate.latitude = newLocation.coordinate.latitude;
    currentLocation.hAccuracy = newLocation.horizontalAccuracy;
    currentLocation.altitude = newLocation.altitude;
    currentLocation.speed = newLocation.speed;
    
    if (gpsDataVector.empty())
    {
        gpsDataVector.push_back (currentLocation);
        std::shared_ptr<vmf::MetadataSchema> spSchema = vmf::MetadataSchema::getStdSchema();
        
        auto spLocationMetadata = std::make_shared<vmf::Metadata>(spSchema->findMetadataDesc("location"));
        
        spLocationMetadata->setFieldValue("longitude", currentLocation.coordinate.longitude);
        spLocationMetadata->setFieldValue("latitude", currentLocation.coordinate.latitude);
        spLocationMetadata->setFieldValue("altitude", currentLocation.altitude);
        spLocationMetadata->setFieldValue("accuracy", currentLocation.hAccuracy);
        spLocationMetadata->setFieldValue("speed", currentLocation.speed);
        spLocationMetadata->setTimestamp(currentLocation.time);

        //self.counterLabel.text = [NSString stringWithFormat:@"Locations Recorded: %lu", gpsData.size()];
    }
    else if (timeSinceStartInSecond == ((gpsDataVector.back().time - startStreamingMetadataTime)/MILLISEC_PER_SEC))
    {
        buffer.push_back (currentLocation);
    }
    else if ((timeSinceStartInSecond > ((gpsDataVector.back ().time - startStreamingMetadataTime)/MILLISEC_PER_SEC)))
    {
         size_t bufSize = buffer.size();
         if (!buffer.empty())
         {
             CLLocationDegrees sumLongitude = currentLocation.coordinate.longitude;
             CLLocationDegrees sumLatitude = currentLocation.coordinate.latitude;
             CLLocationDistance sumAltitude = currentLocation.altitude;
         
             for (size_t i = 0; i < bufSize; i++)
             {
                 sumLongitude += buffer[i].coordinate.longitude;
                 sumLatitude += buffer[i].coordinate.latitude;
                 sumAltitude += buffer[i].altitude;
             }
         
             LocationData averagedForSecond;
             averagedForSecond.coordinate.longitude = sumLongitude/(bufSize + 1);
             averagedForSecond.coordinate.latitude = sumLatitude/(bufSize + 1);
             averagedForSecond.altitude = sumAltitude/(bufSize + 1);
             averagedForSecond.hAccuracy = currentLocation.hAccuracy;
             averagedForSecond.time = currentLocation.time;
             gpsDataVector.push_back (averagedForSecond);
             buffer.clear();
        }
        else
        {
           gpsDataVector.push_back (currentLocation);
        }
        
        std::shared_ptr<vmf::MetadataSchema> spSchema = vmf::MetadataSchema::getStdSchema();
        
        auto spLocationMetadata = std::make_shared<vmf::Metadata>(spSchema->findMetadataDesc("location"));
        
        spLocationMetadata->setFieldValue("longitude", gpsDataVector.back().coordinate.longitude);
        spLocationMetadata->setFieldValue("latitude", gpsDataVector.back().coordinate.latitude);
        spLocationMetadata->setFieldValue("altitude", gpsDataVector.back().altitude);
        spLocationMetadata->setFieldValue("accuracy", gpsDataVector.back().hAccuracy);
        spLocationMetadata->setFieldValue("speed", gpsDataVector.back().speed);
        spLocationMetadata->setTimestamp(gpsDataVector.back().time);
        //self.counterLabel.text = [NSString stringWithFormat:@"Locations Recorded: %lu", gpsDataVector.size()];
    }
    
}


@end


