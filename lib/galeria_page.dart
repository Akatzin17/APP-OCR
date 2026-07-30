import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';
import 'home_page.dart';

class OcrGaleriaPage extends StatefulWidget {
  const OcrGaleriaPage({super.key, required this.onScanResult});
  final Function(String texto) onScanResult;

  @override
  State<OcrGaleriaPage> createState() => _OcrGaleriaPageState();
}

class _OcrGaleriaPageState extends State<OcrGaleriaPage> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  File? _imagenSeleccionada;
  String _textoDetectado = '';
  bool _cargando = false;
  bool _aplicarFiltro = false; // igual que tu checkbox en el flujo actual

  Future<void> _seleccionarImagen() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600, // Ajusta según tus necesidades
      imageQuality: 85, // Ajusta según tus necesidades
      );

    if (archivo == null) return; // usuario canceló

    setState(() {
      _imagenSeleccionada = File(archivo.path);
      _textoDetectado = '';
      _cargando = true;
    });

    await _procesarOcr(_imagenSeleccionada!);
  }

  Future<void> _procesarOcr(File imagen) async {
    try {
      File imagenAProcesar = imagen;

      if (_aplicarFiltro) {
        // Reutiliza tu misma función de preprocesamiento vía compute()
        imagenAProcesar = await _preprocesarImagen(imagen);
      }

      final inputImage = InputImage.fromFile(imagenAProcesar);
      final RecognizedText resultado = await _textRecognizer.processImage(
        inputImage,
      );

      setState(() {
        _textoDetectado = resultado.text;
        _cargando = false;
      });

      if (!mounted) return;
      widget.onScanResult(_textoDetectado); // Devuelve el texto al MainScreen
    } catch (e) {
      setState(() {
        _textoDetectado = 'Error al procesar OCR: $e';
        _cargando = false;
      });
    }
  }

  // Placeholder: aquí llamas a tu isolate de preprocesamiento existente
  Future<File> _preprocesarImagen(File original) async {
    final processedBytes = await compute(convertToGrayscale, original.path);
    final tempPath = '${original.path}_procesada.jpg';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(processedBytes);
    return tempFile;
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR desde galería')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _seleccionarImagen,
              icon: const Icon(Icons.photo_library),
              label: const Text('Seleccionar foto de la galería'),
            ),
            CheckboxListTile(
              title: const Text('Aplicar filtro (escala de grises)'),
              value: _aplicarFiltro,
              onChanged: (v) => setState(() => _aplicarFiltro = v ?? false),
            ),
            const SizedBox(height: 12),
            if (_imagenSeleccionada != null)
              Image.file(
                _imagenSeleccionada!,
                height: 250,
                fit: BoxFit.contain,
              ),
            const SizedBox(height: 12),
            if (_cargando) const Center(child: CircularProgressIndicator()),
            if (!_cargando && _textoDetectado.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_textoDetectado),
              ),
          ],
        ),
      ),
    );
  }
}
