/*
 * Photos.h
 */

#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class PhotosApplication, PhotosMediaItem, PhotosContainer, PhotosAlbum, PhotosFolder, PhotosMoment;



/*
 * Standard Suite
 */

// The application's top-level scripting object.
@interface PhotosApplication : SBApplication

@property (copy, readonly) NSString *name;  // The name of the application.
@property (readonly) BOOL frontmost;  // Is this the active application?
@property (copy, readonly) NSString *version;  // The version number of the application.

- (BOOL) exists:(id)x;  // Verify that an object exists.
- (void) open:(NSURL *)x;  // Open a photo library
- (void) quit;  // Quit the application.
- (void) import:(NSArray<NSURL *> *)x into:(PhotosAlbum *)into skipCheckDuplicates:(BOOL)skipCheckDuplicates;  // Import files into the library
- (void) export:(NSArray<PhotosMediaItem *> *)x to:(NSURL *)to usingOriginals:(BOOL)usingOriginals;  // Export media items to the specified location as files
- (void) add:(NSArray<PhotosMediaItem *> *)x to:(PhotosAlbum *)to;  // Add media items to an album.
- (void) startSlideshowUsing:(NSArray<PhotosMediaItem *> *)using_;  // Display an ad-hoc slide show from a list of media items, an album, a folder, or a moment
- (void) stopSlideshow;  // End the currently-playing slideshow.
- (void) nextSlide;  // Skip to next slide in currently-playing slideshow.
- (void) previousSlide;  // Skip to previous slide in currently-playing slideshow.
- (void) pauseSlideshow;  // Pause the currently-playing slideshow.
- (void) resumeSlideshow;  // Resume the currently-playing slideshow.
- (void) spotlight:(id)x;  // Show the image at path in the application, used to show spotlight search results

@end



/*
 * Photos Suite
 */

// The top level scripting object for Photos.
@interface PhotosApplication (PhotosSuite)

- (SBElementArray<PhotosContainer *> *) containers;
- (SBElementArray<PhotosAlbum *> *) albums;
- (SBElementArray<PhotosFolder *> *) folders;
- (SBElementArray<PhotosMediaItem *> *) mediaItems;
- (SBElementArray<PhotosMoment *> *) moments;

@property (copy, readonly) NSArray<PhotosMediaItem *> *selection;  // The currently selected media items in the application
@property (copy, readonly) PhotosAlbum *favoritesAlbum;  // Favorited media items album.
@property (copy, readonly) PhotosAlbum *lastImportAlbum;  // Last import album.
@property (readonly) BOOL slideshowRunning;  // Returns true if a slideshow is currently running.
@property (copy, readonly) PhotosAlbum *recentlyDeletedAlbum;  // The set of recently deleted media items

@end

// A media item, such as a photo or video.
@interface PhotosMediaItem : SBObject

@property (copy) NSArray<NSString *> *keywords;  // A list of keywords to associate with a media item
@property (copy) NSString *name;  // The name (title) of the media item.
@property (copy) NSString *objectDescription;  // A description of the media item.
@property BOOL favorite;  // Whether the media item has been favorited.
@property (copy) NSDate *date;  // The date of the media item
- (NSString *) id;  // The unique ID of the media item
@property (readonly) NSInteger height;  // The height of the media item in pixels.
@property (readonly) NSInteger width;  // The width of the media item in pixels.
@property (copy, readonly) NSString *filename;  // The name of the file on disk.
@property (readonly) double altitude;  // The GPS altitude in meters.
@property (copy, readonly) NSArray<NSNumber *> *location;  // The GPS latitude and longitude, in an ordered list of 2 numbers.  Latitude in range -90.0 to 90.0, longitude in range -180.0 to 180.0.

- (PhotosMediaItem *) duplicate;  // Duplicate an object.  Only media items can be duplicated

@end

// Base class for collections that contains other items, such as albums and folders
@interface PhotosContainer : SBObject

- (NSString *) id;  // The unique ID of this container.
@property (copy) NSString *name;  // The name of this container.
@property (copy, readonly) PhotosFolder *parent;  // This container's parent folder, if any.


@end

// An album. A container that holds media items
@interface PhotosAlbum : PhotosContainer

- (SBElementArray<PhotosMediaItem *> *) mediaItems;

- (void) delete;  // Delete an object.  Only albums and folders can be deleted.
- (void) spotlight;  // Show the image at path in the application, used to show spotlight search results

@end

// A folder. A container that holds albums and other folders, but not media items
@interface PhotosFolder : PhotosContainer

- (SBElementArray<PhotosContainer *> *) containers;
- (SBElementArray<PhotosAlbum *> *) albums;
- (SBElementArray<PhotosFolder *> *) folders;

- (void) delete;  // Delete an object.  Only albums and folders can be deleted.

@end

// A set of media items that represents a Moment.
@interface PhotosMoment : SBObject

- (SBElementArray<PhotosMediaItem *> *) mediaItems;

- (NSString *) id;  // The unique ID of the Moment.
@property (copy, readonly) NSString *name;  // The name of the Moment.


@end

