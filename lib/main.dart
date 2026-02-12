import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_scope.dart';
import 'config/build_config.dart';
import 'domain/usecases/build_instance_from_template.dart';
import 'models/structure_instance.dart';
import 'models/structure_template.dart';
import 'presentation/state/structures_state.dart';
import 'screens/create_template_screen.dart';
import 'screens/instance_selection_screen.dart';
import 'screens/pdf_library_screen.dart';
import 'screens/tag_management_screen.dart';
import 'services/data_service.dart';
import 'services/telemetry_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TelemetryService.instance.initialize();
  runApp(const AppScope(child: MyApp()));
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
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return Banner(
          location: BannerLocation.topEnd,
          message: appFlavor.name.toUpperCase(),
          color: appFlavor == AppFlavor.release ? Colors.green : Colors.orange,
          textStyle: const TextStyle(fontSize: 10),
          child: child,
        );
      },
    );
  }
}

class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataService = context.read<DataService>();
    return FutureBuilder<void>(
      future: dataService.initialize(),
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
      const StructuresHome(),
      PdfLibraryScreen(onDataChanged: () => setState(() {})),
      TagManagementScreen(onDataChanged: () => setState(() {})),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_tree_outlined), selectedIcon: Icon(Icons.account_tree), label: 'Estruturas'),
          NavigationDestination(icon: Icon(Icons.picture_as_pdf_outlined), selectedIcon: Icon(Icons.picture_as_pdf), label: 'Biblioteca'),
          NavigationDestination(icon: Icon(Icons.local_offer_outlined), selectedIcon: Icon(Icons.local_offer), label: 'Tags'),
        ],
      ),
    );
  }
}

class StructuresHome extends StatelessWidget {
  const StructuresHome({super.key});

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StructuresState(context.read<DataService>())..load(),
      child: Consumer<StructuresState>(
        builder: (context, state, _) {
          if (state.isLoading && state.templates.isEmpty && state.instances.isEmpty) {
            return const Scaffold(appBar: AppBar(title: Text('Partitura Maestro')), body: Center(child: CircularProgressIndicator()));
          }

          Future<void> refresh() => state.load();

          Future<void> createInstance(StructureTemplate template) async {
            final instance = await context.read<BuildInstanceFromTemplate>()(template);
            if (!context.mounted) return;
            await Navigator.push(context, MaterialPageRoute(builder: (context) => InstanceSelectionScreen(instance: instance)));
            await refresh();
          }

          Future<void> deleteTemplate(String templateId) async {
            await context.read<DataService>().deleteTemplate(templateId);
            await refresh();
          }

          return Scaffold(
            appBar: AppBar(title: const Text('Partitura Maestro')),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateTemplateScreen()));
                      await refresh();
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
                      if (state.templates.isEmpty) const ListTile(title: Text('Nenhuma estrutura criada ainda.')),
                      ...state.templates.map((template) => ListTile(
                            title: Text(template.name),
                            subtitle: Text('${template.slots.length} sub-estruturas'),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () async {
                                    await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateTemplateScreen(template: template)));
                                    await refresh();
                                  },
                                ),
                                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => deleteTemplate(template.id)),
                                FilledButton.tonal(onPressed: () => createInstance(template), child: const Text('Usar')),
                              ],
                            ),
                          )),
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
                              value: state.templateFilterId,
                              decoration: const InputDecoration(labelText: 'Filtrar por template'),
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                                ...state.templates.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                              ],
                              onChanged: (value) => state.setTemplateFilter(value),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: state.startDate ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (date == null) return;
                                      await state.setStartDate(date);
                                    },
                                    child: Text(state.startDate == null ? 'Data inicial' : 'Início: ${_formatDate(state.startDate!)}'),
                                  ),
                                ),
                                Expanded(
                                  child: TextButton(
                                    onPressed: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: state.endDate ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (date == null) return;
                                      await state.setEndDate(date.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
                                    },
                                    child: Text(state.endDate == null ? 'Data final' : 'Fim: ${_formatDate(state.endDate!)}'),
                                  ),
                                ),
                                IconButton(onPressed: state.clearFilters, icon: const Icon(Icons.filter_alt_off)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (state.instances.isEmpty) const ListTile(title: Text('Nenhuma instância encontrada para os filtros selecionados.')),
                      ...state.instances.map((StructureInstance instance) => ListTile(
                            title: Text(instance.name),
                            subtitle: Text('${instance.templateSnapshot.name} • ${_formatDate(instance.createdAt)} ${instance.isCompleted ? '• Concluída' : ''}'),
                            trailing: FilledButton.tonal(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => InstanceSelectionScreen(instance: instance)));
                                await refresh();
                              },
                              child: const Text('Abrir'),
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
