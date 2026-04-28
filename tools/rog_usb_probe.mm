#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USBSpec.h>

#include <cstdio>
#include <cstring>
#include <iostream>

static bool queryDevice(io_service_t device) {
    IOCFPlugInInterface** plugIn = nullptr;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(device,
                                                         kIOUSBDeviceUserClientTypeID,
                                                         kIOCFPlugInInterfaceID,
                                                         &plugIn,
                                                         &score);
    if (kr != KERN_SUCCESS || !plugIn) {
        std::cout << "device plugin failed 0x" << std::hex << kr << std::dec << "\n";
        return false;
    }

    IOUSBDeviceInterface** usbDevice = nullptr;
    HRESULT hr = (*plugIn)->QueryInterface(plugIn,
                                           CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                                           (LPVOID*)&usbDevice);
    (*plugIn)->Release(plugIn);
    if (hr != S_OK || !usbDevice) {
        std::cout << "device interface failed\n";
        return false;
    }

    (*usbDevice)->USBDeviceOpen(usbDevice);

    UInt8 controlOut[64] = {};
    controlOut[0] = 0x02;
    controlOut[1] = 0x12;
    controlOut[2] = 0x01;
    IOUSBDevRequest setReq;
    setReq.bmRequestType = 0x21;
    setReq.bRequest = 0x09;
    setReq.wValue = 0x0202;
    setReq.wIndex = 0x02;
    setReq.wLength = sizeof(controlOut);
    setReq.pData = controlOut;
    kr = (*usbDevice)->DeviceRequest(usbDevice, &setReq);
    std::cout << "device set output report ret=0x" << std::hex << kr << std::dec << "\n";

    UInt8 controlIn[64] = {};
    IOUSBDevRequest getReq;
    getReq.bmRequestType = 0xA1;
    getReq.bRequest = 0x01;
    getReq.wValue = 0x0102;
    getReq.wIndex = 0x02;
    getReq.wLength = sizeof(controlIn);
    getReq.pData = controlIn;
    kr = (*usbDevice)->DeviceRequest(usbDevice, &getReq);
    std::cout << "device get input report ret=0x" << std::hex << kr << std::dec << "\n";
    if (kr == kIOReturnSuccess) {
        for (int i = 0; i < 64; ++i) {
            std::printf("%02x%s", controlIn[i], (i + 1) % 16 == 0 ? "\n" : " ");
        }
        std::printf("\n");
    }

    IOUSBFindInterfaceRequest request;
    request.bInterfaceClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceSubClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    request.bAlternateSetting = kIOUSBFindInterfaceDontCare;

    io_iterator_t iterator = 0;
    kr = (*usbDevice)->CreateInterfaceIterator(usbDevice, &request, &iterator);
    if (kr != kIOReturnSuccess) {
        std::cout << "interface iterator failed 0x" << std::hex << kr << std::dec << "\n";
        (*usbDevice)->USBDeviceClose(usbDevice);
        (*usbDevice)->Release(usbDevice);
        return false;
    }

    bool success = false;
    io_service_t interfaceService = 0;
    while ((interfaceService = IOIteratorNext(iterator)) != 0) {
        IOCFPlugInInterface** interfacePlugIn = nullptr;
        SInt32 interfaceScore = 0;
        kr = IOCreatePlugInInterfaceForService(interfaceService,
                                               kIOUSBInterfaceUserClientTypeID,
                                               kIOCFPlugInInterfaceID,
                                               &interfacePlugIn,
                                               &interfaceScore);
        if (kr != KERN_SUCCESS || !interfacePlugIn) {
            IOObjectRelease(interfaceService);
            continue;
        }

        IOUSBInterfaceInterface** interface = nullptr;
        hr = (*interfacePlugIn)->QueryInterface(interfacePlugIn,
                                                CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                                                (LPVOID*)&interface);
        (*interfacePlugIn)->Release(interfacePlugIn);
        if (hr != S_OK || !interface) {
            IOObjectRelease(interfaceService);
            continue;
        }

        UInt8 interfaceNumber = 0;
        (*interface)->GetInterfaceNumber(interface, &interfaceNumber);
        std::cout << "interface " << (int)interfaceNumber << "\n";
        if (interfaceNumber != 2) {
            (*interface)->Release(interface);
            IOObjectRelease(interfaceService);
            continue;
        }

        kr = (*interface)->USBInterfaceOpen(interface);
        std::cout << "open interface ret=0x" << std::hex << kr << std::dec << "\n";
        if (kr == kIOReturnExclusiveAccess) {
            UInt8 ifaceOut[64] = {};
            ifaceOut[0] = 0x02;
            ifaceOut[1] = 0x12;
            ifaceOut[2] = 0x01;
            IOUSBDevRequest ifaceSetReq;
            ifaceSetReq.bmRequestType = 0x21;
            ifaceSetReq.bRequest = 0x09;
            ifaceSetReq.wValue = 0x0202;
            ifaceSetReq.wIndex = 0x02;
            ifaceSetReq.wLength = sizeof(ifaceOut);
            ifaceSetReq.pData = ifaceOut;
            IOReturn controlRet = (*interface)->ControlRequest(interface, 0, &ifaceSetReq);
            std::cout << "interface control set ret=0x" << std::hex << controlRet << std::dec << "\n";

            UInt8 ifaceIn[64] = {};
            IOUSBDevRequest ifaceGetReq;
            ifaceGetReq.bmRequestType = 0xA1;
            ifaceGetReq.bRequest = 0x01;
            ifaceGetReq.wValue = 0x0102;
            ifaceGetReq.wIndex = 0x02;
            ifaceGetReq.wLength = sizeof(ifaceIn);
            ifaceGetReq.pData = ifaceIn;
            controlRet = (*interface)->ControlRequest(interface, 0, &ifaceGetReq);
            std::cout << "interface control get ret=0x" << std::hex << controlRet << std::dec << "\n";
            if (controlRet == kIOReturnSuccess) {
                for (int i = 0; i < 64; ++i) {
                    std::printf("%02x%s", ifaceIn[i], (i + 1) % 16 == 0 ? "\n" : " ");
                }
                std::printf("\n");
            }

            kr = (*interface)->USBInterfaceOpenSeize(interface);
            std::cout << "open seize ret=0x" << std::hex << kr << std::dec << "\n";
        }
        if (kr != kIOReturnSuccess) {
            (*interface)->Release(interface);
            IOObjectRelease(interfaceService);
            continue;
        }

        UInt8 endpointCount = 0;
        (*interface)->GetNumEndpoints(interface, &endpointCount);
        UInt8 inPipe = 0;
        UInt8 outPipe = 0;
        for (UInt8 pipe = 1; pipe <= endpointCount; ++pipe) {
            UInt8 direction = 0;
            UInt8 number = 0;
            UInt8 transferType = 0;
            UInt16 maxPacketSize = 0;
            UInt8 interval = 0;
            kr = (*interface)->GetPipeProperties(interface, pipe, &direction, &number,
                                                 &transferType, &maxPacketSize, &interval);
            if (kr != kIOReturnSuccess) {
                continue;
            }
            std::cout << "pipe " << (int)pipe
                      << " dir=" << (int)direction
                      << " num=0x" << std::hex << (int)number
                      << " type=" << std::dec << (int)transferType
                      << " max=" << maxPacketSize << "\n";
            if (transferType == kUSBInterrupt && direction == kUSBIn && number == 3) {
                inPipe = pipe;
            } else if (transferType == kUSBInterrupt && direction == kUSBOut && number == 3) {
                outPipe = pipe;
            }
        }

        if (!inPipe || !outPipe) {
            std::cout << "missing pipes in=" << (int)inPipe << " out=" << (int)outPipe << "\n";
            (*interface)->USBInterfaceClose(interface);
            (*interface)->Release(interface);
            IOObjectRelease(interfaceService);
            continue;
        }

        UInt8 flush[64];
        UInt32 flushSize = sizeof(flush);
        while ((*interface)->ReadPipeTO(interface, inPipe, flush, &flushSize, 1, 1) == kIOReturnSuccess) {
            flushSize = sizeof(flush);
        }

        UInt8 out[64] = {};
        out[0] = 0x02;
        out[1] = 0x12;
        out[2] = 0x01;
        kr = (*interface)->WritePipeTO(interface, outPipe, out, sizeof(out), 1000, 1000);
        std::cout << "write ret=0x" << std::hex << kr << std::dec << "\n";
        if (kr == kIOReturnSuccess) {
            UInt8 in[64] = {};
            UInt32 inSize = sizeof(in);
            kr = (*interface)->ReadPipeTO(interface, inPipe, in, &inSize, 1000, 1000);
            std::cout << "read ret=0x" << std::hex << kr << std::dec << " size=" << inSize << "\n";
            if (kr == kIOReturnSuccess) {
                for (UInt32 i = 0; i < inSize; ++i) {
                    std::printf("%02x%s", in[i], (i + 1) % 16 == 0 ? "\n" : " ");
                }
                std::printf("\n");
                success = inSize >= 12 && in[0] == 0x02 && in[1] == 0x12 && in[2] == 0x01 && in[6] <= 100;
            }
        }

        (*interface)->USBInterfaceClose(interface);
        (*interface)->Release(interface);
        IOObjectRelease(interfaceService);
        break;
    }

    IOObjectRelease(iterator);
    (*usbDevice)->USBDeviceClose(usbDevice);
    (*usbDevice)->Release(usbDevice);
    return success;
}

int main() {
    int vid = 0x0B05;
    int pid = 0x1ACE;
    CFMutableDictionaryRef dict = IOServiceMatching("IOUSBHostDevice");
    CFNumberRef vidRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef pidRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    CFDictionarySetValue(dict, CFSTR(kUSBVendorID), vidRef);
    CFDictionarySetValue(dict, CFSTR(kUSBProductID), pidRef);
    CFRelease(vidRef);
    CFRelease(pidRef);

    io_iterator_t iterator = 0;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, dict, &iterator);
    if (kr != KERN_SUCCESS) {
        std::cout << "matching failed\n";
        return 1;
    }

    io_service_t device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!device) {
        std::cout << "device not found\n";
        return 1;
    }
    bool ok = queryDevice(device);
    IOObjectRelease(device);
    std::cout << "success=" << ok << "\n";
    return ok ? 0 : 2;
}
