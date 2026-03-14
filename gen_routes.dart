// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  final screens = [
    'EditProfileScreen', 'BusinessInfoScreen', 'CurrencyLanguageScreen', 'ManageSubscriptionScreen',
    'NotificationPreferencesScreen', 'SecurityScreen', 'DataBackupScreen', 'HelpCenterScreen', 'AboutScreen',
    'PaymentsSummaryScreen', 'PurchasesSummaryScreen', 'InventorySettingsScreen', 'PinnedActionsScreen',
    'ReportPreviewScreen', 'AiChatScreen', 'ScheduledTransactionsScreen'
  ];
  
  final base = Directory('lib');
  final map = <String, String>{};
  for (var entity in base.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = entity.readAsStringSync();
      for (var s in screens) {
        if (content.contains('class $s')) {
          map[s] = entity.path;
        }
      }
    }
  }
  
  print('// Imports:');
  for (var s in screens) {
    if (map.containsKey(s)) {
      final p = map[s]!.replaceFirst('lib/', '../../');
      print("import '$p';");
    }
  }
  
  print('// Routes:');
  for (var s in screens) {
    if (map.containsKey(s)) {
      final p = map[s]!.replaceAll('lib/features/', '/').replaceAll('_screen.dart', '').replaceAll('.dart', '');
      print('''      GoRoute(
        name: '$s',
        path: '$p',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const $s(),
      ),''');
    }
  }
}
