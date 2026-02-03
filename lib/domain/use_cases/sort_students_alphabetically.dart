import 'package:charis_student_care/data/database/app_database.dart';

/// Use case: sort student list alphabetically by surname, then first name.
/// Use everywhere student lists are displayed for consistent ordering.
List<Student> sortStudentsAlphabetically(List<Student> students) {
  final list = List<Student>.from(students);
  list.sort((a, b) {
    final surnameCompare = a.surname.compareTo(b.surname);
    if (surnameCompare != 0) return surnameCompare;
    return a.firstName.compareTo(b.firstName);
  });
  return list;
}
