# 4d-plugin-photos-v2
Copy selection of images from Photos.app

### Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|https://github.com/miyako/4d-plugin-file|https://github.com/miyako/4d-plugin-file|||

## Attention

You should disable iCould photo library update, or select "download original to this Mac", to prevent Photo from attempting to access the internet. Otherwise, the import could fail, and the application could freeze, if internet connection in unavailable.

![](https://cloud.githubusercontent.com/assets/1725068/15090786/3e4d4766-1434-11e6-8c69-1a53f860e27d.png)

## Examples

```
  //this is not really a drag-n-drop api, it simply returns the selected images in Photos.app
  //but normally dragged items are also selected, so it should work...

  //import synchron
  //Photos GET SELECTION ($photos;$names;$dates;$ids)

$method:="myImport"  //(picture;text;text;text;long;long)->bool

  //import asynchron
Photos GET SELECTION ($photos;$names;$dates;$ids;$method;$process)
  //$process(out):import process number

```

* myImport

```
C_PICTURE($1)
C_TEXT($2;$3;$4)
C_LONGINT($5;$6)
C_BOOLEAN($0)

TRACE

$photo:=$1
$name:=$2
$date:=$3
$id:=$4
$pos:=$5
$total:=$6

$0:=Caps lock down  //return true to abort
```
