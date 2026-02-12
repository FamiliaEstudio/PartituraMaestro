import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models/pdf_file.dart';
import 'models/structure_instance.dart';
import 'models/tag.dart';
import 'screens/create_template_screen.dart';
import 'screens/instance_selection_screen.dart';
import 'screens/pdf_library_screen.dart';
import 'screens/tag_management_screen.dart';
import 'services/data_service.dart';

void main() {
  final service = DataService();

  if (service.getTags().isEmpty && service.getPdfs().isEmpty) {
    service.addTag(Tag(id: 't1', name: 'Entrada'));
    service.addTag(Tag(id: 't2', name: 'Natal'));
    service.addTag(Tag(id: 't3', name: 'Glória'));

    service.addPdf(
      PdfFile(
        id: 'p1',
        path: '/docs/canto1.pdf',
        title: 'Canto de Entrada Natal',
        tagIds: ['t1', 't2'],
      ),
    );
    service.addPdf(
      PdfFile(
        id: 'p2',
        path: '/docs/canto2.pdf',
        title: 'Glória Solene',
        tagIds: ['t3'],
      ),
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Partitura Maestro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      StructuresHome(
        onDataChanged: () => setState(() {}),
      ),
      PdfLibraryScreen(
        onDataChanged: () => setState(() {}),
      ),
      TagManagementScreen(
        onDataChanged: () => setState(() {}),
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: 'Estruturas',
          ),
          NavigationDestination(
            icon: Icon(Icons.picture_as_pdf_outlined),
            selectedIcon: Icon(Icons.picture_as_pdf),
            label: 'Biblioteca',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_offer_outlined),
            selectedIcon: Icon(Icons.local_offer),
            label: 'Tags',
          ),
        ],
      ),
    );
  }
}

class StructuresHome extends StatefulWidget {
  const StructuresHome({super.key, required this.onDataChanged});

  final VoidCallback onDataChanged;

  @override
  State<StructuresHome> createState() => _StructuresHomeState();
}

class _StructuresHomeState extends State<StructuresHome> {
  final DataService _dataService = DataService();

  void _createInstance(BuildContext context, String templateId, String templateName) {
    final instance = StructureInstance(
      id: const Uuid().v4(),
      templateId: templateId,
      name: '$templateName - ${DateTime.now().toString().split(' ')[0]}',
      createdAt: DateTime.now(),
    );
    _dataService.addInstance(instance);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstanceSelectionScreen(instance: instance),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final templates = _dataService.getTemplates();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partitura Maestro'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CreateTemplateScreen()),
                ).then((_) {
                  setState(() {});
                  widget.onDataChanged();
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Criar nova estrutura (template)'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: templates.isEmpty
                ? const Center(
                    child: Text('Nenhuma estrutura criada ainda.'),
                  )
                : ListView.builder(
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      return ListTile(
                        title: Text(template.name),
                        subtitle: Text('${template.slots.length} sub-estruturas'),
                        trailing: FilledButton.tonal(
                          onPressed: () => _createInstance(
                            context,
                            template.id,
                            template.name,
                          ),
                          child: const Text('Usar'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
