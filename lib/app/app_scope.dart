import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../domain/usecases/assign_pdf_tags.dart';
import '../domain/usecases/build_instance_from_template.dart';
import '../domain/usecases/create_template.dart';
import '../domain/usecases/find_candidate_pdfs.dart';
import '../services/data_service.dart';

class AppScope extends StatelessWidget {
  const AppScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DataService>(create: (_) => DataService()),
        ProxyProvider<DataService, CreateTemplate>(
          update: (_, dataService, __) => CreateTemplate(dataService),
        ),
        ProxyProvider<DataService, AssignPdfTags>(
          update: (_, dataService, __) => AssignPdfTags(dataService),
        ),
        ProxyProvider<DataService, BuildInstanceFromTemplate>(
          update: (_, dataService, __) => BuildInstanceFromTemplate(dataService),
        ),
        ProxyProvider<DataService, FindCandidatePdfs>(
          update: (_, dataService, __) => FindCandidatePdfs(dataService),
        ),
      ],
      child: child,
    );
  }
}
