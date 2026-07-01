import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'result_page.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xcel;
import 'download_helper.dart';
import 'package:intl/intl.dart';

class HistorialPage extends StatefulWidget {
  const HistorialPage({super.key});

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  List<Map<String, dynamic>> _escaneos = [];
  bool _cargando = false;
  String? _error;

  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  String _formatearFecha(DateTime fecha) {
    return '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
  }

  String _formatearFechaDisplay(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }

  String obtenerTurno(String? horario) {
  if (horario == null) return '';
  if (horario.compareTo('06:00') >= 0 && horario.compareTo('14:00') < 0) {
    return 'Primero';
  } else if (horario.compareTo('14:00') >= 0 && horario.compareTo('22:00') < 0) {
    return 'Segundo';
  } else {
    return 'Tercero';
  }
}

  Future<void> _seleccionarFecha(BuildContext context, bool esDesde) async {
    final inicial = esDesde
        ? (_fechaDesde ?? DateTime.now())
        : (_fechaHasta ?? DateTime.now());

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color.fromRGBO(255, 120, 1, 1),
            ),
          ),
          child: child!,
        );
      },
    );

    if (seleccionada != null) {
      setState(() {
        if (esDesde) {
          _fechaDesde = seleccionada;
        } else {
          _fechaHasta = seleccionada;
        }
      });
    }
  }

  Future<void> _buscarEscaneos() async {
    if (_fechaDesde == null || _fechaHasta == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona ambas fechas para filtrar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_fechaDesde!.isAfter(_fechaHasta!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha "Desde" no puede ser mayor que "Hasta"'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
      _escaneos = [];
    });

    try {
      final desde = _formatearFecha(_fechaDesde!);
      final hasta = _formatearFecha(_fechaHasta!);

      final response = await http.get(
        Uri.parse('$kBaseUrl/listar_escaneos.php?desde=$desde&hasta=$hasta'),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(() {
          _escaneos = List<Map<String, dynamic>>.from(data['data']);
        });
      } else {
        setState(() {
          _error = data['error'] ?? 'Error al obtener los datos';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() {
        _cargando = false;
      });
    }
  }

  Future<void> _cargarTodos() async {
    setState(() {
      _cargando = true;
      _error = null;
      _escaneos = [];
      _fechaDesde = null;
      _fechaHasta = null;
    });

    try {
      final response = await http.get(
        Uri.parse('$kBaseUrl/listar_escaneos.php'),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(() {
          _escaneos = List<Map<String, dynamic>>.from(data['data']);
        });
      } else {
        setState(() {
          _error = data['error'] ?? 'Error al obtener los datos';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() {
        _cargando = false;
      });
    }
  }

  Future<void> _exportarExcel() async {
    setState(() => _cargando = true);
    try {
      final workbook = xcel.Workbook();
      final sheet = workbook.worksheets[0];
      DateTime now = DateTime.now();
      String fechaArchivo = DateFormat('yyyy-MM-dd').format(now);

      final headers = [
        'Fecha',
        'Cantidad',
        'SKU',
        'País/Cliente',
        'Descripción',
        'Lote',
        'Horario',
        'Turno',
        'Defecto detectado',
      ];
      // Escribir encabezados
      for (int i = 0; i < headers.length; i++) {
        sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
      }
      // Escribir datos
      for (int i = 0; i < _escaneos.length; i++) {
        final escaneo = _escaneos[i];
        sheet.getRangeByIndex(i + 2, 1).setText(escaneo['Fecha'] ?? '');
        sheet
            .getRangeByIndex(i + 2, 2)
            .setNumber((escaneo['Cantidad'] ?? 0).toDouble());
        sheet
            .getRangeByIndex(i + 2, 3)
            .setText(escaneo['SKU']?.toString() ?? '');
        sheet.getRangeByIndex(i + 2, 4).setText(escaneo['Cliente'] ?? '');
        sheet.getRangeByIndex(i + 2, 5).setText(escaneo['Descripcion'] ?? '');
        sheet.getRangeByIndex(i + 2, 6).setText(escaneo['LOTE'] ?? '');
        sheet.getRangeByIndex(i + 2, 7).setText(escaneo['Horario'] ?? '');
        sheet.getRangeByIndex(i + 2, 8).setText(obtenerTurno(escaneo['Horario'] as String?));
        sheet.getRangeByIndex(i + 2, 9).setText(escaneo['Motivo'] ?? '');
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      await guardarArchivo(bytes, 'historial_escaneos_$fechaArchivo.xlsx');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Archivo Excel generado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarTodos(); // Carga todos los registros al abrir
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Título ──
          const Text(
            'Historial de escaneos',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // ── Filtro de fechas ──
          Row(
            children: [
              // Fecha desde
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _seleccionarFecha(context, true),
                  icon: const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Color.fromRGBO(255, 120, 1, 1),
                  ),
                  label: Text(
                    _fechaDesde != null
                        ? 'Desde: ${_formatearFechaDisplay(_fechaDesde!)}'
                        : 'Fecha desde',
                    style: const TextStyle(
                      color: Color.fromRGBO(255, 120, 1, 1),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color.fromRGBO(255, 120, 1, 1),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Fecha hasta
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _seleccionarFecha(context, false),
                  icon: const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Color.fromRGBO(255, 120, 1, 1),
                  ),
                  label: Text(
                    _fechaHasta != null
                        ? 'Hasta: ${_formatearFechaDisplay(_fechaHasta!)}'
                        : 'Fecha hasta',
                    style: const TextStyle(
                      color: Color.fromRGBO(255, 120, 1, 1),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color.fromRGBO(255, 120, 1, 1),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botón buscar
              ElevatedButton.icon(
                onPressed: _buscarEscaneos,
                icon: const Icon(Icons.search),
                label: const Text('Buscar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(255, 120, 1, 1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botón ver todos
              OutlinedButton.icon(
                onPressed: _cargarTodos,
                icon: const Icon(
                  Icons.refresh,
                  color: Color.fromRGBO(255, 120, 1, 1),
                ),
                label: const Text(
                  'Ver todos',
                  style: TextStyle(color: Color.fromRGBO(255, 120, 1, 1)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color.fromRGBO(255, 120, 1, 1)),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Botón exportar (opcional)
              OutlinedButton.icon(
                onPressed: _exportarExcel,
                icon: const Icon(
                  Icons.file_download,
                  color: Color.fromRGBO(255, 120, 1, 1),
                ),
                label: const Text(
                  'Exportar',
                  style: TextStyle(color: Color.fromRGBO(255, 120, 1, 1)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color.fromRGBO(255, 120, 1, 1)),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Contador de resultados ──
          if (!_cargando && _error == null)
            Text(
              '${_escaneos.length} registro(s) encontrado(s)',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),

          const SizedBox(height: 8),

          // ── Contenido ──
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color.fromRGBO(255, 120, 1, 1),
                    ),
                  )
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _cargarTodos,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : _escaneos.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'No hay registros en ese rango de fechas',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          const Color.fromRGBO(255, 120, 1, 0.1),
                        ),
                        columns: const [
                          DataColumn(
                            label: Text(
                              'Fecha',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Cantidad',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'SKU',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Cliente/Cliente',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Descripción',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Lote',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Horario',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Turno',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Defecto detectado',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        rows: _escaneos.map((escaneo) {
                          return DataRow(
                            cells: [
                              DataCell(Text(escaneo['Fecha'] ?? '')),
                              DataCell(
                                Text(escaneo['Cantidad']?.toString() ?? ''),
                              ),
                              DataCell(Text(escaneo['SKU']?.toString() ?? '')),
                              DataCell(Text(escaneo['Cliente'] ?? '')),
                              DataCell(
                                SizedBox(
                                  width: 200,
                                  child: Text(
                                    escaneo['Descripcion'] ?? '',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text(escaneo['LOTE'] ?? '')),
                              DataCell(Text(escaneo['Horario'] ?? '')),
                              DataCell(
                                Text(obtenerTurno(escaneo['Horario'] as String?)),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    escaneo['Motivo'] ?? '',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
