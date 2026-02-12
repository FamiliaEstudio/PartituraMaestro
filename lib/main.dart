import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models/structure_instance.dart';
import 'models/structure_template.dart';
import 'screens/create_template_screen.dart';
import 'screens/instance_selection_screen.dart';
import 'screens/pdf_library_screen.dart';
import 'screens/tag_management_screen.dart';
import 'services/data_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const BootstrapScreen(),
    );
  }
}

class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: DataService().initialize(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Erro ao inicializar dados: ${snapshot.error}')));
        }

        return const RootScreen();
      },
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
      StructuresHome(onDataChanged: () => setState(() {})),
      PdfLibraryScreen(onDataChanged: () => setState(() {})),
      TagManagementScreen(onDataChanged: () => setState(() {})),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
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
  late Future<Map<String, dynamic>> _loadFuture;
  String? _templateFilterId;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final templates = await _dataService.getTemplates();
    final instances = await _dataService.getInstances(
      templateId: _templateFilterId,
      startDate: _startDate,
      endDate: _endDate,
    );
    return {'templates': templates, 'instances': instances};
  }

  Future<void> _refresh() async {
    setState(() => _loadFuture = _loadData());
    widget.onDataChanged();
  }

  Future<void> _createInstance(BuildContext context, StructureTemplate template) async {
    final instance = StructureInstance(
      id: const Uuid().v4(),
      templateId: template.id,
      name: '${template.name} - ${DateTime.now().toString().split(' ')[0]}',
      createdAt: DateTime.now(),
      templateSnapshot: template,
    );
    await _dataService.addInstance(instance);

    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (context) => InstanceSelectionScreen(instance: instance)));
    await _refresh();
  }

  Future<void> _deleteTemplate(String templateId) async {
    await _dataService.deleteTemplate(templateId);
    await _refresh();
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(appBar: AppBar(title: Text('Partitura Maestro')), body: Center(child: CircularProgressIndicator()));
        }

        final templates = (snapshot.data?['templates'] as List<StructureTemplate>?) ?? <StructureTemplate>[];
        final instances = (snapshot.data?['instances'] as List<StructureInstance>?) ?? <StructureInstance>[];

        return Scaffold(
          appBar: AppBar(title: const Text('Partitura Maestro')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTemplateScreen()));
                    await _refresh();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Criar nova estrutura (template)'),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('Templates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (templates.isEmpty)
                      const ListTile(title: Text('Nenhuma estrutura criada ainda.')),
                    ...templates.map(
                      (template) => ListTile(
                        title: Text(template.name),
                        subtitle: Text('${template.slots.length} sub-estruturas'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => CreateTemplateScreen(template: template)),
                                );
                                await _refresh();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteTemplate(template.id),
                            ),
                            FilledButton.tonal(
                              onPressed: () => _createInstance(context, template),
                              child: const Text('Usar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('Instâncias criadas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String?>(
                            value: _templateFilterId,
                            decoration: const InputDecoration(labelText: 'Filtrar por template'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                              ...templates.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                            ],
                            onChanged: (value) {
                              setState(() => _templateFilterId = value);
                              _refresh();
                            },
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _startDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date == null) return;
                                    setState(() => _startDate = date);
                                    await _refresh();
                                  },
                                  child: Text(_startDate == null ? 'Data inicial' : 'Início: ${_formatDate(_startDate!)}'),
                                ),
                              ),
                              Expanded(
                                child: TextButton(
                                  onPressed: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _endDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date == null) return;
                                    setState(() => _endDate = date.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
                                    await _refresh();
                                  },
                                  child: Text(_endDate == null ? 'Data final' : 'Fim: ${_formatDate(_endDate!)}'),
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                    _templateFilterId = null;
                                  });
                                  await _refresh();
                                },
                                icon: const Icon(Icons.filter_alt_off),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (instances.isEmpty)
                      const ListTile(title: Text('Nenhuma instância encontrada para os filtros selecionados.')),
                    ...instances.map(
                      (instance) => ListTile(
                        title: Text(instance.name),
                        subtitle: Text(
                          '${instance.templateSnapshot.name} • ${_formatDate(instance.createdAt)} ${instance.isCompleted ? '• Concluída' : ''}',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => InstanceSelectionScreen(instance: instance)),
                            );
                            await _refresh();
                          },
                          child: const Text('Abrir'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
