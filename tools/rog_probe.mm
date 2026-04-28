#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDLib.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

static constexpr int kAsusVendorId = 0x0B05;
static constexpr int kRogOmniProductId = 0x1ACE;

static long long intProperty(IOHIDDeviceRef device, CFStringRef key, long long fallback = -1) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return fallback;
    }
    long long result = fallback;
    CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, &result);
    return result;
}

static std::string stringProperty(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (!value || CFGetTypeID(value) != CFStringGetTypeID()) {
        return "";
    }
    char buf[512];
    if (!CFStringGetCString((CFStringRef)value, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        return "";
    }
    return buf;
}

static std::string hexBytes(const uint8_t* data, size_t len, size_t maxLen = 96) {
    std::ostringstream oss;
    size_t shown = std::min(len, maxLen);
    for (size_t i = 0; i < shown; ++i) {
        if (i) oss << ' ';
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)data[i];
    }
    if (len > shown) {
        oss << " ... (" << std::dec << len << " bytes)";
    }
    return oss.str();
}

static void printReportIfInteresting(const char* label, int reportId, IOReturn ret,
                                     const uint8_t* data, CFIndex len) {
    if (ret == kIOReturnSuccess) {
        bool nonZero = false;
        for (CFIndex i = 0; i < len; ++i) {
            if (data[i] != 0) {
                nonZero = true;
                break;
            }
        }
        std::cout << "  " << label << " id=0x" << std::hex << reportId
                  << std::dec << " len=" << len
                  << (nonZero ? " nonzero " : " zero ")
                  << hexBytes(data, (size_t)len) << "\n";
    }
}

static void inputCallback(void* context, IOReturn result, void* sender,
                          IOHIDReportType type, uint32_t reportId,
                          uint8_t* report, CFIndex reportLength) {
    (void)sender;
    if (result != kIOReturnSuccess || type != kIOHIDReportTypeInput) {
        return;
    }
    int* count = static_cast<int*>(context);
    if (*count >= 40) {
        return;
    }
    (*count)++;
    std::cout << "  callback input id=0x" << std::hex << reportId
              << std::dec << " len=" << reportLength << " "
              << hexBytes(report, (size_t)reportLength) << "\n";
}

static const char* reportTypeName(IOHIDReportType type) {
    switch (type) {
        case kIOHIDReportTypeInput:
            return "input";
        case kIOHIDReportTypeOutput:
            return "output";
        case kIOHIDReportTypeFeature:
            return "feature";
        default:
            return "unknown";
    }
}

static void activeQuery(IOHIDDeviceRef device, const char* label, IOHIDReportType type,
                        uint8_t reportId, const std::vector<uint8_t>& packet,
                        size_t reportSize, double waitSeconds = 0.35) {
    if (packet.empty()) {
        return;
    }

    std::vector<uint8_t> output(std::max(reportSize, packet.size()));
    std::copy(packet.begin(), packet.end(), output.begin());

    IOReturn writeRet = IOHIDDeviceSetReport(device,
                                             type,
                                             reportId,
                                             output.data(),
                                             (CFIndex)output.size());
    std::cout << "  query " << label
              << " type=" << reportTypeName(type)
              << " write id=0x" << std::hex << (int)reportId
              << " ret=0x" << writeRet << std::dec
              << " packet=" << hexBytes(packet.data(), packet.size()) << "\n";

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, waitSeconds, false);

    std::vector<uint8_t> input(output.size());
    CFIndex len = (CFIndex)input.size();
    IOReturn readRet = IOHIDDeviceGetReport(device,
                                            kIOHIDReportTypeInput,
                                            reportId,
                                            input.data(),
                                            &len);
    printReportIfInteresting("query get input", reportId, readRet, input.data(), len);

    if (type == kIOHIDReportTypeFeature) {
        std::vector<uint8_t> feature(output.size());
        CFIndex featureLen = (CFIndex)feature.size();
        IOReturn featureRet = IOHIDDeviceGetReport(device,
                                                   kIOHIDReportTypeFeature,
                                                   reportId,
                                                   feature.data(),
                                                   &featureLen);
        printReportIfInteresting("query get feature", reportId, featureRet,
                                 feature.data(), featureLen);
    }
}

int main(int argc, char** argv) {
    int listenSeconds = 8;
    if (argc > 1) {
        listenSeconds = std::max(1, std::atoi(argv[1]));
    }
    int productId = kRogOmniProductId;
    if (argc > 2) {
        productId = (int)std::strtol(argv[2], nullptr, 0);
    }

    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        std::cerr << "Failed to create IOHIDManager\n";
        return 1;
    }

    CFNumberRef vendor = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &kAsusVendorId);
    CFNumberRef product = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &productId);
    const void* keys[] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
    const void* vals[] = { vendor, product };
    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);

    IOReturn openRet = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    if (openRet != kIOReturnSuccess) {
        std::cerr << "IOHIDManagerOpen failed: 0x" << std::hex << openRet << std::dec << "\n";
    }

    CFSetRef deviceSet = IOHIDManagerCopyDevices(manager);
    if (!deviceSet) {
        std::cout << "No ASUS HID devices found for product 0x"
                  << std::hex << productId << std::dec << ".\n";
        CFRelease(match);
        CFRelease(product);
        CFRelease(vendor);
        CFRelease(manager);
        return 0;
    }

    CFIndex count = CFSetGetCount(deviceSet);
    std::vector<const void*> rawDevices((size_t)count);
    CFSetGetValues(deviceSet, rawDevices.data());
    std::vector<IOHIDDeviceRef> devices;
    devices.reserve((size_t)count);
    for (const void* raw : rawDevices) {
        devices.push_back((IOHIDDeviceRef)raw);
    }

    std::cout << "Found " << count << " HID device/interface entries for 0x0b05:0x"
              << std::hex << productId << std::dec << "\n";

    const std::vector<int> reportIds = {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
        0x06, 0x09, 0x0b, 0x52, 0x5f, 0xc0, 0xe0
    };

    std::vector<std::vector<uint8_t>> callbackBuffers;
    std::vector<int> callbackCounts;
    callbackBuffers.resize(devices.size());
    callbackCounts.resize(devices.size());

    for (size_t idx = 0; idx < devices.size(); ++idx) {
        IOHIDDeviceRef device = devices[idx];
        long long usagePage = intProperty(device, CFSTR(kIOHIDPrimaryUsagePageKey));
        long long usage = intProperty(device, CFSTR(kIOHIDPrimaryUsageKey));
        long long maxInput = intProperty(device, CFSTR(kIOHIDMaxInputReportSizeKey), 0);
        long long maxOutput = intProperty(device, CFSTR(kIOHIDMaxOutputReportSizeKey), 0);
        long long maxFeature = intProperty(device, CFSTR(kIOHIDMaxFeatureReportSizeKey), 0);

        std::cout << "\n[" << idx << "] "
                  << stringProperty(device, CFSTR(kIOHIDManufacturerKey)) << " / "
                  << stringProperty(device, CFSTR(kIOHIDProductKey)) << "\n"
                  << "  usagePage=0x" << std::hex << usagePage
                  << " usage=0x" << usage << std::dec
                  << " maxInput=" << maxInput
                  << " maxOutput=" << maxOutput
                  << " maxFeature=" << maxFeature
                  << " serial=" << stringProperty(device, CFSTR(kIOHIDSerialNumberKey)) << "\n";

        IOReturn ret = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
        std::cout << "  open ret=0x" << std::hex << ret << std::dec << "\n";
        if (ret != kIOReturnSuccess) {
            continue;
        }

        size_t inputSize = (size_t)std::max<long long>(maxInput, 1);
        size_t featureSize = (size_t)std::max<long long>(maxFeature, 1);
        inputSize = std::min<size_t>(inputSize, 4097);
        featureSize = std::min<size_t>(featureSize, 4097);

        callbackBuffers[idx].resize(inputSize);
        IOHIDDeviceRegisterInputReportCallback(device,
                                               callbackBuffers[idx].data(),
                                               (CFIndex)callbackBuffers[idx].size(),
                                               inputCallback,
                                               &callbackCounts[idx]);
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

        bool omniControl = (productId == kRogOmniProductId
                            && usagePage == 0x59 && usage == 0x1 && maxOutput >= 1);
        bool vendorControl = ((usagePage == 0xff00 || usagePage == 0xff02)
                              && usage == 0x1 && maxOutput >= 64);
        if (omniControl) {
            activeQuery(device, "omni-pid-output", kIOHIDReportTypeOutput,
                        0x01, {0x01, 0xa0, 0x00, 0x00}, (size_t)maxOutput);
            activeQuery(device, "omni-pid-feature", kIOHIDReportTypeFeature,
                        0x01, {0x01, 0xa0, 0x00, 0x00}, (size_t)std::max<long long>(maxFeature, 1));
        }
        if (vendorControl) {
            activeQuery(device, "omni-keyboard-battery-r2", kIOHIDReportTypeOutput,
                        0x02, {0x02, 0x12, 0x01}, (size_t)maxOutput);
            activeQuery(device, "omni-keyboard-fw-r2", kIOHIDReportTypeOutput,
                        0x02, {0x02, 0x12, 0x00}, (size_t)maxOutput);
            activeQuery(device, "omni-keyboard-layout-r2", kIOHIDReportTypeOutput,
                        0x02, {0x02, 0x12, 0x12}, (size_t)maxOutput);
            activeQuery(device, "keyboard-fw-r0", kIOHIDReportTypeOutput,
                        0x00, {0x00, 0x12, 0x00}, (size_t)maxOutput);
            activeQuery(device, "keyboard-fw-no-id", kIOHIDReportTypeOutput,
                        0x00, {0x12, 0x00}, (size_t)maxOutput);
            activeQuery(device, "keyboard-battery-r0", kIOHIDReportTypeOutput,
                        0x00, {0x00, 0x12, 0x07}, (size_t)maxOutput);
            activeQuery(device, "keyboard-battery-no-id-r0", kIOHIDReportTypeOutput,
                        0x00, {0x12, 0x07}, (size_t)maxOutput);
            activeQuery(device, "keyboard-layout-no-id", kIOHIDReportTypeOutput,
                        0x00, {0x12, 0x12}, (size_t)maxOutput);
            activeQuery(device, "keyboard-unknown-04-no-id", kIOHIDReportTypeOutput,
                        0x00, {0x12, 0x04}, (size_t)maxOutput);
            activeQuery(device, "keyboard-fw-r0-feature", kIOHIDReportTypeFeature,
                        0x00, {0x00, 0x12, 0x00}, (size_t)std::max<long long>(maxFeature, 1));
            activeQuery(device, "keyboard-battery-r0-feature", kIOHIDReportTypeFeature,
                        0x00, {0x00, 0x12, 0x07}, (size_t)std::max<long long>(maxFeature, 1));
            activeQuery(device, "battery", kIOHIDReportTypeOutput,
                        0x03, {0x03, 0x12, 0x07}, (size_t)maxOutput);
            activeQuery(device, "battery-no-id", kIOHIDReportTypeOutput,
                        0x03, {0x12, 0x07}, (size_t)maxOutput);
            activeQuery(device, "booster", kIOHIDReportTypeOutput,
                        0x03, {0x03, 0x7d, 0x20, 0x02}, (size_t)maxOutput);
            activeQuery(device, "serial", kIOHIDReportTypeOutput,
                        0x03, {0x03, 0x12, 0x12, 0x02}, (size_t)maxOutput);
        }

        for (int reportId : reportIds) {
            std::vector<uint8_t> buf(inputSize);
            CFIndex len = (CFIndex)buf.size();
            IOReturn r = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput,
                                              (CFIndex)reportId, buf.data(), &len);
            printReportIfInteresting("get input", reportId, r, buf.data(), len);
        }

        for (int reportId : reportIds) {
            std::vector<uint8_t> buf(featureSize);
            CFIndex len = (CFIndex)buf.size();
            IOReturn r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature,
                                              (CFIndex)reportId, buf.data(), &len);
            printReportIfInteresting("get feature", reportId, r, buf.data(), len);
        }
    }

    std::cout << "\nListening for input reports for " << listenSeconds
              << "s. Press a key on the ROG keyboard if you want to generate traffic.\n";
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, listenSeconds, false);

    for (IOHIDDeviceRef device : devices) {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }

    CFRelease(deviceSet);
    CFRelease(match);
    CFRelease(product);
    CFRelease(vendor);
    IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
    CFRelease(manager);

    return 0;
}
