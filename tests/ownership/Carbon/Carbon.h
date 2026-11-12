#pragma once
#import <Cocoa/Cocoa.h>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#define pascal
#define errAEEventWouldRequireUserConsent errAEEventWouldRequireUserConsent
#define AECreateDesc OwnershipAECreateDesc
#define AEDeterminePermissionToAutomateTarget OwnershipAEPermission
#define AEDisposeDesc OwnershipAEDisposeDesc
inline OSStatus OwnershipAECreateDesc(int, const void *, size_t, AEAddressDesc *) {
    throw std::runtime_error("authorization forbidden");
}
inline OSStatus OwnershipAEPermission(AEAddressDesc *, int, int, bool) {
    throw std::runtime_error("authorization forbidden");
}
inline OSStatus OwnershipAEDisposeDesc(AEAddressDesc *) {
    throw std::runtime_error("authorization forbidden");
}
