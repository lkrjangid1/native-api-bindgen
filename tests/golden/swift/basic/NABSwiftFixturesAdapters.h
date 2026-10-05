// GENERATED CODE - DO NOT MODIFY BY HAND.
// Objective-C view of the @objc adapters for `NABSwiftFixtures` (binding input; not compiled).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NABSwiftFixtures_Counter;
@class NABSwiftFixtures_Temperature;

/// Adapter for the Swift type `NABSwiftFixtures.Counter`.
@interface NABSwiftFixtures_Counter : NSObject
@property (nonatomic, readonly) NSInteger value;
@property (nonatomic, strong) NSString *label;
- (instancetype)initWithStart:(NSInteger)start label:(NSString *)label;
- (NSInteger)incrementBy:(NSInteger)step;
- (NSString *)describePrefix:(NSString * _Nullable)prefix;
- (NABSwiftFixtures_Temperature *)temperature;
- (BOOL)isAbove:(NABSwiftFixtures_Temperature *)threshold;
+ (NABSwiftFixtures_Counter *)make;
@property (class, nonatomic, readonly) NSInteger instances;
@end

/// Adapter for the Swift type `NABSwiftFixtures.Temperature`.
@interface NABSwiftFixtures_Temperature : NSObject
@property (nonatomic) double celsius;
- (instancetype)initWithCelsius:(double)celsius;
@property (nonatomic, readonly) double fahrenheit;
- (NABSwiftFixtures_Temperature *)adding:(double)delta;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
