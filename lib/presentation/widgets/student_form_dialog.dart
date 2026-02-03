import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

/// Styled modal for Add / Edit student (white card, red primary button).
class StudentFormDialog extends ConsumerStatefulWidget {
  const StudentFormDialog({
    super.key,
    required this.isEdit,
    this.student,
    required this.onSaved,
  });

  final bool isEdit;
  final Student? student;
  final VoidCallback onSaved;

  static const List<String> yearOptions = ['Year 1', 'Year 2', 'Year 3', 'Year 4'];
  static const List<String> modeOptions = ['Full-time', 'Hybrid'];
  static const List<String> statusOptions = ['Active', 'Withdrawn', 'Transferred'];

  /// Admission year options: current year - 10 to current year + 1
  static List<String> get admissionYearOptions {
    final now = DateTime.now();
    final currentYear = now.year;
    return List.generate(12, (i) => (currentYear - 10 + i).toString());
  }

  static Future<void> showAdd({
    required BuildContext context,
    required WidgetRef ref,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => StudentFormDialog(
          isEdit: false,
          onSaved: onSaved,
        ),
      ),
    );
  }

  static Future<void> showEdit({
    required BuildContext context,
    required WidgetRef ref,
    required Student student,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => StudentFormDialog(
          isEdit: true,
          student: student,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  ConsumerState<StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends ConsumerState<StudentFormDialog> {
  late final TextEditingController _surnameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _contactInfoController;
  late final TextEditingController _emailController;
  String? _year;
  String? _mode;
  String? _admissionYear;
  String? _status;
  bool _handbook = false;
  bool _mediaRelease = false;
  bool _accidentWaiver = false;

  @override
  void initState() {
    super.initState();
    final s = widget.student;
    _surnameController = TextEditingController(text: s?.surname ?? '');
    _firstNameController = TextEditingController(text: s?.firstName ?? '');
    _contactInfoController = TextEditingController(text: s?.contactInfo ?? '');
    _emailController = TextEditingController(text: s?.email ?? '');
    _year = s?.year;
    _mode = s?.mode;
    _admissionYear = s?.admissionYear;
    _status = s?.status;
    _handbook = s?.handbook ?? false;
    _mediaRelease = s?.mediaRelease ?? false;
    _accidentWaiver = s?.accidentWaiver ?? false;
  }

  @override
  void dispose() {
    _surnameController.dispose();
    _firstNameController.dispose();
    _contactInfoController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: AppColors.charisWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildField('Surname', _surnameController, hint: 'Surname'),
                    const SizedBox(height: 16),
                    _buildField('First Names', _firstNameController, hint: 'First Names'),
                    const SizedBox(height: 16),
                    _buildOptionalDropdown('Year', StudentFormDialog.yearOptions, _year, 'Select Year', (v) => setState(() => _year = v)),
                    const SizedBox(height: 16),
                    _buildOptionalDropdown('Mode', StudentFormDialog.modeOptions, _mode, 'Select Mode', (v) => setState(() => _mode = v)),
                    const SizedBox(height: 16),
                    _buildOptionalDropdown('Admission year', StudentFormDialog.admissionYearOptions, _admissionYear, 'Select admission year', (v) => setState(() => _admissionYear = v)),
                    const SizedBox(height: 16),
                    _buildDropdown('Status', StudentFormDialog.statusOptions, _status, 'Select Status', (v) => setState(() => _status = v)),
                    const SizedBox(height: 16),
                    _buildPhoneField(),
                    const SizedBox(height: 16),
                    _buildEmailField(),
                    const SizedBox(height: 16),
                    _buildCheckboxField('Handbook', _handbook, (v) => setState(() => _handbook = v)),
                    const SizedBox(height: 12),
                    _buildCheckboxField('Media Release', _mediaRelease, (v) => setState(() => _mediaRelease = v)),
                    const SizedBox(height: 12),
                    _buildCheckboxField('Accident Waiver', _accidentWaiver, (v) => setState(() => _accidentWaiver = v)),
                    const SizedBox(height: 24),
                    _buildActions(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEdit ? 'Edit Student' : 'Add New Student',
                  style: const TextStyle(
                    color: AppColors.charisBlack,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isEdit
                      ? 'Update the details below.'
                      : 'Fill in the details below to add a new student record.',
                  style: const TextStyle(
                    color: AppColors.charisMidGray,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: AppColors.charisDarkGray),
            style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint ?? label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryActionRed, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: AppColors.charisWhite,
          ),
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: AppColors.charisBlack, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, List<String> options, String? value, String hint, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryActionRed, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: AppColors.charisWhite,
          ),
          hint: Text(hint, style: const TextStyle(color: AppColors.charisMidGray, fontSize: 14)),
          items: options.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.charisBlack, fontSize: 14),
        ),
      ],
    );
  }

  /// Builds a dropdown with a "Clear" option for optional fields
  Widget _buildOptionalDropdown(String label, List<String> options, String? value, String hint, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryActionRed, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: AppColors.charisWhite,
          ),
          hint: Text(hint, style: const TextStyle(color: AppColors.charisMidGray, fontSize: 14)),
          items: [
            // Add a "Clear" option at the beginning if a value is selected
            if (value != null)
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Clear', style: TextStyle(color: AppColors.charisMidGray, fontStyle: FontStyle.italic)),
              ),
            ...options.map((s) => DropdownMenuItem(value: s, child: Text(s))),
          ],
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.charisBlack, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phone',
          style: TextStyle(
            color: AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _contactInfoController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Phone Number (Optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryActionRed, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: AppColors.charisWhite,
          ),
          style: const TextStyle(color: AppColors.charisBlack, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email',
          style: TextStyle(
            color: AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'Email Address (Optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryActionRed, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: AppColors.charisWhite,
          ),
          style: const TextStyle(color: AppColors.charisBlack, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildCheckboxField(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (v) {
              if (v != null) {
                onChanged(v);
              }
            },
            activeColor: AppColors.primaryActionRed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => onChanged(!value),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.charisBlack,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.charisDarkGray,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryActionRed,
            foregroundColor: AppColors.charisWhite,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(widget.isEdit ? 'Save' : 'Add Student'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final surname = _surnameController.text.trim();
    final firstName = _firstNameController.text.trim();
    if (surname.isEmpty || firstName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Surname and first name are required')),
      );
      return;
    }
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    final contactInfo = _contactInfoController.text.trim();
    final email = _emailController.text.trim();
    final status = _status ?? 'Active';

    try {
      if (widget.isEdit && widget.student != null) {
        await ref.read(studentRepositoryProvider).updateStudent(
              widget.student!.id,
              surname: surname,
              firstName: firstName,
              year: _year,
              mode: _mode,
              admissionYear: _admissionYear,
              status: status,
              contactInfo: contactInfo.isEmpty ? null : contactInfo,
              email: email.isEmpty ? null : email,
              handbook: _handbook, // Always pass boolean values explicitly
              mediaRelease: _mediaRelease,
              accidentWaiver: _accidentWaiver,
              userRole: auth.role,
              userId: auth.user.id,
            );
      } else {
        await ref.read(studentRepositoryProvider).addStudent(
              surname,
              firstName,
              userRole: auth.role,
              userId: auth.user.id,
              year: _year,
              mode: _mode,
              admissionYear: _admissionYear,
              contactInfo: contactInfo.isEmpty ? null : contactInfo,
              email: email.isEmpty ? null : email,
              handbook: _handbook, // Always pass boolean values explicitly
              mediaRelease: _mediaRelease,
              accidentWaiver: _accidentWaiver,
            );
      }
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}
