import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/data/services/sync_folder_watch_coordinator.dart';

void main() {
  group('SyncFolderWatchCoordinator', () {
    test('debounces multiple events into one sync run', () async {
      final controller = StreamController<FileSystemEvent>.broadcast();
      var runs = 0;

      final coordinator = SyncFolderWatchCoordinator(
        onSyncRequested: () async {
          runs++;
        },
        debounceDuration: const Duration(milliseconds: 20),
        watchStreamFactory: (_) => controller.stream,
      );

      coordinator.configure(
        syncFolderPath: r'C:\tmp\sync',
        enabled: true,
        localDeviceId: 'local-1',
      );

      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote.json', false, true),
      );
      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote.json', false, true),
      );
      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote.json', false, true),
      );

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 1);

      await coordinator.dispose();
      await controller.close();
    });

    test('ignores local device file and non-device files', () async {
      final controller = StreamController<FileSystemEvent>.broadcast();
      var runs = 0;

      final coordinator = SyncFolderWatchCoordinator(
        onSyncRequested: () async {
          runs++;
        },
        debounceDuration: const Duration(milliseconds: 20),
        watchStreamFactory: (_) => controller.stream,
      );

      coordinator.configure(
        syncFolderPath: r'C:\tmp\sync',
        enabled: true,
        localDeviceId: 'local-1',
      );

      controller.add(FileSystemModifyEvent(r'C:\tmp\sync\notes.txt', false, true));
      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_local-1.json', false, true),
      );
      controller.add(
        FileSystemModifyEvent(
          r'C:\tmp\sync\device_local-1-DESKTOP-QNOGFOJ.json',
          false,
          true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 0);

      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote-2.json', false, true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 1);

      await coordinator.dispose();
      await controller.close();
    });

    test('does not subscribe when localDeviceId is empty', () async {
      final controller = StreamController<FileSystemEvent>.broadcast();
      var runs = 0;

      final coordinator = SyncFolderWatchCoordinator(
        onSyncRequested: () async {
          runs++;
        },
        debounceDuration: const Duration(milliseconds: 20),
        watchStreamFactory: (_) => controller.stream,
      );

      coordinator.configure(
        syncFolderPath: r'C:\tmp\sync',
        enabled: true,
        localDeviceId: '',
      );

      expect(coordinator.isWatching, isFalse);

      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote.json', false, true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 0);

      await coordinator.dispose();
      await controller.close();
    });

    test('suppresses file events during post-sync cooldown', () async {
      final controller = StreamController<FileSystemEvent>.broadcast();
      var runs = 0;

      final coordinator = SyncFolderWatchCoordinator(
        onSyncRequested: () async {
          runs++;
        },
        debounceDuration: const Duration(milliseconds: 20),
        postSyncCooldown: const Duration(milliseconds: 120),
        watchStreamFactory: (_) => controller.stream,
      );

      coordinator.configure(
        syncFolderPath: r'C:\tmp\sync',
        enabled: true,
        localDeviceId: 'local-1',
      );

      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote.json', false, true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 1);

      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote.json', false, true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 1);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      controller.add(
        FileSystemModifyEvent(r'C:\tmp\sync\device_remote.json', false, true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 2);

      await coordinator.dispose();
      await controller.close();
    });
  });
}
