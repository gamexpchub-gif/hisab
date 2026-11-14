import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'theme.dart';

/// Lets the user take or choose a photo and copies it into the app's own
/// storage. Returns the stored file path, '' when the user chose "Remove",
/// or null when cancelled.
Future<String?> pickPhoto(BuildContext context, {String folder = 'images', bool allowRemove = false}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: C.purple2),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(c, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: C.purple2),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          if (allowRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: C.red),
              title: const Text('Remove photo'),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
        ]),
      ),
    ),
  );
  if (choice == null) return null;
  if (choice == 'remove') return '';
  final picked = await ImagePicker().pickImage(
    source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1200,
    maxHeight: 1200,
    imageQuality: 85,
  );
  if (picked == null) return null;
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, folder));
  await dir.create(recursive: true);
  final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
  final dest = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}$ext');
  await File(picked.path).copy(dest);
  return dest;
}

/// Shows a stored photo path, a bundled design image ("asset:name"), or a fallback.
Widget storedImage(String? ref, {BoxFit fit = BoxFit.cover, Widget? fallback}) {
  if (ref != null && ref.startsWith('asset:')) {
    return Image.asset('assets/products/tile_${ref.substring(6)}.png', fit: fit);
  }
  if (ref != null && ref.isNotEmpty && File(ref).existsSync()) {
    return Image.file(File(ref), fit: fit, errorBuilder: (_, __, ___) => fallback ?? const SizedBox());
  }
  return fallback ?? const SizedBox();
}
