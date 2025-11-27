import 'package:flutter/material.dart';
import 'screens/create_template_screen.dart';
import 'screens/instance_selection_screen.dart';
import 'services/data_service.dart';
import 'models/tag.dart';
import 'models/pdf_file.dart';
import 'models/structure_instance.dart';
import 'package:uuid/uuid.dart';

void main() {
  // Inicialização de dados fictícios para teste
  final service = DataService();
  if (service.getTags().isEmpty) {
    service.addTag(Tag(id: 't1', name: 'Entrada'));
    service.addTag(Tag(id: 't2', name: 'Natal'));
    service.addTag(Tag(id: 't3', name: 'Glória'));
    service.addPdf(PdfFile(id: 'p1', path: '/docs/canto1.pdf', title: 'Canto de Entrada Natal', tagIds: ['t1', 't2']));
    service.addPdf(PdfFile(id: 'p2', path: '/docs/canto2.pdf', title: 'Glória Solene', tagIds: ['t3']));
    service.addPdf(PdfFile(id: 'p3', path: '/docs/canto3.pdf', title: 'Canto Genérico', tagIds: []));
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pastoral PDF Organizer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DataService _dataService = DataService();

  void _createInstance(BuildContext context, String templateId, String templateName) {
    // Cria uma nova instância da estrutura
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
      appBar: AppBar(title: const Text('Organizador Pastoral')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CreateTemplateScreen()),
                ).then((_) => setState(() {})); // Atualiza a lista ao voltar
              },
              child: const Text('Criar Nova Estrutura (Template)'),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('Estruturas Disponíveis:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: templates.isEmpty
                ? const Center(child: Text('Nenhuma estrutura criada.'))
                : ListView.builder(
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      return ListTile(
                        title: Text(template.name),
                        subtitle: Text('${template.slots.length} partes'),
                        trailing: ElevatedButton(
                          child: const Text('Usar'),
                          onPressed: () => _createInstance(context, template.id, template.name),
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
