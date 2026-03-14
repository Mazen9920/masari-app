// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  final file = File('lib/features/profile/profile_screen.dart');
  String content = file.readAsStringSync();
  
  final navPattern = RegExp(r'_navigate\(context,\s*const\s+([A-Za-z0-9_]+)\(\)\)');
  content = content.replaceAllMapped(navPattern, (match) {
    return 'context.pushNamed(\'${match.group(1)}\')';
  });

  if (!content.contains('package:go_router/go_router.dart')) {
    content = "import 'package:go_router/go_router.dart';\n$content";
  }
  
  file.writeAsStringSync(content);
  print('Updated profile_screen.dart');
}
