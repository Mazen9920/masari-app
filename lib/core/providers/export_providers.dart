import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/report_service.dart';
import '../services/share_service.dart';

/// Singleton providers for the export services.
final reportServiceProvider = Provider<ReportService>((_) => ReportService());
final shareServiceProvider = Provider<ShareService>((_) => ShareService());
