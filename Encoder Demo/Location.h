//  Copyright (C) 2014, Intel Corporation, all rights reserved.

#ifndef sample_Location_h
#define sample_Location_h
#include <string>
#include <vector>
#import <vmf/vmf.hpp>
#import <CoreLocation/CLLocation.h>
#include <stdio.h>

typedef struct LocationData
{
    CLLocationCoordinate2D coordinate;
    CLLocationAccuracy hAccuracy;
    CLLocationDistance altitude;
    CLLocationSpeed speed;
    long long time;
} LocationData;


int writeVmfGpsCoordinateMetadata (std::string const& path, std::vector<LocationData> const& gpsData, long long startRecordTime)
{
    vmf::MetadataStream outStream;
    std::shared_ptr<vmf::MetadataSchema> spSchema;
    
    try
    {
        if (outStream.open(path, vmf::MetadataStream::Update))
        {
            throw "Failed to open file!";
        }
    }
    catch (...)
    {
	    return -1;
    }
    
    // Add GPS metadata description.
    spSchema = vmf::MetadataSchema::getStdSchema();
    
    // Add schema to stream
    outStream.addSchema(spSchema);

    outStream.addVideoSegment(std::make_shared<vmf::MetadataStream::VideoSegment>("segment1", 30, startRecordTime));
    
    size_t vecSize = gpsData.size();
   
    if (gpsData.empty())
        return -1;

    for (int i = 0; i < vecSize; i++)
    {
        auto spLocationMetadata = std::make_shared<vmf::Metadata>(spSchema->findMetadataDesc("location"));

        spLocationMetadata->setFieldValue("longitude", gpsData[i].coordinate.longitude);
        spLocationMetadata->setFieldValue("latitude", gpsData[i].coordinate.latitude);
        spLocationMetadata->setFieldValue("altitude", gpsData[i].altitude);
        spLocationMetadata->setFieldValue("accuracy", gpsData[i].hAccuracy);
        spLocationMetadata->setFieldValue("speed", gpsData[i].speed);
        spLocationMetadata->setTimestamp(gpsData[i].time);

        outStream.add(spLocationMetadata);
    }
    
    try
    {
        if (!outStream.save())
           throw "Couldn't save message to file!";

        outStream.close();
    }
    catch (...)
    {
        return -1;
    }

    vmf::terminate();
    return 0;
}


#endif
