# 4d-plugin-photos-v2
Copy selection of images from Photos.app

See [4d-utility-sign-app](https://github.com/miyako/4d-utility-sign-app) on how to enable the plugin in 4D.

### Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
||<img src="https://cloud.githubusercontent.com/assets/1725068/22371562/1b091f0a-e4db-11e6-8458-8653954a7cce.png" width="24" height="24" />|||

### Releases

You must codesign your app with the following entitlement:

* ``com.apple.security.automation.apple-events`` 

The app must also have the following property list key:

* ``NSAppleEventsUsageDescription``

See [build-application](https://github.com/miyako/4d-utility-build-application)

### Alternative solution

[4d-plugin-apple-file-promises](https://github.com/miyako/4d-plugin-apple-file-promises)

## Ownership tests

`tests/ownership` compiles the bundled 4D Plugin API, the wrapper classes and `4DPlugin.cpp` with AddressSanitizer and UndefinedBehaviorSanitizer against a synthetic in-memory engine and synthetic Photos/AppKit/ScriptingBridge/Carbon stubs. It never accesses the Photos library, files, the network or the UI.

```
python3 tests/ownership/compare.py
```

This runs the same harness on the immutable baseline (expected failures are recorded in `tests/ownership/baseline.json`) and on the current sources (all cases must pass). Notes:

* Array, text, BLOB and picture wrappers own deep copies. `PA_SetStringInArray`/`PA_SetPictureInArray` transfer ownership only when the index is accepted.
* A failed `PA_ResizeArray` may still change the logical count. The wrappers restore it and throw.
* Command and method results are adopted only after `PA_GetLastError` reports success.
* Gaps: no Windows, real 4D host, real Photos, genuine out-of-memory, packed alignment or LeakSanitizer coverage.

## Attention

You should disable iCould photo library update, or select "download original to this Mac", to prevent Photo from attempting to access the internet. Otherwise, the import could fail, and the application could freeze, if internet connection in unavailable.

![](https://cloud.githubusercontent.com/assets/1725068/15090786/3e4d4766-1434-11e6-8c69-1a53f860e27d.png)

## Photos GET SELECTION

Returns the images currently selected in Photos.app. This is not a real drag-n-drop API — it reads the current selection — but normally dragged items are also selected, so it works as a drop target.

Each selected photo is exported to a temporary folder as its **original** file and read back as picture data. Each per-photo export folder is deleted after use.

**Platforms:** macOS only (Cocoa / ScriptingBridge).

---

### Syntax

```4d
// synchronous: returns arrays of pictures, names, dates and ids
Photos GET SELECTION ( $photos ; $names ; $dates ; $ids )

// asynchronous: $method is called once per photo
Photos GET SELECTION ( $photos ; $names ; $dates ; $ids ; $method ; $process )
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `$photos` | `Array of Picture` | The exported images, one entry per selected photo that could be read. May contain empty slots for photos whose export produced no data, so always iterate with `For each`/`Size of` and check the element. |
| `$names` | `Array of Text` | File names of the exported images, aligned by index with `$photos`. |
| `$dates` | `Array of Text` | Creation dates of the selected photos (localized description), aligned by index. |
| `$ids` | `Array of Text` | Photos library identifiers (UUID without dashes) of the selected photos, aligned by index. |
| `$method` | `Text` | *(asynchronous form only)* Name of a project method called once per photo. Pass an empty text or omit the last two parameters for the synchronous form. |
| `$process` | `Longint` | *(asynchronous form only, output)* Process number of the background import started with `PA_NewProcess`. |
| Result | — | No return value. |

In the asynchronous form the arrays are filled by the callback method instead: `$photos`, `$names`, `$dates`, `$ids` are **not** populated by the command itself.

### Example

Synchronous import:

```4d
$photos:=[]
$names:=[]
$dates:=[]
$ids:=[]

Photos GET SELECTION ($photos;$names;$dates;$ids)

For ($i:=1; $i<=Size of($photos); $i++)
	//$photos{$i} is a Picture, $names{$i}/$dates{$i}/$ids{$i} are Text
End for
```

Asynchronous import — the callback method `$method` receives one photo per call:

```4d
$photos:=[]
$names:=[]
$dates:=[]
$ids:=[]
$process:=0

Photos GET SELECTION ($photos;$names;$dates;$ids;"myImport";$process)
//$process: import process number, usable with e.g. PROCESS STATE
```

Callback method (from the plugin's README example):

```4d
// myImport (picture ; text ; text ; text ; long ; long) -> bool
C_PICTURE($1)
C_TEXT($2;$3;$4)
C_LONGINT($5;$6)
C_BOOLEAN($0)

TRACE

$photo:=$1  //Picture
$name:=$2   //Text: file name
$date:=$3   //Text: creation date
$id:=$4     //Text: Photos library id
$pos:=$5    //Long: position in selection (1-based)
$total:=$6  //Long: total number of selected photos

$0:=Caps lock down  //return true to abort the import
```

### Requirements & error handling

- **Automation permission is required.** On first use, macOS asks whether your application may control Photos.app. The host app needs the `com.apple.security.automation.apple-events` entitlement and the `NSAppleEventsUsageDescription` Info.plist key — see [build-application](https://github.com/miyako/4d-utility-build-application). If permission is denied, the command returns empty results without a 4D error.
- **Failure is silent.** If Photos.app is not running, has no selection, or the export fails, the command returns empty or partial arrays and logs to the system log (`NSLog`, visible via `Console.app` / `log stream`). There is no `4D` error to catch.
- **Photos must be downloaded locally.** If iCloud Photos is set to optimize storage and the originals are not on this Mac, the export can fail or the import can stall while Photos tries to download — see [Attention](#attention) below.
- **Arrays stay index-aligned.** Text arrays (`$names`, `$dates`, `$ids`) get one entry per selected photo; picture slots may be empty when an export produced no readable data. Do not assume `Size of($photos)` equals `Size of($ids)` for pictures — check elements individually.
- **The asynchronous form needs a real method name.** If `$method` does not resolve to a project method, the command falls back to synchronous behavior but still expects only the first four parameters; the process number stays 0.
