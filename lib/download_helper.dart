import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> guardarArchivo(List<int> bytes, String nombreArchivo) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$nombreArchivo');
  await file.writeAsBytes(bytes);
}
