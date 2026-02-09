#!/usr/bin/env dart
/// Script to clear all test records from the database.
/// 
/// Usage:
///   dart run scripts/clear_all_tests.dart
/// 
/// This script will:
/// 1. Connect to the application database
/// 2. Delete all test records
/// 3. Log the operation to change_sets table
/// 
/// WARNING: This is a destructive operation that cannot be undone.

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/test_repository.dart';

Future<void> main() async {
  print('=' * 60);
  print('Clear All Tests Script');
  print('=' * 60);
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
  
  print('\nConnecting to database...');
  
  AppDatabase? database;
  try {
    // Initialize database
    database = AppDatabase();
    
    // Get count before deletion
    final countResult = await (database.selectOnly(database.tests)
          ..addColumns([database.tests.id.count()]))
        .getSingle();
    final totalCount = countResult.read(database.tests.id.count()) ?? 0;
    
    if (totalCount == 0) {
      print('\nNo test records found. Database is already empty.');
      await database.close();
      exit(0);
    }
    
    print('Found $totalCount test record(s) to delete.');
    print('\nDeleting all test records...');
    
    // Create repository and clear all tests
    final repository = TestRepository(database);
    await repository.clearAllTests(
      userRole: UserRole.adminLevel01, // Use admin role for script
      userId: 'script-clear-all-tests', // Script identifier
    );
    
    print('✓ Successfully deleted all test records.');
    print('✓ Operation logged to change_sets table.');
    print('\nDatabase cleared successfully!');
    
  } catch (e, stackTrace) {
    print('\n✗ Error occurred: $e');
    print('\nStack trace:');
    print(stackTrace);
    exit(1);
  } finally {
    if (database != null) {
      await database.close();
      print('\nDatabase connection closed.');
    }
  }
}
