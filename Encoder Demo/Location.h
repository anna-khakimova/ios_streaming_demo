//  Copyright (C) 2014, Intel Corporation, all rights reserved.

#ifndef sample_Location_h
#define sample_Location_h
#include <string>
#include <vector>
#import <vmf/vmf.hpp>
#import <CoreLocation/CLLocation.h>
#include <stdio.h>

typedef struct
{
    CLLocationCoordinate2D coordinate;
    CLLocationAccuracy hAccurcy;
    CLLocationDistance altitude;
    CLLocationSpeed speed;
    long long time;
} LocationData;

struct vmfInfo
{
	vmf::MetadataStream outStream;
	std::string sSchemaName;
	std::shared_ptr<vmf::MetadataSchema> spSchema;
};

int writeVmfGpsCoordinateMetadata (std::string const& path, std::vector<LocationData> const& gpsData, long long startRecordTime)
{
    struct vmfInfo* pVmfInfo = new vmfInfo;
    
    vmf::initialize ();

    vmf::Log::logToConsole();
    vmf::Log::setVerbosityLevel(vmf::LOG_INFO);
    
    try
    {
        if (!pVmfInfo->outStream.open(path, vmf::MetadataStream::ReadWrite))
        {
	    throw "Failed to open file!";
	}
    }
    catch (...)
    {
        delete pVmfInfo;
        pVmfInfo = NULL;
	    return 0;
    }
    
    // Add GPS metadata description.
    pVmfInfo->spSchema = vmf::MetadataSchema::getStdSchema();
    
    // Add schema to stream
    pVmfInfo->outStream.addSchema(pVmfInfo->spSchema);

    pVmfInfo->outStream.addVideoSegment(std::make_shared<vmf::MetadataStream::VideoSegment>("segment1", 30, startRecordTime));
    
    unsigned long vectorSize = gpsData.size();
   
    if (vectorSize == 0)
        return -1;

    for (int i = 0; i < vectorSize; i++)
    {
        auto spLocationMetadata = std::shared_ptr <vmf::Metadata> (new vmf::Metadata(pVmfInfo->spSchema->findMetadataDesc("location")));

        spLocationMetadata->setFieldValue("longitude", gpsData[i].coordinate.longitude);
        spLocationMetadata->setFieldValue("latitude", gpsData[i].coordinate.latitude);
        spLocationMetadata->setFieldValue("altitude", gpsData[i].altitude);
        spLocationMetadata->setFieldValue("accuracy", gpsData[i].hAccurcy);
        spLocationMetadata->setFieldValue("speed", gpsData[i].speed);
        spLocationMetadata->setTimestamp(gpsData[i].time);

        pVmfInfo->outStream.add(spLocationMetadata);
    }
    
    try
    {
        if (!pVmfInfo->outStream.save())
           throw "Couldn't save message to file!";

        pVmfInfo->outStream.close();
    }
    catch (...)
    {
        delete pVmfInfo;
	    return -1;
    }

    vmf::terminate();
    delete pVmfInfo;
    return 0;
}


#endif
