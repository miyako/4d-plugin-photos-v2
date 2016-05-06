/* --------------------------------------------------------------------------------
 #
 #	4DPlugin.h
 #	source generated by 4D Plugin Wizard
 #	Project : Photos v2
 #	author : miyako
 #	2016/05/06
 #
 # --------------------------------------------------------------------------------*/

#import <ScriptingBridge/ScriptingBridge.h>

@class PhotosApplication, PhotosMediaItem;

@interface PhotosApplication : SBApplication
- (void) export:(SBElementArray *)x to:(NSURL *)to usingOriginals:(BOOL)usingOriginals;
@end

@interface PhotosMediaItem : SBObject

@property (copy) NSString *name;  // The name (title) of the media item.
@property (copy) NSDate *date;  // The date of the media item
- (NSString *) id;  // The unique ID of the media item
@property (copy, readonly) NSString *filename;  // The name of the file on disk.
@end

@interface PhotosApplication (PhotosSuite)
@property (copy, readonly) NSArray *selection;  // The currently selected media items in the application
@end

// --- Photos
void Photos_GET_SELECTION(sLONG_PTR *pResult, PackagePtr pParams);

typedef PA_long32 process_number_t;
typedef PA_long32 process_stack_size_t;
typedef PA_long32 method_id_t;
typedef PA_Unichar* process_name_t;