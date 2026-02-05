/// Sync configuration constants
class SyncConstants {
  SyncConstants._();

  // OneDrive folder path
  static const String onedriveFolderPath = 'CharisStudentCare/Sync/';
  static const String changeSetsFileName = 'change_sets.json';

  // Change-set operation types
  static const String operationInsert = 'INSERT';
  static const String operationUpdate = 'UPDATE';
  static const String operationStatusChange = 'STATUS_CHANGE';
  static const String operationDelete = 'DELETE';

  // Critical fields that require manual conflict resolution
  static const List<String> criticalFields = ['payments', 'status'];
}
