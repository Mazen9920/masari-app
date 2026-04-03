import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

/// Thin wrapper around file I/O, share_plus and printing.
class ShareService {
  /// Compute the share origin rect from a [BuildContext].
  /// On iPad this positions the share popover; on iPhone it's ignored.
  static Rect? originFrom(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Save bytes to a temporary file and return the [File].
  Future<File> _saveTempFile(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Save CSV string to a temporary file.
  Future<File> _saveTempCsv(String csvContent, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csvContent);
    return file;
  }

  // ─────────────────────────────────────────────────
  //  PDF actions
  // ─────────────────────────────────────────────────

  /// Share PDF via native share sheet.
  Future<void> sharePdf(Uint8List pdfBytes, String filename,
      {String? subject, Rect? origin}) async {
    final file = await _saveTempFile(pdfBytes, filename);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: subject ?? filename,
      sharePositionOrigin: origin,
    );
  }

  /// Print / preview PDF using system print dialog.
  Future<void> printPdf(Uint8List pdfBytes, String documentName) async {
    await Printing.layoutPdf(
      onLayout: (_) => pdfBytes,
      name: documentName,
    );
  }

  /// Save PDF to the app's documents directory (persistent).
  Future<File> savePdf(Uint8List pdfBytes, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/reports');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File('${folder.path}/$filename');
    await file.writeAsBytes(pdfBytes);
    return file;
  }

  // ─────────────────────────────────────────────────
  //  CSV actions
  // ─────────────────────────────────────────────────

  /// Share CSV via native share sheet.
  Future<void> shareCsv(String csvContent, String filename,
      {String? subject, Rect? origin}) async {
    final file = await _saveTempCsv(csvContent, filename);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: subject ?? filename,
      sharePositionOrigin: origin,
    );
  }

  /// Save CSV to persistent storage.
  Future<File> saveCsv(String csvContent, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/exports');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File('${folder.path}/$filename');
    await file.writeAsString(csvContent);
    return file;
  }

  /// Share multiple files at once (e.g. "Export All Data").
  Future<void> shareMultipleFiles(List<XFile> files,
      {String? subject, Rect? origin}) async {
    await Share.shareXFiles(files,
        subject: subject ?? 'Revvo Export',
        sharePositionOrigin: origin);
  }

  // ─────────────────────────────────────────────────
  //  Text share (for "Share Revvo" etc.)
  // ─────────────────────────────────────────────────

  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    await Share.share(text,
        subject: subject, sharePositionOrigin: origin);
  }
}
