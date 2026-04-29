#import <Cocoa/Cocoa.h>
#import <IOKit/hid/IOHIDLib.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <UserNotifications/UserNotifications.h>
#import "RazerDevice.hpp"

#include <dlfcn.h>
#include <vector>

static NSString* const kAppName = @"Peripheral Battery";
static NSString* const kAppGroupIdentifier = @"group.com.young.peripheralbattery";
static NSString* const kBatterySnapshotDefaultsKey = @"batterySnapshot";
static NSTimeInterval const kNormalRefreshInterval = 60.0;
static NSTimeInterval const kRetryRefreshInterval = 10.0;

struct DeviceBatteryStatus {
    bool available;
    uint8_t battery;
    bool charging;
    bool needsPermission;
};

struct RogInputContext {
    bool received;
    uint8_t battery;
};

static id batteryLevelValue(DeviceBatteryStatus status) {
    if (!status.available || status.battery == 0) {
        return [NSNull null];
    }
    return @(status.battery);
}

static NSDictionary* batterySnapshotDevice(NSString* name,
                                           NSString* symbolName,
                                           DeviceBatteryStatus status) {
    return @{
        @"name": name,
        @"symbolName": symbolName,
        @"level": batteryLevelValue(status),
        @"isCharging": @(status.charging)
    };
}

static void reloadWidgetTimelinesIfAvailable() {
    using ReloadTimelinesFn = void (*)();
    void* symbol = dlsym(RTLD_DEFAULT, "reloadPeripheralBatteryWidgetTimelines");
    if (!symbol) {
        return;
    }
    reinterpret_cast<ReloadTimelinesFn>(symbol)();
}

static void writeSharedBatterySnapshot(DeviceBatteryStatus mouse, DeviceBatteryStatus keyboard) {
    NSDictionary* snapshot = @{
        @"mouse": batterySnapshotDevice(@"Razer DeathAdder V3 Pro", @"computermouse.fill", mouse),
        @"keyboard": batterySnapshotDevice(@"ROG Falchion RX Low Profile", @"keyboard.fill", keyboard),
        @"updatedAt": @([[NSDate date] timeIntervalSince1970])
    };

    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
    if (!data || error) {
        NSLog(@"Failed to encode widget battery snapshot: %@", error);
        return;
    }

    NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!json) {
        return;
    }

    NSUserDefaults* sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroupIdentifier];
    if (sharedDefaults) {
        [sharedDefaults setObject:json forKey:kBatterySnapshotDefaultsKey];
        [sharedDefaults synchronize];
    } else {
        NSLog(@"Failed to resolve shared defaults suite for widget battery snapshot");
    }

    reloadWidgetTimelinesIfAvailable();
}

static long long hidIntProperty(IOHIDDeviceRef device, CFStringRef key, long long fallback = -1) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return fallback;
    }
    long long result = fallback;
    CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, &result);
    return result;
}

static bool isInputMonitoringError(IOReturn result) {
    return result == kIOReturnNotPermitted || result == kIOReturnNotPrivileged;
}

static void rogInputCallback(void* context, IOReturn result, void* sender,
                             IOHIDReportType type, uint32_t reportId,
                             uint8_t* report, CFIndex reportLength) {
    (void)sender;
    if (result != kIOReturnSuccess || type != kIOHIDReportTypeInput || reportId != 0x02) {
        return;
    }
    if (reportLength < 12 || report[0] != 0x02 || report[1] != 0x12 || report[2] != 0x01) {
        return;
    }
    if (report[6] > 100) {
        return;
    }

    RogInputContext* inputContext = static_cast<RogInputContext*>(context);
    inputContext->battery = report[6];
    inputContext->received = true;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static bool queryRogFalchionBattery(uint8_t& batteryPercent, bool& needsInputMonitoring) {
    static constexpr int kAsusVendorId = 0x0B05;
    static constexpr int kRogOmniProductId = 0x1ACE;
    static constexpr size_t kReportSize = 64;
    static constexpr uint8_t kReportId = 0x02;

    needsInputMonitoring = false;

    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        return false;
    }

    CFNumberRef vendor = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &kAsusVendorId);
    CFNumberRef product = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &kRogOmniProductId);
    const void* keys[] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
    const void* vals[] = { vendor, product };
    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, match);

    bool success = false;
    IOReturn managerOpen = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    if (managerOpen == kIOReturnSuccess) {
        CFSetRef deviceSet = IOHIDManagerCopyDevices(manager);
        if (deviceSet) {
            CFIndex count = CFSetGetCount(deviceSet);
            std::vector<const void*> rawDevices((size_t)count);
            CFSetGetValues(deviceSet, rawDevices.data());

            for (const void* rawDevice : rawDevices) {
                IOHIDDeviceRef device = (IOHIDDeviceRef)rawDevice;
                long long usagePage = hidIntProperty(device, CFSTR(kIOHIDPrimaryUsagePageKey));
                long long usage = hidIntProperty(device, CFSTR(kIOHIDPrimaryUsageKey));
                long long maxInput = hidIntProperty(device, CFSTR(kIOHIDMaxInputReportSizeKey), 0);
                long long maxOutput = hidIntProperty(device, CFSTR(kIOHIDMaxOutputReportSizeKey), 0);

                if (usagePage != 0xff02 || usage != 0x1 || maxInput < 64 || maxOutput < 64) {
                    continue;
                }
                IOReturn openRet = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
                if (openRet != kIOReturnSuccess) {
                    if (isInputMonitoringError(openRet)) {
                        needsInputMonitoring = true;
                    }
                    continue;
                }

                RogInputContext inputContext = { false, 0 };
                uint8_t inputReport[kReportSize] = {};
                IOHIDDeviceRegisterInputReportCallback(device, inputReport, kReportSize,
                                                       rogInputCallback, &inputContext);
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

                auto sendRogReport = ^(uint8_t command) {
                    uint8_t outputReport[kReportSize] = {};
                    outputReport[0] = kReportId;
                    outputReport[1] = 0x12;
                    outputReport[2] = command;
                    return IOHIDDeviceSetReport(device,
                                                kIOHIDReportTypeOutput,
                                                kReportId,
                                                outputReport,
                                                kReportSize);
                };

                for (int attempt = 0; attempt < 3 && !inputContext.received; ++attempt) {
                    IOReturn batteryWrite = sendRogReport(0x01);
                    if (batteryWrite == kIOReturnSuccess) {
                        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.75, false);
                    }
                    if (!inputContext.received) {
                        IOReturn wakeWrite = sendRogReport(0x00);
                        if (wakeWrite == kIOReturnSuccess) {
                            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
                        }
                    }
                }

                IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
                IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);

                if (inputContext.received) {
                    batteryPercent = inputContext.battery;
                    success = true;
                    break;
                }
            }
            CFRelease(deviceSet);
        }
    } else if (isInputMonitoringError(managerOpen)) {
        needsInputMonitoring = true;
    }

    IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
    CFRelease(match);
    CFRelease(product);
    CFRelease(vendor);
    CFRelease(manager);
    return success;
}

@interface BatteryMenuApp : NSObject <NSApplicationDelegate> {
    NSStatusItem* statusItem_;
    NSMenuItem* statusMenuItem_;
    NSMenuItem* deviceMenuItem_;
    NSMenuItem* keyboardMenuItem_;
    RazerDevice* razerDevice_;
    NSTimer* refreshTimer_;
    dispatch_queue_t batteryQueue_;
    uint8_t lastBatteryLevel_;
    uint8_t lastKeyboardBatteryLevel_;
    bool lastChargingState_;
    bool lowBatteryNotificationShown_;
    bool keyboardLowBatteryNotificationShown_;
}

- (void)refreshNow:(id)sender;
- (void)openLoginItems:(id)sender;
- (void)openInputMonitoringSettings:(id)sender;
- (void)handleUSBEvent;
- (void)connectAndRefresh;
- (DeviceBatteryStatus)queryRazerBattery;
- (void)updateDisplayWithMouse:(DeviceBatteryStatus)mouse keyboard:(DeviceBatteryStatus)keyboard;
- (void)showUnavailableState:(NSString*)status retrySoon:(BOOL)retrySoon;
- (NSImage*)menuBarBoltIcon;
- (BOOL)canUseUserNotifications;
- (void)requestNotificationPermission;
- (void)showLowBatteryNotificationForDevice:(NSString*)device battery:(uint8_t)battery identifier:(NSString*)identifier;
- (void)scheduleRefresh:(NSTimeInterval)interval;
@end

static void onDeviceChange(void* context) {
    BatteryMenuApp* app = (__bridge BatteryMenuApp*)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        [app handleUSBEvent];
    });
}

@implementation BatteryMenuApp

- (instancetype)init {
    self = [super init];
    if (self) {
        razerDevice_ = new RazerDevice();
        batteryQueue_ = dispatch_queue_create("com.young.peripheralbattery.usb", DISPATCH_QUEUE_SERIAL);
        lastBatteryLevel_ = 0;
        lastKeyboardBatteryLevel_ = 0;
        lastChargingState_ = false;
        lowBatteryNotificationShown_ = false;
        keyboardLowBatteryNotificationShown_ = false;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    statusItem_ = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusItem_.button.image = [self menuBarBoltIcon];
    statusItem_.button.imagePosition = NSImageOnly;
    statusItem_.button.title = @"";
    statusItem_.button.toolTip = kAppName;

    NSMenu* menu = [[NSMenu alloc] initWithTitle:kAppName];

    deviceMenuItem_ = [[NSMenuItem alloc] initWithTitle:@"Razer DeathAdder V3 Pro"
                                                 action:nil
                                          keyEquivalent:@""];
    deviceMenuItem_.enabled = NO;
    [menu addItem:deviceMenuItem_];

    keyboardMenuItem_ = [[NSMenuItem alloc] initWithTitle:@"ROG Falchion RX Low Profile"
                                                   action:nil
                                            keyEquivalent:@""];
    keyboardMenuItem_.enabled = NO;
    [menu addItem:keyboardMenuItem_];

    statusMenuItem_ = [[NSMenuItem alloc] initWithTitle:@"Starting..."
                                                 action:nil
                                          keyEquivalent:@""];
    statusMenuItem_.enabled = NO;
    [menu addItem:statusMenuItem_];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* refreshItem = [[NSMenuItem alloc] initWithTitle:@"Refresh"
                                                         action:@selector(refreshNow:)
                                                  keyEquivalent:@"r"];
    refreshItem.target = self;
    [menu addItem:refreshItem];

    NSMenuItem* loginItem = [[NSMenuItem alloc] initWithTitle:@"Open at Login..."
                                                       action:@selector(openLoginItems:)
                                                keyEquivalent:@""];
    loginItem.target = self;
    [menu addItem:loginItem];

    NSMenuItem* inputMonitoringItem = [[NSMenuItem alloc] initWithTitle:@"Input Monitoring Settings..."
                                                                 action:@selector(openInputMonitoringSettings:)
                                                          keyEquivalent:@""];
    inputMonitoringItem.target = self;
    [menu addItem:inputMonitoringItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [menu addItem:quitItem];

    statusItem_.menu = menu;

    razerDevice_->startMonitoring(onDeviceChange, (__bridge void*)self);
    [self requestNotificationPermission];

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:self
           selector:@selector(systemWillSleep:)
               name:NSWorkspaceWillSleepNotification
             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserver:self
           selector:@selector(systemDidWake:)
               name:NSWorkspaceDidWakeNotification
             object:nil];

    [self connectAndRefresh];
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;

    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

    if (refreshTimer_) {
        [refreshTimer_ invalidate];
        refreshTimer_ = nil;
    }

    if (razerDevice_) {
        razerDevice_->stopMonitoring();
        razerDevice_->disconnect();
        delete razerDevice_;
        razerDevice_ = nullptr;
    }
}

- (void)systemWillSleep:(NSNotification*)notification {
    (void)notification;
    if (refreshTimer_) {
        [refreshTimer_ invalidate];
        refreshTimer_ = nil;
    }
    if (razerDevice_) {
        razerDevice_->disconnect();
    }
}

- (void)systemDidWake:(NSNotification*)notification {
    (void)notification;
    [self performSelector:@selector(connectAndRefresh) withObject:nil afterDelay:2.0];
}

- (void)refreshNow:(id)sender {
    (void)sender;
    [self connectAndRefresh];
}

- (void)openLoginItems:(id)sender {
    (void)sender;
    NSURL* url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.LoginItems-Settings.extension"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openInputMonitoringSettings:(id)sender {
    (void)sender;
    NSURL* url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)handleUSBEvent {
    [self connectAndRefresh];
}

- (void)scheduleRefresh:(NSTimeInterval)interval {
    if (refreshTimer_) {
        [refreshTimer_ invalidate];
        refreshTimer_ = nil;
    }

    refreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:interval
                                                     target:self
                                                   selector:@selector(refreshNow:)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)connectAndRefresh {
    if (!razerDevice_) {
        [self showUnavailableState:@"Device layer unavailable" retrySoon:YES];
        return;
    }

    statusMenuItem_.title = @"Refreshing...";

    __weak BatteryMenuApp* weakSelf = self;
    dispatch_async(batteryQueue_, ^{
        BatteryMenuApp* strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->razerDevice_) {
            return;
        }

        DeviceBatteryStatus mouse = [strongSelf queryRazerBattery];

        dispatch_async(dispatch_get_main_queue(), ^{
            BatteryMenuApp* mainSelf = weakSelf;
            if (!mainSelf) {
                return;
            }

            DeviceBatteryStatus keyboard = { false, 0, false, false };
            uint8_t keyboardBattery = 0;
            bool keyboardNeedsPermission = false;
            if (queryRogFalchionBattery(keyboardBattery, keyboardNeedsPermission)) {
                keyboard.available = true;
                keyboard.battery = keyboardBattery;
                NSLog(@"ROG Falchion battery query succeeded: %u%%", keyboardBattery);
            } else if (keyboardNeedsPermission) {
                keyboard.needsPermission = true;
                NSLog(@"ROG Falchion battery query needs Input Monitoring permission");
            } else if (mainSelf->lastKeyboardBatteryLevel_ > 0) {
                keyboard.available = true;
                keyboard.battery = mainSelf->lastKeyboardBatteryLevel_;
                NSLog(@"ROG Falchion battery query reused cached value: %u%%", keyboard.battery);
            } else {
                NSLog(@"ROG Falchion battery query failed with no cached value");
            }

            if (mouse.available || keyboard.available) {
                [mainSelf updateDisplayWithMouse:mouse keyboard:keyboard];
                BOOL keyboardNeedsRetry = !keyboard.available && !keyboard.needsPermission && mainSelf->lastKeyboardBatteryLevel_ == 0;
                [mainSelf scheduleRefresh:(keyboardNeedsRetry ? kRetryRefreshInterval : kNormalRefreshInterval)];
            } else if (keyboard.needsPermission) {
                [mainSelf updateDisplayWithMouse:mouse keyboard:keyboard];
                [mainSelf scheduleRefresh:kNormalRefreshInterval];
            } else {
                [mainSelf showUnavailableState:@"No supported device battery found" retrySoon:YES];
            }
        });
    });
}

- (DeviceBatteryStatus)queryRazerBattery {
    DeviceBatteryStatus status = { false, 0, false, false };

    if (!razerDevice_->isConnected()) {
        razerDevice_->disconnect();
        if (!razerDevice_->connect()) {
            if (lastBatteryLevel_ > 0) {
                status.available = true;
                status.battery = lastBatteryLevel_;
            }
            return status;
        }
    }

    uint8_t batteryPercent = 0;
    bool batteryOK = razerDevice_->queryBattery(batteryPercent);

    bool isCharging = false;
    razerDevice_->queryChargingStatus(isCharging);
    if (!isCharging && razerDevice_->isWiredDevicePresent()) {
        isCharging = true;
    }

    uint8_t displayLevel = batteryOK && batteryPercent > 0 ? batteryPercent : lastBatteryLevel_;
    if (displayLevel > 0 || isCharging) {
        status.available = true;
        status.battery = displayLevel;
        status.charging = isCharging;
    }

    return status;
}

- (void)updateDisplayWithMouse:(DeviceBatteryStatus)mouse keyboard:(DeviceBatteryStatus)keyboard {
    if (mouse.available && mouse.battery > 0) {
        lastBatteryLevel_ = mouse.battery;
        lastChargingState_ = mouse.charging;
    }
    if (keyboard.available) {
        lastKeyboardBatteryLevel_ = keyboard.battery;
    }

    NSMutableArray<NSString*>* tooltipParts = [NSMutableArray array];

    if (mouse.available) {
        NSString* mode = mouse.charging ? @"Charging" : @"Wireless";
        if (mouse.battery > 0) {
            deviceMenuItem_.title = [NSString stringWithFormat:@"Razer DeathAdder V3 Pro — %@ — %u%%", mode, mouse.battery];
            [tooltipParts addObject:deviceMenuItem_.title];
        } else {
            deviceMenuItem_.title = @"Razer DeathAdder V3 Pro — Charging";
            [tooltipParts addObject:deviceMenuItem_.title];
        }
    } else {
        deviceMenuItem_.title = @"Razer DeathAdder V3 Pro — Not found";
    }

    if (keyboard.available) {
        keyboardMenuItem_.title = [NSString stringWithFormat:@"ROG Falchion RX Low Profile — Wireless — %u%%", keyboard.battery];
        [tooltipParts addObject:keyboardMenuItem_.title];
    } else if (keyboard.needsPermission) {
        keyboardMenuItem_.title = @"ROG Falchion RX Low Profile — Needs Input Monitoring";
        [tooltipParts addObject:keyboardMenuItem_.title];
    } else if (lastKeyboardBatteryLevel_ > 0) {
        keyboardMenuItem_.title = [NSString stringWithFormat:@"ROG Falchion RX Low Profile — Wireless — %u%%", lastKeyboardBatteryLevel_];
        [tooltipParts addObject:keyboardMenuItem_.title];
    } else {
        keyboardMenuItem_.title = @"ROG Falchion RX Low Profile — Checking...";
    }

    statusItem_.button.image = [self menuBarBoltIcon];
    statusItem_.button.imagePosition = NSImageOnly;
    statusItem_.button.title = @"";
    statusItem_.button.attributedTitle = nil;

    NSString* detail = [tooltipParts componentsJoinedByString:@" / "];
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    statusMenuItem_.title = [NSString stringWithFormat:@"Updated %@", [formatter stringFromDate:[NSDate date]]];
    statusItem_.button.toolTip = detail;
    writeSharedBatterySnapshot(mouse, keyboard);

    if (mouse.available && mouse.battery <= 20 && mouse.battery > 0 && !mouse.charging && !lowBatteryNotificationShown_) {
        [self showLowBatteryNotificationForDevice:@"Razer DeathAdder V3 Pro" battery:mouse.battery identifier:@"deathadder-low-battery"];
        lowBatteryNotificationShown_ = true;
    } else if (!mouse.available || mouse.battery > 20 || mouse.charging) {
        lowBatteryNotificationShown_ = false;
    }

    if (keyboard.available && keyboard.battery <= 20 && !keyboardLowBatteryNotificationShown_) {
        [self showLowBatteryNotificationForDevice:@"ROG Falchion RX Low Profile" battery:keyboard.battery identifier:@"falchion-low-battery"];
        keyboardLowBatteryNotificationShown_ = true;
    } else if (!keyboard.available || keyboard.battery > 20) {
        keyboardLowBatteryNotificationShown_ = false;
    }

    NSLog(@"Battery updated: %@", detail);
}

- (void)showUnavailableState:(NSString*)status retrySoon:(BOOL)retrySoon {
    statusItem_.button.image = [self menuBarBoltIcon];
    statusItem_.button.imagePosition = NSImageOnly;
    statusItem_.button.title = @"";
    statusItem_.button.attributedTitle = nil;
    statusItem_.button.toolTip = [NSString stringWithFormat:@"Peripheral Battery — %@", status];
    statusMenuItem_.title = status;
    [self scheduleRefresh:(retrySoon ? kRetryRefreshInterval : kNormalRefreshInterval)];
}

- (NSImage*)menuBarBoltIcon {
    if (@available(macOS 11.0, *)) {
        NSImage* icon = [NSImage imageWithSystemSymbolName:@"bolt.fill"
                                   accessibilityDescription:@"Peripheral Battery"];
        if (icon) {
            [icon setTemplate:YES];
            return icon;
        }
    }
    return nil;
}

- (void)requestNotificationPermission {
    if (![self canUseUserNotifications]) {
        NSLog(@"Skipping notification permission outside app bundle");
        return;
    }

    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted, NSError* error) {
        if (error) {
            NSLog(@"Notification authorization failed: %@", error);
        } else {
            NSLog(@"Notification authorization granted: %d", granted);
        }
    }];
}

- (void)showLowBatteryNotificationForDevice:(NSString*)device battery:(uint8_t)battery identifier:(NSString*)identifier {
    if (![self canUseUserNotifications]) {
        return;
    }

    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Battery Low";
    content.body = [NSString stringWithFormat:@"%@ battery is %u%%.", device, battery];
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError* error) {
        if (error) {
            NSLog(@"Low battery notification failed: %@", error);
        }
    }];
}

- (BOOL)canUseUserNotifications {
    NSURL* bundleURL = [[NSBundle mainBundle] bundleURL];
    return [[[bundleURL pathExtension] lowercaseString] isEqualToString:@"app"];
}

@end

int main(int argc, const char* argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        BatteryMenuApp* delegate = [[BatteryMenuApp alloc] init];
        app.delegate = delegate;
        [app run];
    }

    return 0;
}
