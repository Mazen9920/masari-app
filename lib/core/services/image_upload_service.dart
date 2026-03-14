import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Centralised service for picking images and uploading them to Firebase Storage.
class ImageUploadService {
  static final _picker = ImagePicker();
  static final _storage = FirebaseStorage.instance;

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
      debugPrint('[ImageUploadService] pickImage error: $e');
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
      final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
      debugPrint('[ImageUploadService] currentUser uid: ${currentUser?.uid}');
      debugPrint('[ImageUploadService] storagePath: $storagePath');
      debugPrint('[ImageUploadService] bucket: ${_storage.bucket}');
      final ref = _storage.ref().child(storagePath);
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e, st) {
      debugPrint('[ImageUploadService] uploadFile error: $e');
      debugPrint('[ImageUploadService] stackTrace: $st');
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
