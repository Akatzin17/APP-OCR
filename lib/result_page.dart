import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

//URL como variable global
const String kBaseUrl = 'http://192.168.0.6:8084/';

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, this.text = ''});
  final String text;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _textoCompletoController;
  final _skuController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _loteController = TextEditingController();
  final _clienteController = TextEditingController();
  final _horarioController = TextEditingController();

  String? _tipoDanoSeleccionado;
  late String _fechaRegistro;
  bool _isUpdating = false;
  bool _usuarioEditando = false;

  final List<String> _tiposDano = [
    'Abollado',
    'Abollado por carga axial',
    'Charola despegada',
    'Charola Incompleta',
    'Charola rota',
    'Charola sucia o mojada',
    'Codigo Borroso',
    'Consumo preferente erroneo',
    'Daño en abrefácil',
    'Doble sticker',
    'Etiqueta cambiada',
    'Etiqueta descuadrada',
    'Etiqueta despegada',
    'Etiqueta rota',
    'Etiqueta sucia',
    'Falta de sticker en charola',
    'Lata con grasa',
    'Lata manchada',
    'Lata perforada',
    'Lata sin codigo',
    'Lata sin etiqueta',
    'Lata sin sticker',
    'Latas con óxido',
    'Mal cierre',
    'Presencia de caidas',
    'Sticker borroso',
    'Sticker erroneo',
    'Sticker sucio',
    'Sticker roto',
    'Termo flojo',
    'Termo quemado',
    'Termo roto',
  ];

  @override
  void initState() {
    super.initState();

    _textoCompletoController = TextEditingController(text: widget.text);
    _loteController.text = _extraerLote(widget.text);
    _horarioController.text = _extraerHorario(widget.text);

    final now = DateTime.now();
    _fechaRegistro =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Listener para actualizar lote en tiempo real
    _textoCompletoController.addListener(() {
      if (_isUpdating) return; // ← evita el loop
      if (_usuarioEditando) {
        //El usuario está editanto: Solo extraer lote/horario, NO sanitizar el texto.
        final texto = _textoCompletoController.text;
        final loteExtraido = _extraerLote(texto);
        final horarioExtraido = _extraerHorario(texto);

        setState(() {
          _horarioController.text = horarioExtraido;
        });

        if (loteExtraido != _loteController.text) {
          setState(() {
            _loteController.text = loteExtraido;
          });
          _buscarEnCatalogo(loteExtraido);
        }
        return;
      }

      //primera vez que se ejecuta el listener: el usuario no ha editado manualmente.
      final texto = _textoCompletoController.text;
      final loteExtraido = _usuarioEditando
          ? _extraerLote(texto)
          : _sanitizarLote(_extraerLote(texto)); // Solo sanitiza la primera vez
      final horarioExtraido = _extraerHorario(texto);

      // Reemplazar el lote crudo en el texto por el lote sanitizado
      if (loteExtraido.isNotEmpty) {
        final textoCorregido = _reemplazarLoteEnTexto(texto, loteExtraido);

        if (textoCorregido != texto) {
          _isUpdating = true;
          final cursor = _textoCompletoController
              .selection; // conserva posición del cursor
          _textoCompletoController.text = textoCorregido;
          _textoCompletoController.selection = cursor;
          _isUpdating = false;
        }
      }

      setState(() {
        _horarioController.text = horarioExtraido;
      });

      if (loteExtraido != _loteController.text) {
        setState(() {
          _loteController.text = loteExtraido;
        });
        _buscarEnCatalogo(loteExtraido);
      }

      //Despues del primer ciclo, marcar que ya fue sanitizado
      _usuarioEditando = true;
    });

    // Buscar al cargar si ya hay lote
    if (_loteController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _buscarEnCatalogo(_loteController.text);
      });
    }
  }

  /// Intento 1: busca "L XXXXXXXXXX" al inicio de línea.
  /// Intento 2 (fallback): busca cualquier bloque alfanumérico de 10-11 caracteres.
  String _extraerLote(String texto) {
    final regexConL = RegExp(
      r'(?:^|\n)\s*L\s+([A-Z0-9]{10,11})',
      caseSensitive: false,
    );
    final matchConL = regexConL.firstMatch(texto);
    if (matchConL != null) {
      return matchConL.group(1)?.trim() ?? '';
    }

    final regexFallback = RegExp(r'\b([A-Z0-9]{10,11})\b');
    final matchFallback = regexFallback.firstMatch(texto);
    return matchFallback?.group(1)?.trim() ?? '';
  }

  String _extraerHorario(String texto) {
    // Patrón más flexible: acepta I, l, L, 1 como separador además de ":"
    final regex = RegExp(r'\b(\d{2}[:\|IilL1]\d{2})\b');
    final match = regex.firstMatch(texto);
    final raw = match?.group(1)?.trim() ?? '';
    return _sanitizarHorario(raw); // <--
  }

  /// Corrige confusiones OCR en los primeros 9 chars (deben ser números)
  /// El char 10 puede ser número O letra, se deja como está pero se normaliza
  String _sanitizarLote(String lote) {
    if (lote.isEmpty) return lote;

    const letraANumero = {
      'O': '0',
      'o': '0',
      'I': '1',
      'i': '1',
      'l': '1',
      'S': '5',
      's': '5',
      'B': '8',
      'Z': '2',
      'z': '2',
      'G': '6',
      'T': '7',
    };

    final chars = lote.split('');
    final resultado = <String>[];

    for (int i = 0; i < chars.length; i++) {
      if (i < 9) {
        // Posiciones 0-8: deben ser números, corregir letras
        resultado.add(letraANumero[chars[i]] ?? chars[i]);
      } else {
        // Posición 9 (último): puede ser número o letra, se deja
        resultado.add(chars[i].toUpperCase());
      }
    }

    return resultado.join();
  }

  /// Corrige confusiones OCR en el horario (solo dígitos y ":")
  String _sanitizarHorario(String horario) {
    if (horario.isEmpty) return horario;

    const letraANumero = {
      'O': '0',
      'o': '0',
      'I': '1',
      'i': '1',
      'l': '1',
      'L': '1',
      'S': '5',
      's': '5',
      'B': '8',
      'Z': '2',
      'z': '2',
      'G': '6',
      'T': '7',
    };

    // Primero normalizamos todo el string carácter por carácter
    final sanitized = horario.split('').map((c) {
      if (c == ':') return ':';
      return letraANumero[c] ?? c;
    }).join();

    // Si el ":" fue detectado como 1, i, l o L entre dos pares de dígitos, lo restauramos
    // Patrón: DD[1iIlL]DD → DD:DD
    return sanitized.replaceAllMapped(
      RegExp(r'(\d{2})[1iIlL](\d{2})'),
      (m) => '${m.group(1)}:${m.group(2)}',
    );
  }

  String _reemplazarLoteEnTexto(String texto, String loteSanitizado) {
    // Intenta reemplazar con patrón "L XXXXXXXXXX"
    final regexConL = RegExp(
      r'((?:^|\n)\s*L\s+)([A-Z0-9]{10,11})',
      caseSensitive: false,
    );
    if (regexConL.hasMatch(texto)) {
      return texto.replaceFirstMapped(
        regexConL,
        (m) => '${m.group(1)}$loteSanitizado',
      );
    }

    // Fallback: reemplaza el bloque alfanumérico de 10-11 chars
    final regexFallback = RegExp(r'\b([A-Z0-9]{10,11})\b');
    if (regexFallback.hasMatch(texto)) {
      return texto.replaceFirstMapped(regexFallback, (m) => loteSanitizado);
    }

    return texto;
  }

  Future<void> _buscarEnCatalogo(String lote) async {
    if (lote.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('$kBaseUrl/buscar_catalogo.php?lote=$lote'),
      );

      final data = jsonDecode(response.body);

      if (data['found'] == true) {
        var longitud = data['data'].length;
        if (longitud > 1) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('LOTE a ocupar'),
                content: SingleChildScrollView(
                  child: ListBody(
                    children: <Widget>[
                      for (var i = 0; i < longitud; i++)
                        ListTile(
                          title: Text('SKU: ${data['data'][i]['SKU']}'),
                          subtitle: Text(
                            'Descripción: ${data['data'][i]['Descripcion']}',
                          ),
                          onTap: () {
                            setState(() {
                              _skuController.text = data['data'][i]['SKU']
                                  .toString();
                              _descripcionController.text =
                                  data['data'][i]['Descripcion'] ?? '';
                              _clienteController.text =
                                  data['data'][i]['Cliente'] ?? '';
                            });
                            Navigator.of(context).pop(); // Cierra el diálogo
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        }else {
          setState(() {
            _skuController.text = data['data'][0]['SKU'].toString();
            _descripcionController.text = data['data'][0]['Descripcion'] ?? '';
            _clienteController.text = data['data'][0]['Cliente'] ?? '';
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Datos encontrados en el catálogo'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${data['error'] ?? 'No encontrado'}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      // Si no encuentra, simplemente no autocompleta
      debugPrint('No encontrado en catálogo: $e');
    }
  }

  @override
  void dispose() {
    _textoCompletoController.dispose();
    _skuController.dispose();
    _descripcionController.dispose();
    _cantidadController.dispose();
    _loteController.dispose();
    _clienteController.dispose();
    _horarioController.dispose();
    super.dispose();
  }

  void _limpiarCampos() {
    setState(() {
      _textoCompletoController.clear();
      _skuController.clear();
      _descripcionController.clear();
      _cantidadController.clear();
      _loteController.clear();
      _clienteController.clear();
      _horarioController.clear();
      _tipoDanoSeleccionado = null;
      _usuarioEditando = false;
    });
  }

  Future<void> _guardarEnBD() async {
    try {
      final response = await http.post(
        Uri.parse('$kBaseUrl/guardar_escaneo.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fecha': _fechaRegistro,
          'sku': _skuController.text,
          'descripcion': _descripcionController.text,
          'cantidad': _cantidadController.text,
          'lote': _loteController.text,
          'motivo': _tipoDanoSeleccionado,
          'cliente': _clienteController.text,
          'horario': _horarioController.text,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro guardado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        _limpiarCampos();
      } else {
        throw Exception(data['error']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _enviarFormulario() {
    if (_formKey.currentState!.validate()) {
      _guardarEnBD();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resultado')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Fecha de registro ---
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'Fecha de registro: $_fechaRegistro',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // --- Texto completo editable ---
            const Text(
              'Texto completo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _textoCompletoController,
              maxLines: 5,
              onTap: () {
                _usuarioEditando = true;
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Texto escaneado (editable)',
                alignLabelWithHint: true,
                helperText:
                    'Edita el texto si algún carácter fue mal detectado',
              ),
            ),

            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),

            // --- Formulario ---
            const Text(
              'Datos del registro',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _loteController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Lote',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.inventory),
                      helperText:
                          'Se actualiza automáticamente al corregir el texto',
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Campo requerido'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _skuController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'SKU',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Campo requerido'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _horarioController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Horario',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.access_time),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Campo requerido'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _clienteController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Cliente',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Campo requerido'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Descripción (siempre ancho completo, puede ser larga)
                  TextFormField(
                    controller: _descripcionController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                    keyboardType: TextInputType.multiline,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Campo requerido'
                        : null,
                  ),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: _cantidadController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Campo requerido'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: _tipoDanoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de daño',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.warning_amber),
                    ),
                    items: _tiposDano
                        .map(
                          (tipo) =>
                              DropdownMenuItem(value: tipo, child: Text(tipo)),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _tipoDanoSeleccionado = value;
                      });
                    },
                    validator: (value) =>
                        value == null ? 'Selecciona un tipo de daño' : null,
                  ),
                  const SizedBox(height: 20),

                  // Botones
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _enviarFormulario,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color.fromRGBO(
                              255,
                              120,
                              1,
                              1,
                            ),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _limpiarCampos,
                          icon: const Icon(Icons.delete),
                          label: const Text('Borrar'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.white,
                            foregroundColor: const Color.fromRGBO(
                              255,
                              120,
                              1,
                              1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
