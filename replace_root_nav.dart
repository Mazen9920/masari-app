// ignore_for_file: avoid_print, unused_local_variable
import 'dart:io';

void main() {
  final dir = Directory('lib');
  int filesModified = 0;

  // Pattern exactly matching: 
  // Navigator.of(context, rootNavigator: true).push(
  //   MaterialPageRoute(
  //     builder: (_) => const ScreenName(),
  //   ),
  // );
  // Note: we can be general to handle varied whitespace
  final navPattern = RegExp(
    r'Navigator\.of\(context,\s*rootNavigator:\s*true\)\.push\(\s*MaterialPageRoute\(\s*builder:\s*\(\_\)\s*=>\s*const\s+([A-Za-z0-9_]+)\(\),\s*\),\s*\);',
  );
  
  // Also without rootNavigator
   final navPattern2 = RegExp(
    r'Navigator\.of\(context\)\.push\(\s*MaterialPageRoute\(\s*builder:\s*\(\_\)\s*=>\s*const\s+([A-Za-z0-9_]+)\(\),\s*\),\s*\);',
  );

  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;

    String content = file.readAsStringSync();
    bool changed = false;

    if (content.contains(navPattern) || content.contains(navPattern2)) {
      content = content.replaceAllMapped(navPattern, (match) {
        final screenName = match.group(1);
        return 'context.pushNamed(\'$screenName\');';
      });
      content = content.replaceAllMapped(navPattern2, (match) {
        final screenName = match.group(1);
        return 'context.pushNamed(\'$screenName\');';
      });
      changed = true;
    }

    if (changed) {
      if (!content.contains('package:go_router/go_router.dart')) {
        content = "import 'package:go_router/go_router.dart';\n$content";
      }
      file.writeAsStringSync(content);
      filesModified++;
      print('Updated \${file.path}');
    }
  }

  print('Modified \$filesModified files.');
}
