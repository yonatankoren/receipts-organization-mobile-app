/// App-wide constants and configuration defaults.

class AppConstants {
  AppConstants._();

  // --- Default backend URL (override in Settings) ---
  static const String defaultBackendUrl = 'http://10.0.2.2:8080'; // Android emulator → host

  // --- Google Drive folder structure ---
  static const String driveFolderRoot = 'Receipts';
  // Subfolders created as: Receipts/YYYY-MM/

  // --- Google Sheets ---
  static const List<String> sheetsHeaders = [
    'מזהה קבלה',
    'תאריך צילום',
    'שם עסק',
    'תאריך קבלה',
    'סכום',
    'מטבע',
    'קטגוריה',
    'קישור לדרייב',
    'ביטחון כללי',
  ];

  // --- Job queue ---
  static const int maxJobRetries = 5;
  static const Duration initialRetryDelay = Duration(seconds: 5);
  static const double retryBackoffMultiplier = 2.0;

  // --- Categories (Hebrew) ---
  static const List<String> categories = [
    'מזון',
    'מסעדות',
    'תחבורה',
    'דלק',
    'קניות',
    'בריאות',
    'חשבונות',
    'בילויים',
    'אחר',
  ];

  // --- Google OAuth Scopes ---
  static const List<String> googleScopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/spreadsheets',
  ];

  // --- Currency default ---
  static const String defaultCurrency = 'ILS';
  static const String defaultLocale = 'he-IL';
  static const String defaultTimezone = 'Asia/Jerusalem';
}

