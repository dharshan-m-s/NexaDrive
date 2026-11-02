import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/services/upload_item.dart';
import 'package:nexadrive/services/upload_manager.dart';
import 'package:nexadrive/services/upload_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late File journal;
  late UploadManager manager;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nexadrive-queue-test');
    journal = File('${root.path}/queue.jsonl');
    manager = UploadManager.forTesting(journal);
    await manager.ready;
  });

  tearDown(() async {
    manager.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<List<String>> enqueueFiles(int count) async {
    final sources = <UploadSource>[];
    for (var i = 0; i < count; i++) {
      final file = File('${root.path}/file-$i.bin');
      await file.writeAsBytes(List<int>.filled(8, i));
      sources.add(UploadSource(
        path: file.path,
        name: 'file-$i.bin',
        size: 8,
      ));
    }
    return manager.enqueueAll(sources, 'Camera');
  }

  test('pause all holds every waiting transfer and resume all restarts them',
      () async {
    await enqueueFiles(3);

    expect(await manager.pauseAll(), 3);
    expect(
      manager
          .items()
          .every((UploadItem item) => item.state == UploadState.paused),
      isTrue,
    );

    // A second pause is a no-op, not a second state transition.
    expect(await manager.pauseAll(), 0);

    expect(await manager.resumeAll(), 3);
    expect(
      manager
          .items()
          .every((UploadItem item) => item.state == UploadState.queued),
      isTrue,
    );
  });

  test('delete all empties the in-memory queue and the journal', () async {
    await enqueueFiles(4);
    expect(manager.items(), hasLength(4));

    expect(await manager.removeAll(), 4);
    expect(manager.items(), isEmpty);
    expect(manager.pendingCount, 0);

    // A new manager reading the same journal must see nothing either.
    final reloaded = await UploadStore(journal).load();
    expect(reloaded, isEmpty);
  });

  test('folder sources keep only the document URI, not copied bytes', () async {
    const uri = 'content://com.android.providers.downloads.documents/tree/x';
    final id = await manager.enqueue(
      const UploadSource(
        path: uri,
        sourceUri: uri,
        name: 'photo.jpg',
        size: 123,
        relativePath: '2026/photo.jpg',
      ),
      'Camera',
    );

    final item =
        manager.items().singleWhere((UploadItem entry) => entry.id == id);
    expect(item.sourceUri, uri);
    expect(item.localPath, uri);
    expect(item.folder, 'Camera/2026');
    expect(item.temporarySource, isFalse);

    final reloaded = await UploadStore(journal).load();
    expect(reloaded.single.sourceUri, uri);
  });
}
