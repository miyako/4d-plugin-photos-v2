#pragma once
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
typedef struct CGImage *CGImageRef;
typedef struct CGContext *CGContextRef;
extern "C" void CGContextScaleCTM(CGContextRef, CGFloat, CGFloat);
extern "C" void CGContextTranslateCTM(CGContextRef, CGFloat, CGFloat);

// Platform boundaries are replaced before any production source is compiled.
#define NSFileManager OwnershipFileManager
#define NSData OwnershipData
#define NSUUID OwnershipUUID
#define NSURL OwnershipURL
#define NSImage OwnershipImage

@interface OwnershipURL : NSObject
- (id)URLByAppendingPathComponent:(NSString *)component isDirectory:(BOOL)directory;
- (id)initWithString:(NSString *)string;
- (NSString *)absoluteString;
@end
@interface OwnershipFileManager : NSObject
+ (id)defaultManager;
- (NSArray *)URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
- (OwnershipURL *)URLForDirectory:(NSSearchPathDirectory)directory
                        inDomain:(NSSearchPathDomainMask)domain
               appropriateForURL:(OwnershipURL *)url create:(BOOL)create error:(NSError **)error;
- (BOOL)removeItemAtURL:(OwnershipURL *)url error:(NSError **)error;
@end
@interface OwnershipData : NSObject
- (id)initWithContentsOfURL:(OwnershipURL *)url;
- (const void *)bytes;
- (NSUInteger)length;
@end
@interface OwnershipUUID : NSObject
+ (id)UUID;
- (NSString *)UUIDString;
@end
@interface OwnershipImage : NSObject
- (id)initWithCGImage:(CGImageRef)image size:(NSSize)size;
- (OwnershipData *)TIFFRepresentation;
@end
