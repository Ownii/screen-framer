#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Kapselt die private CGVirtualDisplay-API vollständig.
/// Solange die Instanz lebt, existiert der virtuelle Bildschirm;
/// die Freigabe der Instanz entfernt ihn wieder.
/// init gibt nil zurück, wenn die private API nicht (mehr) verfügbar ist
/// oder die Erzeugung fehlschlägt.
@interface SFVirtualDisplay : NSObject

@property (readonly, nonatomic) CGDirectDisplayID displayID;

- (nullable instancetype)initWithName:(NSString *)name
                           pixelWidth:(NSUInteger)pixelWidth
                          pixelHeight:(NSUInteger)pixelHeight;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
