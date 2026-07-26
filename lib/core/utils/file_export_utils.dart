/// User-facing messages for report/file export save failures.
class FileExportUtils {
  FileExportUtils._();

  /// Maps OS / IO errors to a short explanation plus what to try next.
  ///
  /// [itemLabel] is used in the first sentence (e.g. `report`, `template`).
  static String userFacingSaveError(
    Object error, {
    String itemLabel = 'file',
  }) {
    final text = error.toString().toLowerCase();

    if (_isFileInUse(text)) {
      return 'Couldn’t save the $itemLabel because that file is open in '
          'another program.\n\n'
          'Close the PDF or Excel file (or choose a different filename in the '
          'save dialog), then try again.';
    }

    if (_isPermissionDenied(text)) {
      return 'Couldn’t save the $itemLabel. You may not have permission to '
          'write to that folder.\n\n'
          'Try saving to Downloads or another folder you own.';
    }

    if (text.contains('no space') ||
        text.contains('not enough space') ||
        text.contains('disk full') ||
        text.contains('errno = 28')) {
      return 'Couldn’t save the $itemLabel. The disk may be full.\n\n'
          'Free some space and try again.';
    }

    if (text.contains('pathnotfound') ||
        text.contains('no such file') ||
        text.contains('cannot find the path') ||
        text.contains('errno = 2')) {
      return 'Couldn’t save the $itemLabel. That folder could not be found.\n\n'
          'Pick a different save location and try again.';
    }

    if (text.contains('pathaccessexception') ||
        text.contains('filesystemexception')) {
      return 'Couldn’t save the $itemLabel. The file or folder could not be '
          'accessed.\n\n'
          'Close the file if it is open, pick a different filename or folder, '
          'then try again.';
    }

    return 'Couldn’t save the $itemLabel.\n\n'
        'Check the save location and try again. If the problem continues, '
        'choose a new filename or folder.';
  }

  static bool _isFileInUse(String text) {
    return text.contains('errno = 32') ||
        text.contains('being used by another process') ||
        text.contains('cannot access the file because it is being used') ||
        text.contains('resource busy') ||
        text.contains('file is locked') ||
        text.contains('sharing violation') ||
        text.contains('text file busy');
  }

  static bool _isPermissionDenied(String text) {
    return text.contains('permission') ||
        text.contains('access is denied') ||
        text.contains('errno = 5') ||
        text.contains('operation not permitted') ||
        text.contains('errno = 13');
  }
}
