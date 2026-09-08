#!/usr/bin/env dart
// ignore_for_file: avoid_print
/// Script to clear all test records from the database.
///
/// Usage:
///   dart run scripts/clear_all_tests.dart
///   dart run scripts/clear_all_tests.dart --db-path="C:\path\to\charis_student_care.db"
///
/// With no --db-path, uses the app's default database (Application Support,
/// with a one-time migrate from Documents if needed).
/// WARNING: This is a destructive operation that cannot be undone.

import 'dart:io';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/database/database_file.dart';
import 'package:charis_student_care/data/repositories/test_repository.dart';

Future<void> main(List<String> args) async {
  print('=' * 60);
  print('Clear All Tests Script');
  print('=' * 60);
  print('');

  // Parse optional --db-path=...
  String? dbPath;
  for (final arg in args) {
    if (arg.startsWith('--db-path=')) {
      dbPath = arg.substring('--db-path='.length).trim();
      if (dbPath.startsWith('"') && dbPath.endsWith('"')) {
        dbPath = dbPath.substring(1, dbPath.length - 1);
      } else if (dbPath.startsWith("'") && dbPath.endsWith("'")) {
        dbPath = dbPath.substring(1, dbPath.length - 1);
      }
      break;
    }
  }

  AppDatabase database;
  String pathUsed;
  if (dbPath != null && dbPath.isNotEmpty) {
    final file = File(dbPath);
    if (!file.existsSync()) {
      print('Error: Database file not found: $dbPath');
      exit(1);
    }
    database = AppDatabase.fromFile(file);
    pathUsed = file.absolute.path;
  } else {
    final file = await DatabaseFile.resolveLiveFile();
    pathUsed = file.absolute.path;
    database = AppDatabase.fromFile(file);
  }
  print('Using database: $pathUsed');
  print('');

  // Confirm before proceeding
  print('WARNING: This will permanently delete ALL test records from the database.');
  print('This action cannot be undone.\n');
  stdout.write('Are you sure you want to continue? (yes/no): ');

  final confirmation = stdin.readLineSync()?.toLowerCase().trim();
  if (confirmation != 'yes') {
    print('\nOperation cancelled.');
    exit(0);
  }

  print('\nChecking test count...');

  try {
    // Get count before deletion
    final allTests = await database.select(database.tests).get();
    final totalCount = allTests.length;

    if (totalCount == 0) {
      print('\nNo test records found. Tests table is already empty.');
      await database.close();
      exit(0);
    }

    print('Found $totalCount test record(s) to delete.');
    print('Deleting all test records...');

    final repository = TestRepository(database);
    await repository.clearAllTests(
      userRole: UserRole.adminLevel01,
      userId: 'script-clear-all-tests',
    );

    print('Successfully deleted all test records.');
    print('Operation logged to change_sets table.');
    print('\nTests table is now clean.');
  } catch (e, stackTrace) {
    print('\nError: $e');
    print('\nStack trace:');
    print(stackTrace);
    exit(1);
  } finally {
    await database.close();
    print('\nDatabase connection closed.');
  }
}
