/// Form validation utilities
class ValidationUtils {
  ValidationUtils._();

  /// Validate email format
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Validate required field
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validate test score (0-100)
  static String? validateTestScore(String? value) {
    if (value == null || value.isEmpty) {
      return 'Test score is required';
    }
    final score = int.tryParse(value);
    if (score == null) {
      return 'Please enter a valid number';
    }
    if (score < 0 || score > 100) {
      return 'Score must be between 0 and 100';
    }
    return null;
  }

  /// Validate payment amount (positive number)
  static String? validatePaymentAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Payment amount is required';
    }
    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Please enter a valid amount';
    }
    if (amount <= 0) {
      return 'Amount must be greater than 0';
    }
    return null;
  }
}
