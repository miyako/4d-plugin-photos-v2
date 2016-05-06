# 4d-plugin-photos-v2
Copy selection of images from Photos.app

##Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|🆗|🆗|🚫|🚫|

##Examples

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
