import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

/// Convierte la foto a escala de grises y le sube el contraste, para que
/// el OCR detecte mejor tintas claras o de bajo contraste.
Uint8List _convertToGrayscale(String path) {
  final bytes = File(path).readAsBytesSync();
  final original = img.decodeImage(bytes);

  if (original == null) return bytes;

  final grayscale = img.grayscale(original);
  // El contraste es ajustable: si con algunas tintas sigue sin detectar
  // bien, prueba subiendo este valor (ej. 1.5 o 1.7).
  final processed = img.adjustColor(
    grayscale,
    contrast: 1.4, // Ajusta el contraste para mejorar la detección de tintas
    gamma:1.4, // Ajusta el gamma para mejorar la visibilidad (1.5 para oscurecer o < 1.0 para aclarar)
    brightness: 1.0, // Ajusta el brillo si es necesario (-1.0 oscuro total, 0.0 sin cambio, 1.0 brillante total)
  ); 

  return img.encodeJpg(processed, quality: 90);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onScanResult});
  final Function(String text) onScanResult;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _isGranted = false;
  bool _isProcessing = false; // Evita doble-tap mientras se escanea
  late final Future<void> _future;
  CameraController? _cameraController;
  final textRecognizer = TextRecognizer();
  static bool _mensajeMostrado = false;

  @override
  void initState() {
    super.initState();
    if (!_mensajeMostrado){
      WidgetsBinding.instance.addPostFrameCallback((_) {
      _DialogoInformativo();
      });
      _mensajeMostrado = true;
    }
    WidgetsBinding.instance.addObserver(this);
    _future = _requestCameraAndInit();
  }

  void _DialogoInformativo() {
    showDialog(
      context: context,
      barrierDismissible:
          false, // El usuario debe presionar un botón para cerrar el diálogo
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('USO DE RED WIFI'),
          content: Text(
            'Esta aplicación necesita estar siempre conectada a la red wifi para el uso correcto de la misma. \nAsegurese de estar conectado a la red wifi antes de escanear los lotes.',
          ),
          actions: [
            TextButton(
              child: Text('Cerrar'),
              onPressed: () {
                Navigator.of(context).pop(); // Cierra el diálogo
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _requestCameraAndInit() async {
    final status = await Permission.camera.request();
    _isGranted = status == PermissionStatus.granted;

    if (_isGranted) {
      final cameras = await availableCameras();
      // Buscamos específicamente la cámara trasera (back),
      // ya que es la que se usa para escanear los LOTEs.
      for (var i = 0; i < cameras.length; i++) {
        if (cameras[i].lensDirection == CameraLensDirection.back) {
          await _selectedCamera(cameras[i]);
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopCamera();
    textRecognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      stopCamera();
    } else if (state == AppLifecycleState.resumed &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      startCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR APP')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }

          if (!_isGranted) {
            return _buildPermissionDenied();
          }

          if (_cameraController == null ||
              !_cameraController!.value.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              Center(child: CameraPreview(_cameraController!)),
              Column(
                children: [
                  Expanded(child: Container()),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 30.0),
                    child: MaterialButton(
                      color: const Color.fromRGBO(255, 120, 1, 1),
                      onPressed: _isProcessing ? null : _scan,
                      child: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Click para escanear',
                              style: TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Cámara no disponible.\nActiva el permiso de cámara para poder escanear.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => openAppSettings(),
              child: const Text('Abrir configuración'),
            ),
          ],
        ),
      ),
    );
  }

  void startCamera() {
    if (_cameraController != null) {
      _selectedCamera(_cameraController!.description);
    }
  }

  void stopCamera() {
    if (_cameraController != null) {
      _cameraController!.dispose();
    }
  }

  Future<void> _selectedCamera(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      // ResolutionPreset.high es suficiente para que el OCR lea bien el
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController!.initialize();

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _scan() async {
    if (_cameraController == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    XFile? picture;
    try {
      picture = await _cameraController!.takePicture();

      // Procesamos la imagen (escala de grises + contraste) en un hilo
      // separado, para que la app no se trabe mientras la convierte.
      final processedBytes = await compute(_convertToGrayscale, picture.path);
      await File(picture.path).writeAsBytes(processedBytes);

      final inputImage = InputImage.fromFile(File(picture.path));

      final recognizerText = await textRecognizer.processImage(inputImage);

      if (!mounted) return;

      widget.onScanResult(recognizerText.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      // Borramos la foto temporal: no la necesitamos guardada y así
      // evitamos que el almacenamiento del teléfono se vaya llenando
      // con fotos de cada escaneo del día.
      if (picture != null) {
        final tempFile = File(picture.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
