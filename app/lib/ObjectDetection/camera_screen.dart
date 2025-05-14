import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'dart:io';
import 'mlkit_object_detection.dart';
import 'object_painter.dart';
import 'dart:io';

class IsolateDataHolder {
 final SendPort mainSendPort;
 final RootIsolateToken? rootIsolateToken;
 IsolateDataHolder(this.mainSendPort, this.rootIsolateToken);
}

class RealtimeObjectDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const RealtimeObjectDetectionScreen({Key? key, required this.cameras})
      : super(key: key);

  @override
  _RealtimeObjectDetectionScreenState createState() =>
      _RealtimeObjectDetectionScreenState();
}

class _RealtimeObjectDetectionScreenState
    extends State<RealtimeObjectDetectionScreen> {
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isBusy = false;
  List<DetectedObject> _detectedObjects = [];
  InputImageRotation? _imageRotation;
  late ObjectDetector _objectDetector;
  Size? _lastImageSize;

  Isolate? _objectDetectionIsolate;
  Isolate? _imageRotationIsolate;
  late ReceivePort _objectDetectionReceivePort;
  late ReceivePort _imageRotationReceivePort;
  SendPort? _objectDetectionIsolateSendPort;
  SendPort? _imageRotationIsolateSendPort;
  StreamSubscription? _objectDetectionSubscription;
  StreamSubscription? _imageRotationSubscription;

  bool _isWaitingForRotation = false;
  bool _isWaitingForDetection = false;
  InputImageRotation? _lastCalculatedRotation;
  Uint8List? _pendingImageDataBytes;
  int? _pendingImageDataWidth;
  int? _pendingImageDataHeight;
  int? _pendingImageDataFormatRaw;
  int? _pendingImageDataBytesPerRow;

  @override
  void initState() {
    super.initState();
    print("RealtimeObjectDetectionScreen: initState called");
    _objectDetector = initializeObjectDetector();
    _spawnIsolates().then((_) {
      if (widget.cameras.isNotEmpty) {
        _initializeCamera(widget.cameras[0]);
      }else {
        print("****** No cameras available!");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용 가능한 카메라가 없습니다.')),
          );
        }
      }
    }).catchError((e, stacktrace) {

      print("****** initState: Error spawning isolates or initializing camera: $e");

      print(stacktrace);

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text('초기화 중 오류 발생: $e')),

        );

      }

    });

  }

  @override
  void dispose() {
    print("RealtimeObjectDetectionScreen: dispose called");
    _stopCameraStream();
    _objectDetectionSubscription?.cancel();
    _imageRotationSubscription?.cancel();
    _killIsolates();
    _cameraController?.dispose().then((_) {
      print("CameraController disposed");
    }).catchError((e) {
      });
      _objectDetector.close().then((_) {
      print("ObjectDetector closed");
    }).catchError((e){
      print("Error closing object detector: $e");
    });
    super.dispose();
  }

  Future<void> _spawnIsolates() async {
    print("Spawning Isolates..."); 
    final RootIsolateToken? rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      print("****** RootIsolateToken is null. ML Kit in Isolate might not work.");
      return;
    }

    _objectDetectionReceivePort = ReceivePort();
    _objectDetectionIsolate = await Isolate.spawn(
      detectObjectsIsolateEntry,
      IsolateDataHolder(_objectDetectionReceivePort.sendPort, rootIsolateToken),
      onError: _objectDetectionReceivePort.sendPort,
      onExit: _objectDetectionReceivePort.sendPort,
      debugName: "ObjectDetectionIsolate"
    );
    _objectDetectionSubscription =
        _objectDetectionReceivePort.listen(_handleDetectionResult);
    print("Object Detection Isolate spawned and listener attached."); // 디버그 로그

    _imageRotationReceivePort = ReceivePort();
    _imageRotationIsolate = await Isolate.spawn(
      getImageRotationIsolateEntry,

      _imageRotationReceivePort.sendPort,
      onError: _imageRotationReceivePort.sendPort,
      onExit: _imageRotationReceivePort.sendPort,

      debugName: "ImageRotationIsolate"
    );
    _imageRotationSubscription =
        _imageRotationReceivePort.listen(_handleRotationResult);

    print("Image Rotation Isolate spawned and listener attached."); // 디버그 로그

    
  }

  void _killIsolates() {
    print("Killing Isolates...");
    try {
      _objectDetectionIsolate?.kill(priority: Isolate.immediate);
      print("Object Detection Isolate kill signal sent.");
    } catch (e) {
      print("Error killing object detection isolate: $e");
    }
    try {
      _imageRotationIsolate?.kill(priority: Isolate.immediate);
      print("Image Rotation Isolate kill signal sent."); // 디버그 로그
    } catch (e) {
      print("Error killing image rotation isolate: $e");
    }

    _objectDetectionIsolate = null;
    _imageRotationIsolate = null;
    _objectDetectionIsolateSendPort = null;
    _imageRotationIsolateSendPort = null;
  }

  void _handleDetectionResult(dynamic message) {
    if (_objectDetectionIsolateSendPort == null && message is SendPort) {
      _objectDetectionIsolateSendPort = message;
    } else if (message is List<DetectedObject>) {
      _isWaitingForDetection = false;
      if (mounted) {
        setState(() {
          _detectedObjects = message;
          _imageRotation = _lastCalculatedRotation;
        });
      }
      if (!_isWaitingForRotation && !_isWaitingForDetection && _isBusy) {
        _isBusy = false;
      }
    } else if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[0].contains('Error')) {
      print('****** Object Detection Isolate Error: ${message[1]}');
      _isWaitingForDetection = false;
      if (!_isWaitingForRotation) _isBusy = false;
    } else {}
  }

  void _handleRotationResult(dynamic message) {
    if (!mounted) return; // 위젯 unmount 시 처리 중단

    if (_imageRotationIsolateSendPort == null && message is SendPort) {
      print("Image Rotation Isolate SendPort received via message."); // 디버그 로그
      _imageRotationIsolateSendPort = message;
    } else if (message is InputImageRotation?) {
      _isWaitingForRotation = false;
      _lastCalculatedRotation = message;
      _imageRotation = message;

      if (_pendingImageDataBytes != null &&
          _objectDetectionIsolateSendPort != null &&
          message != null) {
        _isWaitingForDetection = true;
        _lastImageSize = Size(_pendingImageDataWidth!.toDouble(),
        _pendingImageDataHeight!.toDouble());
        final Map<String, dynamic> payload = {
          'bytes': _pendingImageDataBytes!,
          'width': _pendingImageDataWidth!,
          'height': _pendingImageDataHeight!,
          'rotation': message,
          'formatRaw': _pendingImageDataFormatRaw!,
          'bytesPerRow': _pendingImageDataBytesPerRow!,
        };
        _objectDetectionIsolateSendPort!.send(payload);
        _pendingImageDataBytes = null;
      } else {
        if (message == null) print("Rotation calculation resulted in null, not sending to detection isolate.");

        if (!_isWaitingForDetection && _isBusy) _isBusy = false;
      }
    } else if (message is List &&
        message.length == 2 &&
        message[0] is String &&
        message[0].toString().contains('Error')) {
      print('****** Image Rotation Isolate Error: ${message[1]}');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    } else if (message == null || (message is List && message.isEmpty && message is! InputImageRotation)) {
       print('****** Image Rotation Isolate exited or sent empty/null message.');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (_imageRotationIsolateSendPort != null && message == null) {
          _imageRotationIsolateSendPort = null;
          print("Image Rotation Isolate SendPort invalidated due to Isolate exit.");
      }

      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    }
     else {

      print('****** Unexpected message from Image Rotation Isolate: $message, type: ${message.runtimeType}');
      _isWaitingForRotation = false;
      _pendingImageDataBytes = null;
      if (!_isWaitingForDetection && _isBusy) _isBusy = false;
    }
  }

   Future<void> _initializeCamera(CameraDescription cameraDescription) async {

    if (_cameraController != null && _cameraController!.value.isInitialized) {

      print("Disposing previous camera controller before initializing a new one.");

      await _stopCameraStream();
      await _cameraController!.dispose();
      _cameraController = null;
    }

     if (mounted) setState(() => _isCameraInitialized = false);



    print("Initializing camera: ${cameraDescription.name} with lens direction ${cameraDescription.lensDirection}");

    _cameraController = CameraController(

      cameraDescription,

      ResolutionPreset.high,
      enableAudio: false,

      imageFormatGroup: Platform.isAndroid

          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );



    try {

      await _cameraController!.initialize();

      print("Camera initialized. Preview size: ${_cameraController!.value.previewSize}, Aspect Ratio: ${_cameraController!.value.aspectRatio}");
   

      await _startCameraStream(); 



      if (mounted) {

        setState(() {

          _isCameraInitialized = true;

          _cameraIndex = widget.cameras.indexOf(cameraDescription);

        });

      }

    } on CameraException catch (e) {

      print('****** CameraException on initializeCamera for ${cameraDescription.name}: ${e.code} ${e.description}');

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text('카메라 초기화 오류 (${cameraDescription.name}): ${e.description}')),

        );

        setState(() => _isCameraInitialized = false);

      }

    } catch (e, stacktrace) {

      print('****** Other Exception on initializeCamera for ${cameraDescription.name}: $e');

      print(stacktrace);

      if (mounted) {

         ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text('알 수 없는 카메라 오류 발생 (${cameraDescription.name}).')),

        );

        setState(() => _isCameraInitialized = false);

      }

    }

  }
//여기부터 하면 됨
  Future<void> _startCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("Cannot start stream: Camera not initialized.");
      return;
    }
    if (_cameraController!.value.isStreamingImages) {
      print("Stream already started.");
      return;
    }
    try {
      await _cameraController!.startImageStream(_processCameraImage); 
      print("Camera image stream started.");
    } catch (e, stacktrace) {
      print('****** Exception on startCameraStream: $e');
      print(stacktrace);
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카메라 스트림 시작 오류.')),
        );
      }
    }
  }

  Future<void> _stopCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || !_cameraController!.value.isStreamingImages) {
      return;
    }
    try {
      await _cameraController!.stopImageStream();
      print("Camera image stream stopped.");
    } catch (e, stacktrace) {
      print('****** Exception on stopCameraStream: $e');
      print(stacktrace);
    } finally { 
      if(mounted) { 
        _isBusy = false;
        _isWaitingForRotation = false;
        _isWaitingForDetection = false;
        _pendingImageDataBytes = null;
      }
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isBusy ||
        _imageRotationIsolateSendPort == null ||
        _objectDetectionIsolateSendPort == null) return;
    _isBusy = true;
    _isWaitingForRotation = true;
    _isWaitingForDetection = false;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes)
        allBytes.putUint8List(plane.bytes);
      _pendingImageDataBytes = allBytes.done().buffer.asUint8List();
      _pendingImageDataWidth = image.width;
      _pendingImageDataHeight = image.height;
      _pendingImageDataFormatRaw = image.format.raw;
      _pendingImageDataBytesPerRow =
          image.planes.isNotEmpty ? image.planes[0].bytesPerRow : 0;

      final camera = widget.cameras[_cameraIndex];
      final orientation = MediaQuery.of(context).orientation;
      final DeviceOrientation deviceRotation =
          (orientation == Orientation.landscape)
              ? DeviceOrientation.landscapeLeft
              : DeviceOrientation.portraitUp;

      _imageRotationIsolateSendPort!.send([
        camera.sensorOrientation,
        deviceRotation,
      ]);
    } catch (e, stacktrace) {
      print("****** Error processing image: $e");
      _pendingImageDataBytes = null;
      _isWaitingForRotation = false;
      _isBusy = false;
    }
  }

  void _switchCamera() {
    if (widget.cameras.length < 2 || _isBusy) return;
    final newIndex = (_cameraIndex + 1) % widget.cameras.length;
    _stopCameraStream().then((_) {
      _initializeCamera(widget.cameras[newIndex]);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget cameraPreviewWidget;
    if (_isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      cameraPreviewWidget = AspectRatio(
        aspectRatio: _cameraController!.value.aspectRatio,
        child: CameraPreview(_cameraController!),
      );
    } else {
      cameraPreviewWidget = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 객체 탐지'),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: Icon(
                _cameras[_cameraIndex].lensDirection ==
                        CameraLensDirection.front
                    ? Icons.camera_front
                    : Icons.camera_rear,
              ),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: cameraPreviewWidget),
          if (_isCameraInitialized &&
              _detectedObjects.isNotEmpty &&
              _lastImageSize != null &&
              _imageRotation != null)
            LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: constraints.biggest,
                  painter: ObjectPainter(
                    objects: _detectedObjects,
                    imageSize: _lastImageSize!,
                    rotation: _imageRotation!,
                    cameraLensDirection:
                        widget.cameras[_cameraIndex].lensDirection,
                  ),
                );
              },
            ),
          if (_isBusy)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
