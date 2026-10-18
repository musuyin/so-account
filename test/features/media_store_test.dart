import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/platform/media/media_store.dart';

void main() {
  test('orphan collection preserves referenced and recent photos', () async {
    final root = await Directory.systemTemp.createTemp('so_media_');
    try {
      final store = MediaStore(root);
      await Directory('${root.path}/media').create();
      for (final name in ['referenced', 'orphan', 'recent']) {
        final file = store.resolve('media/$name.jpg');
        await file.writeAsBytes([1]);
        if (name != 'recent') {
          await file.setLastModified(
            DateTime.now().subtract(const Duration(days: 2)),
          );
        }
      }
      await store.collectOrphans({'media/referenced.jpg'});
      expect(await store.resolve('media/referenced.jpg').exists(), isTrue);
      expect(await store.resolve('media/recent.jpg').exists(), isTrue);
      expect(await store.resolve('media/orphan.jpg').exists(), isFalse);
      expect(() => store.resolve('../private.jpg'), throwsFormatException);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
