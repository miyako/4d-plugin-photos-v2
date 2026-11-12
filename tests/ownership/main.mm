#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include "4DPlugin.h"
#include <algorithm>
#include <functional>
#include <iostream>
#include <set>
#include <type_traits>

namespace {
using Text = std::basic_string<PA_Unichar>;
std::map<PA_Unichar *, Text> strings;
std::map<PA_Handle, size_t> handles;
std::map<PA_Picture, int> pictures;
int checks = 0, failures = 0, badDisposals = 0;
int selectionCalls = 0, exports = 0, removals = 0, callbacks = 0, createdProcesses = 0;
int fakeObjects = 0, failCommand = 0, callbackKind = eVK_Boolean;
int logCalls = 0;
Text expectedFormat(reinterpret_cast<const PA_Unichar *>(u".png"));
bool failResize = false, failHandle = false, haveData = true, abortCallback = false;
bool allocatedEmpty = true, failedOutputInspected = false;
bool failPictureData = false, failConversion = false;
void (*processEntry)() = nullptr;
NSString *fixture = @"";
NSArray *selection = nil;
Text expected;

void check(bool value, const char *name) {
    ++checks;
    if (!value) { ++failures; std::cerr << "FAIL " << name << "\n"; }
}
void require(bool value, const char *name) {
    if (!value) throw std::runtime_error(name);
}
PA_Unistring make(const PA_Unichar *p) {
    Text text(p ? p : reinterpret_cast<const PA_Unichar *>(u""));
    PA_Unistring s = {};
    s.fLength = static_cast<PA_long32>(text.size());
    if (text.empty() && !allocatedEmpty) return s;
    s.fString = new PA_Unichar[text.size() + 1];
    std::copy(text.begin(), text.end(), s.fString);
    s.fString[text.size()] = 0;
    strings.emplace(s.fString, text);
    return s;
}
void dispose(PA_Unistring s) {
    if (!s.fString) return;
    if (strings.erase(s.fString) != 1) { ++badDisposals; return; }
    delete[] s.fString;
}
PA_Picture picture() {
    PA_Picture p = new int(0);
    pictures[p] = 1;
    return p;
}
void disposePicture(PA_Picture p) {
    if (!p) return;
    auto it = pictures.find(p);
    if (it == pictures.end()) { ++badDisposals; return; }
    if (--it->second == 0) { pictures.erase(it); delete static_cast<int *>(p); }
}
void disposeHandle(PA_Handle h) {
    if (!h) return;
    require(handles.erase(h) == 1, "invalid handle disposal");
    free(*h); free(h);
}
void clear(PA_Variable &v) {
    require(static_cast<unsigned char>(v.fType) != 0xa5, "failed result was inspected/cleared");
    switch (PA_GetVariableKind(v)) {
        case eVK_Unistring: dispose(v.uValue.fString); break;
        case eVK_Picture: disposePicture(v.uValue.fPicture); break;
        case eVK_Blob: disposeHandle(v.uValue.fBlob.fHandle); break;
        case eVK_ArrayUnicode: case eVK_ArrayPicture:
            if (v.uValue.fArray.fData) {
                auto h = v.uValue.fArray.fData;
                size_t elementSize = v.fType == eVK_ArrayUnicode ? sizeof(PA_Unistring) : sizeof(PA_Picture);
                require(handles.at(h) >= (v.uValue.fArray.fNbElements + 1) * elementSize,
                        "logical count exceeds allocation");
                for (int i = 0; i <= v.uValue.fArray.fNbElements; ++i) {
                    if (v.fType == eVK_ArrayUnicode) dispose(reinterpret_cast<PA_Unistring *>(*h)[i]);
                    else disposePicture(reinterpret_cast<PA_Picture *>(*h)[i]);
                }
                disposeHandle(h);
            }
            break;
        case eVK_ArrayBoolean: case eVK_ArrayDate: case eVK_ArrayInteger:
        case eVK_ArrayLongint: case eVK_ArrayReal: case eVK_ArrayTime:
            disposeHandle(v.uValue.fArray.fData); break;
        default: break;
    }
    memset(&v, 0, sizeof(v)); v.fType = eVK_Undefined;
}
PA_Variable result(int kind) {
    PA_Variable v = {};
    v.fType = kind;
    if (kind == eVK_Unistring || kind == 0) v.uValue.fString = make(expected.c_str());
    else if (kind == eVK_Picture) v.uValue.fPicture = picture();
    else if (kind == eVK_Boolean) v.uValue.fBoolean = abortCallback;
    else if (kind == eVK_Longint) v.uValue.fLongint = 17;
    return v;
}
void host(short selector, EngineBlock *eb) {
    eb->fError = eER_NoErr;
    switch (selector) {
        case EX_CREATE_UNISTRING:
            eb->fUniString1 = make(reinterpret_cast<PA_Unichar *>(eb->fHandle)); break;
        case EX_DISPOSE_UNISTRING: dispose(eb->fUniString1); break;
        case EX_SET_UNISTRING: {
            auto next = make(reinterpret_cast<PA_Unichar *>(eb->fHandle));
            dispose(eb->fUniString1); eb->fUniString1 = next; break;
        }
        case EX_CLEAR_VARIABLE: clear(*static_cast<PA_Variable *>(eb->fPtr1)); break;
        case EX_HANDLE_MANAGER: {
            PA_Handle h = eb->fHandle;
            switch (eb->fParam1) {
                case 1:
                    if (failHandle) { failHandle = false; eb->fHandle = nullptr; eb->fError = -108; break; }
                    h = static_cast<PA_Handle>(malloc(sizeof(char *)));
                    *h = static_cast<char *>(calloc(std::max<sLONG_PTR>(eb->fParam2, 1), 1));
                    handles[h] = eb->fParam2; eb->fHandle = h; break;
                case 2: disposeHandle(h); break;
                case 3:
                    require(handles.count(h), "resize unknown handle");
                    if (failResize) { failResize = false; eb->fError = -108; break; }
                    *h = static_cast<char *>(realloc(*h, std::max<sLONG_PTR>(eb->fParam2, 1)));
                    handles[h] = eb->fParam2; break;
                case 4: eb->fParam2 = handles.at(h); break;
                case 5: eb->fParam3 = reinterpret_cast<sLONG_PTR>(h ? *h : nullptr); break;
                case 6: case 7: case 8: break;
                default: throw std::runtime_error("unexpected handle operation");
            }
            break;
        }
        case EX_CREATE_PICTURE:
            if (eb->fParam1) require(eb->fParam1 == 3 && memcmp(eb->fPtr1, "SYN", 3) == 0,
                                     "unexpected picture fixture");
            eb->fPicture = picture(); break;
        case EX_DISPOSE_PICTURE: disposePicture(eb->fPicture); break;
        case EX_DUPLICATE_PICTURE:
            if (eb->fPicture) {
                require(pictures.count(eb->fPicture), "retain stale picture");
                if (eb->fParam1) eb->fPicture = picture();
                else ++pictures.at(eb->fPicture);
            }
            break;
        case EX_GET_PICTURE_DATA: {
            require(pictures.count(eb->fPicture), "read stale picture");
            if (eb->fParam1 != 1 || (eb->fHandle && failPictureData)) {
                memset(&eb->fUniString1, 0xa5, sizeof(eb->fUniString1));
                eb->fError = eER_IncompatibleTypes; break;
            }
            // Metadata allocator/ownership is not specified in this bundled SDK.
            static PA_Unichar type[] = {'.', 'p', 'n', 'g', 0};
            eb->fUniString1 = {}; eb->fUniString1.fString = type; eb->fUniString1.fLength = 4;
            if (eb->fHandle) {
                require(handles.count(eb->fHandle), "picture handle missing");
                *eb->fHandle = static_cast<char *>(realloc(*eb->fHandle, 3));
                memcpy(*eb->fHandle, "SYN", 3); handles[eb->fHandle] = 3;
            }
            break;
        }
        case EX_CONVERT_CHARSET_TO_CHARSET: {
            if (failConversion) { eb->fParam3 = -1; eb->fError = eER_IncompatibleTypes; break; }
            CFStringRef s = CFStringCreateWithBytes(kCFAllocatorDefault,
                static_cast<const UInt8 *>(eb->fPtr1), eb->fParam1,
                eb->fParam2 == eVTC_UTF_8 ? kCFStringEncodingUTF8 : kCFStringEncodingUTF16LE, false);
            require(s, "invalid conversion fixture");
            CFIndex used = 0;
            if (eb->fParam4 == eVTC_UTF_16)
                check(eb->fParam3 >= (CFStringGetLength(s) + 1) * sizeof(PA_Unichar),
                      "conversion capacity includes UTF16 terminator");
            CFStringGetBytes(s, CFRangeMake(0, CFStringGetLength(s)),
                eb->fParam4 == eVTC_UTF_8 ? kCFStringEncodingUTF8 : kCFStringEncodingUTF16LE,
                0, false, static_cast<UInt8 *>(eb->fPtr2), eb->fParam3, &used);
            eb->fParam3 = used; CFRelease(s); break;
        }
        case EX_EXECUTE_COMMAND_BY_ID: {
            auto args = static_cast<PA_Variable **>(eb->fPtr1);
            if (failCommand) {
                require(eb->fParam1 == failCommand, "unexpected failed command");
                memset(eb->fPtr2, 0xa5, sizeof(PA_Variable));
                eb->fError = eER_IncompatibleTypes; break;
            }
            *static_cast<PA_Variable *>(eb->fPtr2) = result(callbackKind);
            switch (eb->fParam1) {
                case 678:
                    check(Text(args[0]->uValue.fString.fString) == expected, "path copied to synchronous command");
                    disposePicture(args[1]->uValue.fPicture); args[1]->uValue.fPicture = picture(); break;
                case 1002:
                    check(Text(args[1]->uValue.fString.fString) == expectedFormat,
                          "format UTF16 units/termination");
                    check(args[1]->uValue.fString.fLength == expectedFormat.size(), "format exact unit length"); break;
                case 988: break;
                case 457: args[1]->uValue.fLongint = 13; args[2]->uValue.fLongint = 17; break;
                case 679:
                    disposePicture(args[1]->uValue.fPicture); args[1]->uValue.fPicture = picture(); break;
                default: throw std::runtime_error("real command forbidden");
            }
            break;
        }
        case EX_CALL_BY_PROCID: {
            ++callbacks;
            auto vars = reinterpret_cast<PA_Variable *>(*eb->fHandle);
            for (int i = 2; i <= 4; ++i) {
                auto s = vars[i].uValue.fString;
                check(Text(s.fString, s.fLength) == expected, "callback exact text");
                require(strings.count(s.fString), "callback got dead string");
            }
            check(vars[5].uValue.fLongint == callbacks, "callback position");
            check(vars[6].uValue.fLongint == static_cast<PA_long32>([selection count]), "callback total");
            require(pictures.count(vars[1].uValue.fPicture), "callback picture live");
            if (failCommand) {
                memset(vars, 0xa5, sizeof(PA_Variable)); eb->fError = eER_IncompatibleTypes;
            } else *vars = result(callbackKind);
            break;
        }
        case EX_GET_METHOD_ID: eb->fParam1 = eb->fUName[0] ? 7 : 0; break;
        case EX_NEW_PROCESS:
            ++createdProcesses; processEntry = reinterpret_cast<void (*)()>(eb->fHandle); eb->fParam1 = 42; break;
        case EX_YIELD_ABSOLUTE: break;
        case EX_CONVERT_STRING:
            require(eb->fParam1 == 4 && handles.count(eb->fHandle), "unexpected blob conversion");
            if (eb->fParam3) memcpy(reinterpret_cast<void *>(eb->fParam3), *eb->fHandle, handles.at(eb->fHandle));
            eb->fParam4 = handles.at(eb->fHandle); break;
        case EX_GET_INFORMATION: eb->fParam2 = 0; break;
        case EX_GET_POINTER_VALUE_PROPERTIES: eb->fParam1 = eVK_Unistring; break;
        case EX_GET_POINTER_VALUE:
            if (failCommand) {
                memset(eb->fHandle, 0xa5, sizeof(PA_Variable)); eb->fError = eER_IncompatibleTypes;
            } else *reinterpret_cast<PA_Variable *>(eb->fHandle) = result(callbackKind);
            break;
        default: throw std::runtime_error("unexpected engine selector");
    }
}
void balance() {
    check(strings.empty(), "all strings disposed exactly once");
    check(pictures.empty(), "all pictures disposed exactly once");
    check(handles.empty(), "all handles disposed exactly once");
    check(badDisposals == 0, "no duplicate/borrowed disposal");
    check(fakeObjects == 0, "all synthetic owned objects released");
}
}

@implementation SBApplication
+ (id)applicationWithBundleIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:@"com.apple.Photos"]) abort();
    return [PhotosApplication new];
}
@end
@implementation SBObject @end
@implementation PhotosApplication
- (NSArray *)selection { ++selectionCalls; return selection; }
- (void)export:(id)items to:(id)url usingOriginals:(BOOL)originals {
    require([items count] == 1 && [url isKindOfClass:[OwnershipURL class]] && originals,
            "unexpected synthetic export");
    ++exports;
}
@end
@implementation PhotosMediaItem
- (NSString *)id { return fixture; }
- (NSString *)filename { return fixture; }
- (NSString *)name { return fixture; }
- (void)setName:(NSString *)name { throw std::runtime_error("unexpected mutation"); }
- (NSDate *)date { return reinterpret_cast<NSDate *>(fixture); }
- (void)setDate:(NSDate *)date { throw std::runtime_error("unexpected mutation"); }
@end
@implementation OwnershipURL
- (id)initWithString:(NSString *)string { throw std::runtime_error("unexpected URL initialization"); }
- (NSString *)absoluteString { throw std::runtime_error("unexpected URL conversion"); }
- (id)URLByAppendingPathComponent:(NSString *)component isDirectory:(BOOL)directory {
    require(component != nil, "missing synthetic path component"); return self;
}
@end
@implementation OwnershipFileManager
+ (id)defaultManager { static id manager = [OwnershipFileManager new]; return manager; }
- (NSArray *)URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    require(directory == NSDesktopDirectory && domains == NSUserDomainMask, "unexpected directory request");
    return [NSArray arrayWithObject:[[[OwnershipURL alloc] init] autorelease]];
}
- (OwnershipURL *)URLForDirectory:(NSSearchPathDirectory)directory
                        inDomain:(NSSearchPathDomainMask)domain
               appropriateForURL:(OwnershipURL *)url create:(BOOL)create error:(NSError **)error {
    require(directory == NSItemReplacementDirectory && domain == NSUserDomainMask && create,
            "unexpected temporary folder request"); return url;
}
- (BOOL)removeItemAtURL:(OwnershipURL *)url error:(NSError **)error { ++removals; return YES; }
@end
@implementation OwnershipData
- (id)initWithContentsOfURL:(OwnershipURL *)url {
    require([url isKindOfClass:[OwnershipURL class]], "unexpected data URL");
    self = [super init]; ++fakeObjects;
    if (!haveData) { [self release]; return nil; }
    return self;
}
- (void)dealloc { --fakeObjects; [super dealloc]; }
- (const void *)bytes { return "SYN"; }
- (NSUInteger)length { return 3; }
@end
@implementation OwnershipUUID
- (id)init { self = [super init]; ++fakeObjects; return self; }
+ (id)UUID { return [[[self alloc] init] autorelease]; }
- (NSString *)UUIDString { return @"SYNTHETIC-UUID"; }
- (void)dealloc { --fakeObjects; [super dealloc]; }
@end
@implementation OwnershipImage
- (id)initWithCGImage:(CGImageRef)image size:(NSSize)size { throw std::runtime_error("real graphics forbidden"); }
- (OwnershipData *)TIFFRepresentation { throw std::runtime_error("real graphics forbidden"); }
@end

extern "C" CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef, CFStringRef, CFURLPathStyle, Boolean) {
    throw std::runtime_error("real path operation forbidden");
}
extern "C" CFStringRef CFURLCopyFileSystemPath(CFURLRef, CFURLPathStyle) {
    throw std::runtime_error("real path operation forbidden");
}
extern "C" void CGContextScaleCTM(CGContextRef, CGFloat, CGFloat) { throw std::runtime_error("graphics forbidden"); }
extern "C" void CGContextTranslateCTM(CGContextRef, CGFloat, CGFloat) { throw std::runtime_error("graphics forbidden"); }
extern "C" CFUUIDRef CFUUIDCreate(CFAllocatorRef) { throw std::runtime_error("real UUID forbidden"); }
extern "C" CFStringRef CFUUIDCreateString(CFAllocatorRef, CFUUIDRef) { throw std::runtime_error("real UUID forbidden"); }
extern "C" void NSLog(NSString *format, ...) {
    ++logCalls; std::cerr << "synthetic log: " << [format UTF8String] << "\n";
}

namespace {
void textFixture(int index) {
    static NSString *values[] = {@"", @"ASCII", @"\u65e5\u672c", @"A\U0001f600Z"};
    fixture = values[index]; expected.resize([fixture length]);
    if (!expected.empty()) [fixture getCharacters:&expected[0] range:NSMakeRange(0, expected.size())];
}
void textRoundTrip(int index) {
    textFixture(index);
    C_TEXT text; text.setUTF16String(fixture);
    check(text.getUTF16Length() == expected.size(), "scalar exact UTF16 units");
    check(Text(text.getUTF16StringPtr(), text.getUTF16Length()) == expected, "scalar exact content");
    CUTF8String utf8; text.copyUTF8String(&utf8);
    C_TEXT from8; from8.setUTF8String(&utf8);
    check(Text(from8.getUTF16StringPtr(), from8.getUTF16Length()) == expected, "UTF8 scalar roundtrip");
    PA_Unistring out = make(reinterpret_cast<const PA_Unichar *>(u"old"));
    BytePtr p[] = {reinterpret_cast<BytePtr>(&out)};
    text.toParamAtIndex(p, 1);
    check(Text(out.fString, out.fLength) == expected, "scalar parameter copy");
    C_TEXT read; read.fromParamAtIndex(p, 1);
    sLONG_PTR returnSlot = reinterpret_cast<sLONG_PTR>(&out);
    text.setReturn(&returnSlot);
    check(Text(out.fString, out.fLength) == expected, "scalar return copy");
    dispose(out);
    ARRAY_TEXT array; array.setSize(1); array.appendUTF16String(fixture); array.appendUTF16String(fixture);
    PA_Variable dst = PA_CreateVariable(eVK_ArrayUnicode);
    BytePtr a[] = {reinterpret_cast<BytePtr>(&dst)};
    for (int i = 0; i < 3; ++i) array.toParamAtIndex(a, 1);
    auto first = PA_GetStringInArray(dst, 1), second = PA_GetStringInArray(dst, 2);
    check(Text(first.fString, first.fLength) == expected, "array content after replacement");
    check(first.fString != second.fString || !first.fString, "one independent owner per output");
    ARRAY_TEXT copied; copied.fromParamAtIndex(a, 1); clear(dst);
    CUTF16String value; copied.copyUTF16StringAtIndex(&value, 1);
    check(value == expected, "borrowed getter copied before host cleanup");
    CUTF8String converted; copied.copyUTF8StringAtIndex(&converted, 1);
    ARRAY_TEXT fromUtf8; fromUtf8.appendUTF8String(&converted);
    fromUtf8.copyUTF16StringAtIndex(&value, 0);
    check(value == expected, "UTF8 array roundtrip");
    array.toParamAtIndex(a, 1); clear(dst);
    balance();
}
void dispatcher(bool async) {
    const bool expectResizeFailure = failResize;
    textFixture(3);
    auto item = [[[PhotosMediaItem alloc] init] autorelease];
    selection = [NSArray arrayWithObjects:item, item, nil];
    PA_Variable outputs[4];
    for (int i = 0; i < 4; ++i) outputs[i] = PA_CreateVariable(i ? eVK_ArrayUnicode : eVK_ArrayPicture);
    PA_Unistring callback = make(reinterpret_cast<const PA_Unichar *>(async ? u"callback" : u""));
    PA_long32 process = -1;
    BytePtr args[6] = {reinterpret_cast<BytePtr>(&outputs[0]), reinterpret_cast<BytePtr>(&outputs[1]),
        reinterpret_cast<BytePtr>(&outputs[2]), reinterpret_cast<BytePtr>(&outputs[3]),
        reinterpret_cast<BytePtr>(&callback), reinterpret_cast<BytePtr>(&process)};
    FourDPackex(1, args, nullptr, nullptr);
    if (expectResizeFailure) {
        check(logCalls == 1, "dispatcher resize failure surfaced");
        check(outputs[0].uValue.fArray.fNbElements == 0, "failed dispatcher preserves output owner");
    } else if (async) {
        check(process == 42 && createdProcesses == 1 && processEntry, "actual dispatcher creates synthetic process");
        if (processEntry) processEntry();
        if (failCommand) check(logCalls == 1, "callback error surfaced");
        check(callbacks == (haveData ? (abortCallback || failCommand ? 1 : 2) : 0), "callback count/abort preserved");
    } else {
        check(selectionCalls == 1 && createdProcesses == 0, "synchronous exported dispatcher boundary");
        check(outputs[0].uValue.fArray.fNbElements == (haveData ? 2 : 0), "picture array cardinality");
        for (int i = 1; i < 4; ++i) {
            auto s = PA_GetStringInArray(outputs[i], 1);
            check(Text(s.fString, s.fLength) == expected, "actual dispatcher exact output text");
        }
    }
    check(removals == exports, "all synthetic exports cleaned up");
    for (auto &v : outputs) clear(v);
    dispose(callback);
}
void pictureHelper(int mode) {
    textFixture(3);
    {
        C_PICTURE wrapper;
        wrapper.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3);
        auto own = wrapper.getPicture();
        check(pictures.count(own), "picture owner live");
        if (mode == 0) {
            CUTF8String path; C_TEXT t; t.setUTF16String(fixture); t.copyUTF8String(&path);
            wrapper.fromFileAtPath(&path);
        } else if (mode == 1) {
            auto p = wrapper.createCopyPNG(); check(pictures.count(p), "converted picture survives argument cleanup"); disposePicture(p);
        } else if (mode == 2) {
            auto p = wrapper.createGrayScale(); check(pictures.count(p), "grayscale handoff"); disposePicture(p);
        } else if (mode == 3) {
            unsigned int w = 0, h = 0; wrapper.getSize(&w, &h); check(w == 13 && h == 17, "size output values");
            check(pictures.count(own), "borrowed size input retained by wrapper");
        } else if (mode == 4) {
            auto p = wrapper.createThumbnail(7, 9); check(pictures.count(p), "thumbnail handoff"); disposePicture(p);
            check(pictures.count(own), "borrowed thumbnail input survives");
        } else if (mode == 5) {
            CUTF8String type(reinterpret_cast<const uint8_t *>(".png"));
            check(wrapper.getBytesLength(&type) == 3, "picture representation size");
            check(memcmp(wrapper.getBytesPtr(&type), "SYN", 3) == 0, "picture representation content");
        } else if (mode == 6) {
            PA_Picture destination = picture(); BytePtr args[] = {reinterpret_cast<BytePtr>(&destination)};
            wrapper.toParamAtIndex(args, 1); check(destination == own, "picture output retain");
            wrapper.fromParamAtIndex(args, 1); disposePicture(destination);
            sLONG_PTR returned = 0; wrapper.setReturn(&returned); disposePicture(reinterpret_cast<PA_Picture>(returned));
        }
    }
    balance();
}
template<class T> void copyOwner() {
    { T a; T b(a); T c; c = a; c = c; }
    balance();
}
template<class T> struct ArrayTraits;
#define NUMERIC_TRAITS(T, KIND, APPEND, GET) \
template<> struct ArrayTraits<T> { \
    static PA_VariableKind kind() { return KIND; } \
    static void seed(T& a) { a.APPEND(3); a.APPEND(7); a.APPEND(11); } \
    static bool value(T& a) { return a.GET(1) == 7; } \
}
NUMERIC_TRAITS(ARRAY_INTEGER, eVK_ArrayInteger, appendIntValue, getShortValueAtIndex);
NUMERIC_TRAITS(ARRAY_LONGINT, eVK_ArrayLongint, appendIntValue, getIntValueAtIndex);
NUMERIC_TRAITS(ARRAY_REAL, eVK_ArrayReal, appendDoubleValue, getDoubleValueAtIndex);
NUMERIC_TRAITS(ARRAY_TIME, eVK_ArrayTime, appendTimeValue, getTimeValueAtIndex);
#undef NUMERIC_TRAITS
template<> struct ArrayTraits<ARRAY_BOOLEAN> {
    static PA_VariableKind kind() { return eVK_ArrayBoolean; }
    static void seed(ARRAY_BOOLEAN& a) { a.appendBooleanValue(false); a.appendBooleanValue(true); a.appendBooleanValue(false); }
    static bool value(ARRAY_BOOLEAN& a) { return a.getBooleanValueAtIndex(1); }
};
template<> struct ArrayTraits<ARRAY_DATE> {
    static PA_VariableKind kind() { return eVK_ArrayDate; }
    static void seed(ARRAY_DATE& a) { for (int i = 0; i < 3; ++i) a.appendYearMonthDay(2026, 11, 12); }
    static bool value(ARRAY_DATE& a) {
        uint16_t y = 0, m = 0, d = 0; a.getYearMonthDayAtIndex(&y, &m, &d, 1);
        return y == 2026 && m == 11 && d == 12;
    }
};
template<> struct ArrayTraits<ARRAY_TEXT> {
    static PA_VariableKind kind() { return eVK_ArrayUnicode; }
    static void seed(ARRAY_TEXT& a) {
        for (int i = 0; i < 3; ++i) a.appendUTF16String(reinterpret_cast<const PA_Unichar *>(u"A\u65e5\U0001f600"));
    }
    static bool value(ARRAY_TEXT& a) {
        CUTF16String s; a.copyUTF16StringAtIndex(&s, 1);
        return s == Text(reinterpret_cast<const PA_Unichar *>(u"A\u65e5\U0001f600"));
    }
};
template<class T> void arrayControl(int mode) {
    T a; ArrayTraits<T>::seed(a);
    PA_Variable dst = PA_CreateVariable(mode == 1 ? eVK_Undefined : mode == 2 ? eVK_Longint : ArrayTraits<T>::kind());
    BytePtr args[] = {reinterpret_cast<BytePtr>(&dst)};
    a.toParamAtIndex(args, 1);
    if (mode == 2) check(dst.fType == eVK_Longint && dst.uValue.fLongint == 0, "wrong array type rejected unchanged");
    else {
        check(dst.fType == ArrayTraits<T>::kind() && dst.uValue.fArray.fNbElements == 2, "array type and count");
        T read; read.fromParamAtIndex(args, 1);
        check(read.getSize() == 3 && ArrayTraits<T>::value(read), "array borrowed input independently copied");
        a.setSize(0); a.toParamAtIndex(args, 1);
        check(dst.uValue.fArray.fNbElements == 0, "array shrink to zero");
        T b(read); T c; c = read; c = c; read.setSize(0);
        check(ArrayTraits<T>::value(b) && ArrayTraits<T>::value(c), "populated array copies have independent lifetime");
    }
    clear(dst); balance();
}
template<class T> void existingResizeFailure(bool shrink) {
    PA_Variable dst = PA_CreateVariable(ArrayTraits<T>::kind());
    PA_ResizeArray(&dst, shrink ? 31 : 1);
    const PA_long32 oldCount = dst.uValue.fArray.fNbElements;
    BytePtr args[] = {reinterpret_cast<BytePtr>(&dst)};
    bool stopped = false;
    try { T a; a.setSize(shrink ? 2 : 32); failResize = true; a.toParamAtIndex(args, 1); }
    catch (const std::exception &) { stopped = true; }
    check(stopped, "existing resize failure stops");
    check(dst.uValue.fArray.fNbElements == oldCount, "existing output count remains usable");
    clear(dst); balance();
}
template<class T> void arrayAllocationFailure() {
    PA_Variable dst = PA_CreateVariable(eVK_Undefined);
    BytePtr args[] = {reinterpret_cast<BytePtr>(&dst)};
    bool stopped = false;
    try { T a; a.setSize(2); failHandle = true; a.toParamAtIndex(args, 1); }
    catch (const std::exception &) { stopped = true; }
    check(stopped && dst.fType == eVK_Undefined, "array allocation failure preserves undefined output");
    clear(dst); balance();
}
void transferControl(int mode) {
    textFixture(3);
    PA_Variable storage = PA_CreateVariable(mode == 1 ? eVK_Longint : eVK_ArrayUnicode);
    if (storage.fType == eVK_ArrayUnicode) PA_ResizeArray(&storage, 1);
    PA_Variable dst = storage;
    if (mode == 2) dst.uValue.fArray.fData = nullptr;
    int index = mode == 3 ? -1 : mode == 4 ? 2 : mode == 5 ? 0 : 1;
    auto str = make(expected.c_str());
    auto pointer = str.fString;
    PA_SetStringInArray(dst, index, &str);
    bool accepted = mode == 0 || mode == 5;
    if (accepted) {
        auto view = PA_GetStringInArray(dst, index);
        std::vector<Text> churn(1024, expected);
        check(view.fString == pointer && Text(view.fString, view.fLength) == expected, "accepted transfer survives allocator churn");
    } else {
        check(strings.count(pointer), "rejected transfer retains caller ownership");
        dispose(str);
    }
    clear(storage); balance();
}
void scalarControls() {
    PA_long32 n = 3; short s = 5; double d = 7; PA_Date date = {12, 11, 2026};
    BytePtr args[] = {reinterpret_cast<BytePtr>(&n), reinterpret_cast<BytePtr>(&s),
                      reinterpret_cast<BytePtr>(&d), reinterpret_cast<BytePtr>(&date)};
    C_LONGINT l; l.fromParamAtIndex(args, 1); check(l.getIntValue() == 3, "long input");
    l.setIntValue(9); l.toParamAtIndex(args, 1); check(n == 9, "long output");
    C_INTEGER i; i.fromParamAtIndex(args, 2); check(i.getShortValue() == 5, "integer input");
    i.setShortValue(11); i.toParamAtIndex(args, 2); check(s == 11, "integer output");
    C_REAL r; r.fromParamAtIndex(args, 3); check(r.getDoubleValue() == 7, "real input");
    r.setDoubleValue(13); r.toParamAtIndex(args, 3); check(d == 13, "real output");
    C_DATE dt; dt.fromParamAtIndex(args, 4); check(dt.getYear() == 2026, "date input");
    dt.setYearMonthDay(2025, 10, 9); dt.toParamAtIndex(args, 4); check(date.fYear == 2025, "date output");
    C_TIME tm; tm.setHourMinuteSecond(1, 2, 3); tm.toParamAtIndex(args, 1);
    check(n == 3723, "time output");
    C_POINTER pointer; check(pointer.getType() == ePK_InvalidPointer, "dormant pointer default");
    balance();
}
void independentCopies(int mode) {
    textFixture(3);
    if (mode == 0) {
        C_TEXT a; a.setUTF16String(fixture); C_TEXT b(a); C_TEXT c; c = a; a.setUTF16String(@"");
        check(Text(b.getUTF16StringPtr(), b.getUTF16Length()) == expected &&
              Text(c.getUTF16StringPtr(), c.getUTF16Length()) == expected, "populated text copy independence");
    } else if (mode == 1) {
        C_BLOB a; a.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3); C_BLOB b(a); C_BLOB c; c = a;
        a.setBytes(nullptr, 0);
        check(b.getBytesLength() == 3 && c.getBytesLength() == 3, "populated blob copy independence");
    } else {
        C_PICTURE b;
        PA_Picture p = nullptr;
        {
            C_PICTURE a; a.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3); p = a.getPicture();
            C_PICTURE c(a); b = c;
        }
        check(pictures.count(p), "picture copy retains past source destruction");
        CUTF8String type(reinterpret_cast<const uint8_t *>(".png"));
        check(b.getBytesLength(&type) == 3, "picture copied cache/representation usable");
    }
}
void blobReuse(int mode) {
    C_BLOB b; b.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3);
    if (mode == 0) {
        b.setBytes(nullptr, 0); check(b.getBytesLength() == 0 && !b.getBytesPtr(), "null empty resets blob");
    } else if (mode == 1) {
        PA_Handle h = nullptr; BytePtr args[] = {reinterpret_cast<BytePtr>(&h)}; b.fromParamAtIndex(args, 1);
        check(b.getBytesLength() == 0, "empty blob parameter clears reused wrapper");
    } else if (mode == 2) {
        uint32_t size = 2; b.getBytesPtrForSize(&size);
        b.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3); size = 3;
        auto p = b.getBytesPtrForSize(&size);
        check(size == 3 && p && memcmp(p, "SYN", 3) == 0, "reused blob resets cursor");
    } else if (mode == 3) {
        b.addBytes(b.getBytesPtr(), b.getBytesLength());
        check(b.getBytesLength() == 6 && memcmp(b.getBytesPtr(), "SYNSYN", 6) == 0, "self append preserves source lifetime");
    }
    balance();
}
void pictureDataRetry(bool allocation) {
    C_PICTURE p; p.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3);
    CUTF8String type(reinterpret_cast<const uint8_t *>(".png"));
    if (allocation) failHandle = true; else failPictureData = true;
    bool stopped = false;
    try { p.getBytesLength(&type); } catch (const std::exception &) { stopped = true; }
    check(stopped, "picture data failure surfaced");
    failPictureData = false; failHandle = false;
    check(p.getBytesLength(&type) == 3, "failed picture load does not poison representation cache");
}
void embeddedConversion() {
    const uint8_t bytes[] = {'A', 0, 'B'};
    C_TEXT t; t.setUTF8String(bytes, 3);
    check(t.getUTF16Length() == 3 && t.getUTF16StringPtr()[2] == 'B', "scalar explicit UTF8 units survive embedded null");
    ARRAY_TEXT a; a.appendUTF8String(bytes, 3); CUTF16String s; a.copyUTF16StringAtIndex(&s, 0);
    check(s.size() == 3 && s[2] == 'B', "array explicit UTF8 units survive embedded null");
    balance();
}
void blobPluginParameters() {
    PA_Handle h = PA_NewHandle(3); memcpy(*h, "SYN", 3);
    BytePtr raw[] = {reinterpret_cast<BytePtr>(&h)};
    PluginBlock params = {}; params.fParameters = raw;
    C_BLOB b; b.fromParamAtIndex(&params, 1);
    check(b.getBytesLength() == 3 && memcmp(b.getBytesPtr(), "SYN", 3) == 0, "plugin BLOB parameter independent copy");
    disposeHandle(h); h = nullptr; b.fromParamAtIndex(&params, 1);
    check(b.getBytesLength() == 0, "plugin empty BLOB clears reused wrapper");
    sLONG_PTR returned = 0; b.setReturn(&returned);
    auto output = reinterpret_cast<PA_Handle>(returned);
    check(handles.count(output) && handles.at(output) == 0, "empty BLOB return owner");
    disposeHandle(output); balance();
}
void pictureFormat(int mode) {
    textFixture(3);
    if (mode == 0 || mode == 1) {
        C_PICTURE p; p.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3);
        expectedFormat = Text(reinterpret_cast<const PA_Unichar *>(mode == 0 ? u".jpg" : u".tif"));
        auto out = mode == 0 ? p.createCopyJPG() : p.createCopyTIF(); disposePicture(out);
    } else {
        CPicture p; p.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3);
        expectedFormat = mode == 2 ? expected : Text();
        auto out = p.createCopy(mode == 2 ? [fixture UTF8String] : ""); disposePicture(out);
    }
}
template<class T> void resizeFailure() {
    PA_Variable dst = PA_CreateVariable(eVK_Undefined);
    BytePtr args[] = {reinterpret_cast<BytePtr>(&dst)};
    bool stopped = false;
    try { T a; a.setSize(32); failResize = true; a.toParamAtIndex(args, 1); }
    catch (const std::exception &) { stopped = true; }
    check(stopped, "failed resize stops before writes");
    clear(dst); balance();
}
void blobControls() {
    C_BLOB bytes; bytes.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3);
    C_TEXT text; bytes.toHexText(&text);
    C_BLOB decoded; decoded.fromHexText(&text);
    check(decoded.getBytesLength() == 3 && memcmp(decoded.getBytesPtr(), "SYN", 3) == 0, "hex roundtrip");
    bytes.toB64Text(&text); C_BLOB from64; from64.fromB64Text(&text);
    check(from64.getBytesLength() == 3 && memcmp(from64.getBytesPtr(), "SYN", 3) == 0, "base64 roundtrip");
    PA_Handle handle = PA_NewHandle(1); BytePtr args[] = {reinterpret_cast<BytePtr>(&handle)};
    bytes.toParamAtIndex(args, 1); C_BLOB input; input.fromParamAtIndex(args, 1);
    check(input.getBytesLength() == 3, "blob parameter independent copy"); disposeHandle(handle); balance();
}
void blobAllocationFailure() {
    C_BLOB bytes; bytes.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3);
    PA_Handle handle = PA_NewHandle(1), original = handle;
    BytePtr args[] = {reinterpret_cast<BytePtr>(&handle)};
    failHandle = true;
    try { bytes.toParamAtIndex(args, 1); } catch (const std::exception &) {}
    check(handle == original && handles.count(handle), "blob allocation failure preserves existing owner");
    if (handles.count(handle)) disposeHandle(handle);
    balance();
}
void textIndex() {
    ARRAY_TEXT a; a.setSize(2);
    a.setUTF16StringAtIndex(reinterpret_cast<const PA_Unichar *>(u"new"), 1);
    check(a.getSize() == 2, "text indexed replacement does not append");
    CUTF16String s; a.copyUTF16StringAtIndex(&s, 1);
    check(s == Text(reinterpret_cast<const PA_Unichar *>(u"new")), "text indexed replacement value"); balance();
}
std::map<std::string, std::function<void()>> cases() {
    std::map<std::string, std::function<void()>> c;
    for (int i = 0; i < 4; ++i)
        c["text-roundtrip-" + std::to_string(i)] = [i] { textRoundTrip(i); };
    c["text-null-empty"] = [] { allocatedEmpty = false; textRoundTrip(0); };
    c["text-indexed-replacement"] = textIndex;
    c["dispatcher-sync"] = [] { dispatcher(false); };
    c["dispatcher-sync-no-data"] = [] { haveData = false; dispatcher(false); };
    for (int kind : {int(eVK_Boolean), int(eVK_Longint), int(eVK_Unistring), 0, int(eVK_Picture)}) {
        c["dispatcher-callback-kind-" + std::to_string(kind)] = [kind] {
            callbackKind = kind; dispatcher(true);
            // Drain the fixture autorelease pool before checking synthetic objects.
        };
    }
    c["dispatcher-callback-abort"] = [] { abortCallback = true; dispatcher(true); };
    c["dispatcher-callback-no-data"] = [] { haveData = false; dispatcher(true); };
    c["dispatcher-callback-error"] = [] { failCommand = 1; dispatcher(true); };
    c["dispatcher-unknown"] = [] { FourDPackex(999, nullptr, nullptr, nullptr); check(!selectionCalls, "unknown selector inert"); };
    static const char *names[] = {"file", "copy", "grayscale", "size", "thumbnail", "bytes", "param-return"};
    for (int i = 0; i < 7; ++i) c[std::string("picture-") + names[i]] = [i] { pictureHelper(i); };
    for (int kind : {int(eVK_Boolean), int(eVK_Unistring), 0, int(eVK_Picture)}) {
        c["picture-command-result-" + std::to_string(kind)] = [kind] { callbackKind = kind; pictureHelper(3); };
    }
    for (int command : {678, 1002, 988, 457, 679}) {
        c["picture-command-error-" + std::to_string(command)] = [command] {
            failCommand = command;
            bool stopped = false;
            try { pictureHelper(command == 678 ? 0 : command == 1002 ? 1 : command == 988 ? 2 : command == 457 ? 3 : 4); }
            catch (const std::exception &) { stopped = true; }
            check(stopped, "failed command stops before result/output adoption");
        };
    }
#define OWNER_CASE(T) c["copy-" #T] = copyOwner<T>
    OWNER_CASE(C_TEXT); OWNER_CASE(C_BLOB); OWNER_CASE(C_PICTURE); OWNER_CASE(CPicture);
    OWNER_CASE(ARRAY_TEXT); OWNER_CASE(ARRAY_BOOLEAN); OWNER_CASE(ARRAY_DATE);
    OWNER_CASE(ARRAY_INTEGER); OWNER_CASE(ARRAY_LONGINT); OWNER_CASE(ARRAY_REAL); OWNER_CASE(ARRAY_TIME);
#undef OWNER_CASE
#define RESIZE_CASE(T) c["resize-failure-" #T] = resizeFailure<T>
    RESIZE_CASE(ARRAY_TEXT); RESIZE_CASE(ARRAY_BOOLEAN); RESIZE_CASE(ARRAY_DATE);
    RESIZE_CASE(ARRAY_INTEGER); RESIZE_CASE(ARRAY_LONGINT); RESIZE_CASE(ARRAY_REAL); RESIZE_CASE(ARRAY_TIME);
#undef RESIZE_CASE
    c["blob-controls"] = blobControls; c["blob-allocation-failure"] = blobAllocationFailure;
    for (int mode = 0; mode < 3; ++mode) {
#define ARRAY_CONTROL(T) c["control-" #T "-" + std::to_string(mode)] = [mode] { arrayControl<T>(mode); }
        ARRAY_CONTROL(ARRAY_TEXT); ARRAY_CONTROL(ARRAY_BOOLEAN); ARRAY_CONTROL(ARRAY_DATE);
        ARRAY_CONTROL(ARRAY_INTEGER); ARRAY_CONTROL(ARRAY_LONGINT); ARRAY_CONTROL(ARRAY_REAL); ARRAY_CONTROL(ARRAY_TIME);
#undef ARRAY_CONTROL
    }
#define ARRAY_FAILURES(T) \
    c["resize-existing-" #T] = [] { existingResizeFailure<T>(false); }; \
    c["resize-shrink-" #T] = [] { existingResizeFailure<T>(true); }; \
    c["allocation-failure-" #T] = arrayAllocationFailure<T>
    ARRAY_FAILURES(ARRAY_TEXT); ARRAY_FAILURES(ARRAY_BOOLEAN); ARRAY_FAILURES(ARRAY_DATE);
    ARRAY_FAILURES(ARRAY_INTEGER); ARRAY_FAILURES(ARRAY_LONGINT); ARRAY_FAILURES(ARRAY_REAL); ARRAY_FAILURES(ARRAY_TIME);
#undef ARRAY_FAILURES
    for (int i = 0; i < 6; ++i) c["transfer-contract-" + std::to_string(i)] = [i] { transferControl(i); };
    c["scalar-controls"] = scalarControls;
    for (int i = 0; i < 3; ++i) c["populated-copy-" + std::to_string(i)] = [i] { independentCopies(i); };
    for (int i = 0; i < 4; ++i) c["blob-reuse-" + std::to_string(i)] = [i] { blobReuse(i); };
    c["picture-data-error"] = [] { pictureDataRetry(false); };
    c["picture-data-allocation-error"] = [] { pictureDataRetry(true); };
    c["picture-conversion-error"] = [] {
        failConversion = true; bool stopped = false;
        try { C_PICTURE p; p.setBytes(reinterpret_cast<const uint8_t *>("SYN"), 3); }
        catch (const std::exception &) { stopped = true; }
        check(stopped, "metadata conversion error stops before adopting format");
    };
    c["embedded-UTF8-conversion"] = embeddedConversion;
    c["blob-plugin-parameters"] = blobPluginParameters;
    c["dispatcher-resize-error"] = [] { failResize = true; dispatcher(false); };
    for (int i = 0; i < 4; ++i) c["picture-format-" + std::to_string(i)] = [i] { pictureFormat(i); };
    return c;
}
}

int main(int argc, char **argv) {
    auto all = cases();
    if (argc == 2 && std::string(argv[1]) == "--list") {
        for (const auto &entry : all) std::cout << entry.first << "\n";
        return 0;
    }
    if (argc != 2 || !all.count(argv[1])) return 2;
    auto pool = [[NSAutoreleasePool alloc] init];
    gCall4D = host;
    try { all.at(argv[1])(); }
    catch (const std::exception &e) { ++failures; std::cerr << "FAIL exception: " << e.what() << "\n"; }
    [pool drain];
    balance();
    std::cout << argv[1] << " assertions=" << checks << " failures=" << failures << "\n";
    return failures ? 1 : 0;
}
