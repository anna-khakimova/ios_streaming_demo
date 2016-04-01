//
//  RTSPServer.m
//  Encoder Demo
//
//  Created by Geraint Davies on 17/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "RTSPServer.h"
#import "CameraServer.h"
#import "RTSPClientConnection.h"
#import "ifaddrs.h"
#import "arpa/inet.h"
#import <CoreLocation/CoreLocation.h>
#import "Location.h"
#define MILLISEC_PER_SEC 1000

@interface RTSPServer () <CLLocationManagerDelegate>

{
    CFSocketRef _listener;
    CFSocketRef _listenerVmf;
    
    CFSocketRef _vmfDataSocket;
    
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
    long long _startVideoStreamTime;
    
    NSTimer *locationGenerationTimer;
    std::vector<LocationData> gpsGeneratedData;
    size_t generatedDataIndex;
}

- (RTSPServer*) init:(NSData*) configData;
- (void) onAccept:(CFSocketNativeHandle) childHandle;

- (void) onVmfData:(CFDataRef) data;
- (void) sendNewLocationOnTimer:(NSTimer*)timer;

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
    
    if (server.vmfDataSocket)
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
@synthesize startVideoStreamTime = _startVideoStreamTime;
@synthesize vmfDataSocket = _vmfDataSocket;
@synthesize vmfMetadataSessionSetup;
@synthesize listenerVmf = _listenerVmf;

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
    _listenerVmf = nil;
    _vmfRls = nil;
    
    vmfMetadataSessionSetup = FALSE;
    _startVideoStreamTime = -1;
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
    
    // must set SO_REUSEADDR in case a client is still holding this address
    int t = 1;
    setsockopt(CFSocketGetNative(_listener), SOL_SOCKET, SO_REUSEADDR, &t, sizeof(t));
    
    struct sockaddr_in addr;
    
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(1234);
    CFDataRef dataAddr = CFDataCreate(nil, (const uint8_t*)&addr, sizeof(addr));
    CFSocketError e = CFSocketSetAddress(_listener, dataAddr);
    CFRelease(dataAddr);
    
    if (e)
    {
        NSLog(@"bind error %d", (int) e);
    }
    
    CFRunLoopSourceRef rls = CFSocketCreateRunLoopSource(nil, _listener, 0);
    
    CFRunLoopAddSource(CFRunLoopGetMain(), rls, kCFRunLoopCommonModes);
    
    CFRelease(rls);
    
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
    
    if (!_listenerVmf)
    {
        CFSocketContext info;
        memset(&info, 0, sizeof(info));
        info.info = (void*)CFBridgingRetain(self);
        
        _listenerVmf = CFSocketCreate(nil, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, onVmfSocket, &info);
        
        // must set SO_REUSEADDR in case a client is still holding this address
        int t = 1;
        setsockopt(CFSocketGetNative(_listenerVmf), SOL_SOCKET, SO_REUSEADDR, &t, sizeof(t));
        
        struct sockaddr_in addrVmf;
        
        addrVmf.sin_addr.s_addr = INADDR_ANY;
        addrVmf.sin_family = AF_INET;
        addrVmf.sin_port = htons(4321);
        CFDataRef dataAddrVmf = CFDataCreate(nil, (const uint8_t*)&addrVmf, sizeof(addrVmf));
        CFSocketError vmfSocketSetAddrErr = CFSocketSetAddress(_listenerVmf, dataAddrVmf);
        CFRelease(dataAddrVmf);
        
        if (vmfSocketSetAddrErr)
        {
            NSLog(@"Failed vmf socket address setting: %d", (int) vmfSocketSetAddrErr);
        }
        
        CFRunLoopSourceRef rlsVmf = CFSocketCreateRunLoopSource(nil, _listenerVmf, 0);
        
        CFRunLoopAddSource(CFRunLoopGetMain(), rlsVmf, kCFRunLoopCommonModes);
        
        CFRelease(rlsVmf);
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
    
    NSString *msg = @"VMF";
    NSData* msgData = [msg dataUsingEncoding:NSUTF8StringEncoding];
    
    CFDataRef msgDataRef = (__bridge CFDataRef)(msgData);
    
    __uint32_t bytes = CFDataGetLength(msgDataRef);
    
    NSData* data = [NSData dataWithBytes: &bytes length: sizeof(bytes)];
    CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(data), 2);
    
    if (e)
    {
        NSLog(@"send size %ld", e);
    }
    
    e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgData), 2);
    if (e)
    {
        NSLog(@"send %ld", e);
    }
}

- (void) onVmfData:(CFDataRef) data
{
    if (CFDataGetLength(data) == 0)
    {
        if (_vmfDataSocket)
        {
            CFSocketInvalidate(_vmfDataSocket);
            _vmfDataSocket = nil;
        }
            
        vmfMetadataSessionSetup = FALSE;
        gpsDataVector.clear();
        buffer.clear();
        [[CameraServer server].delegate setIPAddrLabel:@"Connection is lost"];
            
        //if (locationManager)
        //   [locationManager stopUpdatingLocation];
            
        generatedDataIndex = 0;
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
        
        CFDataRef msgDataRef = (__bridge CFDataRef)(msgData);
        
        __uint32_t bytes = CFDataGetLength(msgDataRef);
        
        NSData* data = [NSData dataWithBytes: &bytes length: sizeof(bytes)];
        CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(data), 2);
        
        if (e)
        {
            NSLog(@"send size %ld", e);
        }
        
        e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgData), 2);
        if (e)
        {
            NSLog(@"send %ld", e);
        }
    }
    else if (([clientResponse caseInsensitiveCompare:@"OK"] == NSOrderedSame))
    {
        buffer.clear();
        gpsDataVector.clear();
        
        [[CameraServer server].delegate setIPAddrLabel:@"Metadata session is setup"];
        //if (locationManager)
          //  [locationManager startUpdatingLocation];
        
        generatedDataIndex = 0;
        
        if (locationGenerationTimer)
        {
            [locationGenerationTimer invalidate];
            locationGenerationTimer = nil;
        }
        
        locationGenerationTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0 target: self selector:@selector(sendNewLocationOnTimer:) userInfo: nil repeats:YES];
        
        vmfMetadataSessionSetup = true;
        vmf::FormatXML xml;
        
        if (_startVideoStreamTime < 0)
            throw "Start time of video streaming isn't initialized!";
        
        std::shared_ptr<vmf::MetadataStream::VideoSegment> segment = std::make_shared<vmf::MetadataStream::VideoSegment>("iOS", 25, _startVideoStreamTime, 0, 720, 480);
        std::shared_ptr<vmf::MetadataSchema> spSchema = vmf::MetadataSchema::getStdSchema();
        
        std::string segmentStr = xml.store({}, {}, {segment});
        std::string schemaStr = xml.store({}, {spSchema});
        
        NSString *segmentMsg = [NSString stringWithUTF8String:segmentStr.c_str()];
        NSData* msgSegData = [segmentMsg dataUsingEncoding:NSUTF8StringEncoding];
        CFDataRef msgSegDataRef = (__bridge CFDataRef)(msgSegData);
        
        __uint32_t segBytes = CFDataGetLength(msgSegDataRef);
        
        NSData* segData = [NSData dataWithBytes: &segBytes length: sizeof(segBytes)];
        CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(segData), 2);

        if (e)
        {
            NSLog(@"send size %ld", e);
        }
        
        e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgSegData), 2);
        if (e)
        {
            NSLog(@"send %ld", e);
        }
        
        NSString *schemaMsg = [NSString stringWithUTF8String:schemaStr.c_str()];
        NSData* msgSchemaData = [schemaMsg dataUsingEncoding:NSUTF8StringEncoding];
        
        CFDataRef msgSchemaDataRef = (__bridge CFDataRef)(msgSchemaData);
        __uint32_t schemaBytes = CFDataGetLength(msgSchemaDataRef);
        
        NSData* schemaData = [NSData dataWithBytes: &schemaBytes length: sizeof(schemaBytes)];
        e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(schemaData), 2);
        
        if (e)
        {
            NSLog(@"send size %ld", e);
        }

        
        e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgSchemaData), 2);
        if (e)
        {
            NSLog(@"send %ld", e);
        }
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
    
    vmf::FormatXML xml;
    vmf::MetadataSet set;
    
    set.push_back(spLocationMetadata);
    std::string mdStr = xml.store(set);
    
    NSString *msg = [NSString stringWithUTF8String:mdStr.c_str()];
    NSData* msgData = [msg dataUsingEncoding:NSUTF8StringEncoding];
    CFDataRef msgDataRef = (__bridge CFDataRef)(msgData);
    __uint32_t size = [msgData length];
    NSLog(@"Size of message is %d", size);
    __uint32_t bytes = size;
    
    NSData* data = [NSData dataWithBytes: &bytes length: sizeof(bytes)];
    
    if (_vmfDataSocket)
    {
        CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(data), 2);
        
        if (e)
        {
            NSLog(@"send %ld", e);
        }
        
        e = CFSocketSendData(_vmfDataSocket, NULL, msgDataRef, 2);
        if (e)
        {
            NSLog(@"send %ld", e);
        }
        generatedDataIndex++;
    }
    
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
    if ([_connections count] == 0)
    {
        @synchronized(self)
        {
            if (_listenerVmf)
            {
                CFSocketInvalidate(_listenerVmf);
                _listenerVmf = nil;
            }
            
            _startVideoStreamTime = -1;
        }
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
            vmfMetadataSessionSetup = false;
        }
        
        if (_listener != nil)
        {
            CFSocketInvalidate(_listener);
            _listener = nil;
        }
        
        if (_listenerVmf != nil)
        {
            CFSocketInvalidate(_listenerVmf);
            _listenerVmf = nil;
        }
        
        if (_vmfRls != nil)
        {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), _vmfRls, kCFRunLoopCommonModes);
            CFRelease(_vmfRls);
        }
        
        _startVideoStreamTime = -1;
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
    long long timeSinceStartInSecond = (currentTime - _startVideoStreamTime)/MILLISEC_PER_SEC;
    
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
    
    vmf::FormatXML xml;
    vmf::MetadataSet set;
    
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
        
        set.push_back(spLocationMetadata);
        std::string mdStr = xml.store(set);
        
        NSString *msg = [NSString stringWithUTF8String:mdStr.c_str()];
        NSData* msgData = [msg dataUsingEncoding:NSUTF8StringEncoding];
        CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgData), 2);
        if (e)
        {
            NSLog(@"send %ld", e);
        }

        //self.counterLabel.text = [NSString stringWithFormat:@"Locations Recorded: %lu", gpsData.size()];
    }
    else if (timeSinceStartInSecond == ((gpsDataVector.back().time - _startVideoStreamTime)/MILLISEC_PER_SEC))
    {
        buffer.push_back (currentLocation);
    }
    else if ((timeSinceStartInSecond > ((gpsDataVector.back ().time - _startVideoStreamTime)/MILLISEC_PER_SEC)))
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
        
        set.push_back(spLocationMetadata);
        std::string mdStr = xml.store(set);
        
        NSString *msg = [NSString stringWithUTF8String:mdStr.c_str()];
        NSData* msgData = [msg dataUsingEncoding:NSUTF8StringEncoding];
        CFSocketError e = CFSocketSendData(_vmfDataSocket, NULL, (__bridge CFDataRef)(msgData), 2);
        if (e)
        {
            NSLog(@"send %ld", e);
        }
        //self.counterLabel.text = [NSString stringWithFormat:@"Locations Recorded: %lu", gpsDataVector.size()];
    }
    
}


@end


