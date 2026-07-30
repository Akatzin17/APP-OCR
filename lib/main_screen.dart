import 'package:flutter/material.dart';
import 'home_page.dart';
import 'result_page.dart';
import 'galeria_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String _textoEscaneado = '';

  void _onScanResult(String texto) {
    setState(() {
      _textoEscaneado = texto;
      _selectedIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onScanResult: _onScanResult), // índice 0 → Escaneo
      OcrGaleriaPage(onScanResult: _onScanResult), // índice 1 → Galería
      ResultPage(text: _textoEscaneado), // índice 2 → Formulario
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            if (index == 1) {
              _textoEscaneado = '';
            }
            _selectedIndex = index;
          });
        },
        selectedItemColor: const Color.fromRGBO(255, 120, 1, 1),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.document_scanner),
            label: 'Escaneo',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library),
            label: 'Subir Imagen',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Formulario',
          ),
        ],
      ),
    );
  }
}
