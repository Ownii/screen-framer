#import "CGVirtualDisplayShim.h"

// Private CoreGraphics-Klassen. Bewusst mit SF-Präfix deklariert und nur
// über NSClassFromString aufgelöst: kein Link-Time-Symbol nötig, und bei
// einer API-Änderung durch ein macOS-Update schlägt init kontrolliert
// mit nil fehl statt zur Link-/Ladezeit zu brechen.

@interface SFCGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(double)refreshRate;
@end

@interface SFCGVirtualDisplaySettings : NSObject
@property (nonatomic, strong) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface SFCGVirtualDisplayDescriptor : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@interface SFCGVirtualDisplay : NSObject
@property (readonly, nonatomic) uint32_t displayID;
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@end

@implementation SFVirtualDisplay {
    // Stark referenziert; ARC-Freigabe in dealloc entfernt den virtuellen Bildschirm.
    SFCGVirtualDisplay *_display;
}

- (nullable instancetype)initWithName:(NSString *)name
                           pixelWidth:(NSUInteger)pixelWidth
                          pixelHeight:(NSUInteger)pixelHeight {
    self = [super init];
    if (!self) {
        return nil;
    }

    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descriptorClass || !displayClass || !settingsClass || !modeClass) {
        return nil;
    }

    SFCGVirtualDisplayDescriptor *descriptor =
        (SFCGVirtualDisplayDescriptor *)[[descriptorClass alloc] init];
    descriptor.name = name;
    descriptor.maxPixelsWide = (unsigned int)pixelWidth;
    descriptor.maxPixelsHigh = (unsigned int)pixelHeight;
    // Physische Größe nur für die Monitor-Metadaten (~92 dpi)
    descriptor.sizeInMillimeters =
        CGSizeMake(pixelWidth * 25.4 / 92.0, pixelHeight * 25.4 / 92.0);
    descriptor.productID = 0x5346;
    descriptor.vendorID = 0x5346;
    descriptor.serialNum = 1;
    descriptor.queue = dispatch_get_main_queue();

    SFCGVirtualDisplay *display =
        (SFCGVirtualDisplay *)[[displayClass alloc] initWithDescriptor:descriptor];
    if (!display) {
        return nil;
    }

    SFCGVirtualDisplayMode *mode =
        (SFCGVirtualDisplayMode *)[[modeClass alloc] initWithWidth:pixelWidth
                                                            height:pixelHeight
                                                       refreshRate:60.0];
    if (!mode) {
        return nil;
    }
    SFCGVirtualDisplaySettings *settings =
        (SFCGVirtualDisplaySettings *)[[settingsClass alloc] init];
    settings.hiDPI = 0;
    settings.modes = @[ mode ];
    if (![display applySettings:settings]) {
        return nil;
    }

    _display = display;
    _displayID = display.displayID;
    return self;
}

@end
