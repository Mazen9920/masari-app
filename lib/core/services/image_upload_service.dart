import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// Centralised service for picking images and uploading them to Firebase Storage.
class ImageUploadService {
  static final _picker = ImagePicker();
  static final _storage = FirebaseStorage.instance;

  /// Max upload size — must match Storage Rules (5 MB).
  static const _maxBytes = 5 * 1024 * 1024;

  /// Allowed image MIME types — must match Storage Rules.
  static const _allowedTypes = <String, String>{
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.gif': 'image/gif',
    '.heic': 'image/heic',
    '.heif': 'image/heif',
  };

  /// Shows a source picker (camera / gallery) and returns the chosen [XFile],
  /// or `null` if the user cancelled.
  static Future<XFile?> pickImage({
    ImageSource source = ImageSource.gallery,
    int maxWidth = 1024,
    int maxHeight = 1024,
    int imageQuality = 80,
  }) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: imageQuality,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageUploadService] pickImage error: $e');
      return null;
    }
  }

  /// Uploads [file] to Firebase Storage at [storagePath] and returns the
  /// public download URL, or `null` on failure.
  static Future<String?> uploadFile({
    required File file,
    required String storagePath,
  }) async {
    try {
      // ── Client-side validation (mirrors Storage Rules) ──────────
      final size = await file.length();
      if (size > _maxBytes) {
        if (kDebugMode) debugPrint('[ImageUploadService] rejected: file too large ($size bytes, max $_maxBytes)');
        return null;
      }

      final ext = p.extension(file.path).toLowerCase();
      final contentType = _allowedTypes[ext];
      if (contentType == null) {
        if (kDebugMode) debugPrint('[ImageUploadService] rejected: unsupported type "$ext"');
        return null;
      }

      if (kDebugMode) debugPrint('[ImageUploadService] uploading ${size ~/ 1024} KB ($ext) to $storagePath');
      final ref = _storage.ref().child(storagePath);
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ImageUploadService] uploadFile error: $e');
        debugPrint('[ImageUploadService] stackTrace: $st');
      }
      return null;
    }
  }

  /// Deletes the file at [storagePath]. Fails silently.
  static Future<void> deleteFile(String storagePath) async {
    try {
      await _storage.ref().child(storagePath).delete();
    } catch (_) {}
  }

  /// Convenience: pick from gallery + upload to [storagePath].
  /// Returns the download URL or `null`.
  static Future<String?> pickAndUpload({
    required String storagePath,
    ImageSource source = ImageSource.gallery,
  }) async {
    final xFile = await pickImage(source: source);
    if (xFile == null) return null;
    return uploadFile(file: File(xFile.path), storagePath: storagePath);
  }
}
