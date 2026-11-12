#pragma once
#import <Cocoa/Cocoa.h>
@interface SBApplication : NSObject
+ (id)applicationWithBundleIdentifier:(NSString *)identifier;
@end
@interface SBObject : NSObject
@end
@interface SBElementArray : NSArray
@end
