import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pdf_file.dart';
import '../models/structure_instance.dart';
import '../models/structure_template.dart';
import '../services/data_service.dart';
import 'pdf_viewer_screen.dart';

class CelebrationModeScreen extends StatefulWidget {
  const CelebrationModeScreen({super.key, required this.instance});

  final StructureInstance instance;

  @override
  State<CelebrationModeScreen> createState() => _CelebrationModeScreenState();
}

class _CelebrationModeScreenState extends State<CelebrationModeScreen> {
  late Future<_CelebrationData> _future;
  int _currentSlotIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_CelebrationData> _loadData() async {
    final latest = await context.read<DataService>().getInstance(widget.instance.id);
    final instance = latest ?? widget.instance;
    final template = instance.templateSnapshot;
    final pdfs = await context.read<DataService>().getPdfs();
    final selections = await context.read<DataService>().getInstanceSelections(instance.id);
    return _CelebrationData(template: template, pdfs: pdfs, selections: selections);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadData();
    });
  }

  void _moveSlot(int offset, int totalSlots) {
    setState(() {
      _currentSlotIndex = (_currentSlotIndex + offset).clamp(0, totalSlots - 1);
    });
  }

  Future<void> _openCurrentSlotPdf(_CelebrationData data) async {
    final slot = data.template.slots[_currentSlotIndex];
    final selectedIds = data.selections[slot.id] ?? const <String>[];
    final currentPdf = data.findPdfById(selectedIds.isNotEmpty ? selectedIds.first : null);
    final nextPdf = _findNextSlotFirstPdf(data);

    if (currentPdf == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este slot ainda não possui PDF selecionado.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          pdfFile: currentPdf,
          prefetchedPdfFile: nextPdf,
        ),
      ),
    );
    await _refresh();
  }

  PdfFile? _findNextSlotFirstPdf(_CelebrationData data) {
    for (var index = _currentSlotIndex + 1; index < data.template.slots.length; index++) {
      final slot = data.template.slots[index];
      final selectedIds = data.selections[slot.id] ?? const <String>[];
      if (selectedIds.isEmpty) continue;
      final nextPdf = data.findPdfById(selectedIds.first);
      if (nextPdf != null) return nextPdf;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modo celebração')),
      body: FutureBuilder<_CelebrationData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('Não foi possível carregar a instância.'));
          }

          final data = snapshot.data!;
          if (data.template.slots.isEmpty) {
            return const Center(child: Text('Esta instância não possui slots.'));
          }

          _currentSlotIndex = _currentSlotIndex.clamp(0, data.template.slots.length - 1);
          final completedSlots = data.template.slots.where((slot) => (data.selections[slot.id] ?? const <String>[]).isNotEmpty).length;
          final progress = completedSlots / data.template.slots.length;
          final currentSlot = data.template.slots[_currentSlotIndex];
          final currentSlotSelection = data.selections[currentSlot.id] ?? const <String>[];
          final currentPdf = data.findPdfById(currentSlotSelection.isNotEmpty ? currentSlotSelection.first : null);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Progresso da instância: $completedSlots/${data.template.slots.length} slots preenchidos',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Slot atual: ${currentSlot.name}', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        currentPdf != null ? 'PDF principal: ${currentPdf.displayName}' : 'Sem PDF selecionado neste slot.',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _currentSlotIndex == 0
                                  ? null
                                  : () => _moveSlot(-1, data.template.slots.length),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Anterior slot'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _openCurrentSlotPdf(data),
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Abrir PDF atual'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _currentSlotIndex == data.template.slots.length - 1
                                  ? null
                                  : () => _moveSlot(1, data.template.slots.length),
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Próximo slot'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: data.template.slots.length,
                  itemBuilder: (context, index) {
                    final slot = data.template.slots[index];
                    final selectedIds = data.selections[slot.id] ?? const <String>[];
                    final hasSelection = selectedIds.isNotEmpty;
                    final isCurrent = index == _currentSlotIndex;
                    final slotPdf = data.findPdfById(hasSelection ? selectedIds.first : null);

                    return ListTile(
                      selected: isCurrent,
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(slot.name),
                      subtitle: Text(
                        hasSelection
                            ? 'Preenchido • ${slotPdf?.displayName ?? 'PDF selecionado'}'
                            : 'Pendente',
                      ),
                      trailing: Icon(
                        hasSelection ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: hasSelection ? Colors.green : null,
                      ),
                      onTap: () {
                        setState(() {
                          _currentSlotIndex = index;
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CelebrationData {
  const _CelebrationData({
    required this.template,
    required this.pdfs,
    required this.selections,
  });

  final StructureTemplate template;
  final List<PdfFile> pdfs;
  final Map<String, List<String>> selections;

  PdfFile? findPdfById(String? id) {
    if (id == null) return null;
    for (final pdf in pdfs) {
      if (pdf.id == id) return pdf;
    }
    return null;
  }
}
