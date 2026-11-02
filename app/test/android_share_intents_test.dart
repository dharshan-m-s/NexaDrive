import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/services/android_share_intents.dart';

void main() {
  group('Android shared-file metadata', () {
    test('preserves the provider URI and original media metadata', () {
      final file = AndroidSharedFile.fromMap({
        'uri': 'content://media/external/images/media/42',
        'name': 'Vacation.jpg',
        'mimeType': 'image/jpeg',
        'size': 4096,
        'localPath': '/data/user/0/io.nexadrive.app/files/shared-imports/1.jpg',
      });

      expect(file.uri, 'content://media/external/images/media/42');
      expect(file.name, 'Vacation.jpg');
      expect(file.mimeType, 'image/jpeg');
      expect(file.size, 4096);
      expect(file.localPath, contains('shared-imports'));
      expect(file.stageError, isNull);
    });

    test('keeps an unavailable size distinguishable from an empty file', () {
      final file = AndroidSharedFile.fromMap({
        'uri': 'content://provider/document/1',
        'name': 'Document.bin',
      });

      expect(file.size, -1);
    });

    test('retains staging failures so a received item can be retried', () {
      final file = AndroidSharedFile.fromMap({
        'uri': 'content://provider/document/2',
        'name': 'Private.docx',
        'stageError': 'Permission was revoked',
      });

      expect(file.localPath, isNull);
      expect(file.stageError, 'Permission was revoked');
      expect(file.withStageError('Retry failed').stageError, 'Retry failed');
    });

    test('maps incoming metadata into the native staging request', () {
      const file = AndroidSharedFile(
        uri: 'content://provider/document/3',
        name: 'A.pdf',
        mimeType: 'application/pdf',
        size: -1,
      );

      expect(file.toMap(), {
        'uri': 'content://provider/document/3',
        'name': 'A.pdf',
        'mimeType': 'application/pdf',
        'size': -1,
      });
    });
  });
}
