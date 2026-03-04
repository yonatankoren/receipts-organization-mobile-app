/// Google Sheets service.
/// Appends receipt rows to a configured spreadsheet.
///
/// Idempotency: before appending, checks if receipt_id already exists in the sheet.
/// This prevents duplicate rows on retry.

import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import '../models/receipt.dart';
import '../utils/constants.dart';

class SheetsService {
  static final SheetsService instance = SheetsService._();
  SheetsService._();

  static const String _prefKeySpreadsheetId = 'sheets_spreadsheet_id';
  static const String _prefKeySheetName = 'sheets_sheet_name';

  /// Get configured spreadsheet ID from settings
  Future<String?> getSpreadsheetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeySpreadsheetId);
  }

  /// Set spreadsheet ID in settings
  Future<void> setSpreadsheetId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySpreadsheetId, id);
  }

  /// Get sheet name (tab), defaults to "קבלות"
  Future<String> getSheetName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeySheetName) ?? 'קבלות';
  }

  Future<void> setSheetName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySheetName, name);
  }

  /// Append a receipt row to Google Sheets.
  /// Idempotent: checks for existing receipt_id before appending.
  Future<void> appendReceiptRow(Receipt receipt) async {
    final spreadsheetId = await getSpreadsheetId();
    if (spreadsheetId == null || spreadsheetId.isEmpty) {
      throw Exception('Spreadsheet ID not configured. Set it in Settings.');
    }

    final client = await AuthService.instance.getAuthenticatedClient();
    if (client == null) {
      throw Exception('Not authenticated — cannot write to Sheets');
    }

    try {
      final sheetsApi = sheets.SheetsApi(client);
      final sheetName = await getSheetName();

      // 1. Ensure headers exist (first row)
      await _ensureHeaders(sheetsApi, spreadsheetId, sheetName);

      // 2. Check for duplicate (idempotency)
      final isDuplicate = await _isReceiptAlreadyInSheet(
        sheetsApi, spreadsheetId, sheetName, receipt.id,
      );
      if (isDuplicate) {
        debugPrint('Sheets: receipt ${receipt.id} already exists, skipping');
        return;
      }

      // 3. Append row
      final row = receipt.toSheetsRow();
      final valueRange = sheets.ValueRange()
        ..values = [row.map((v) => v.toString()).toList()];

      await sheetsApi.spreadsheets.values.append(
        valueRange,
        spreadsheetId,
        '$sheetName!A:I',
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );

      debugPrint('Sheets: appended row for receipt ${receipt.id}');
    } finally {
      client.close();
    }
  }

  /// Ensure the header row exists
  Future<void> _ensureHeaders(
    sheets.SheetsApi api,
    String spreadsheetId,
    String sheetName,
  ) async {
    try {
      final response = await api.spreadsheets.values.get(
        spreadsheetId,
        '$sheetName!A1:I1',
      );

      // If first row is empty or doesn't match our headers, write them
      if (response.values == null || response.values!.isEmpty) {
        final headerRange = sheets.ValueRange()
          ..values = [AppConstants.sheetsHeaders];

        await api.spreadsheets.values.update(
          headerRange,
          spreadsheetId,
          '$sheetName!A1:I1',
          valueInputOption: 'RAW',
        );
        debugPrint('Sheets: wrote headers');
      }
    } catch (e) {
      // Sheet might not exist yet — try creating headers anyway
      debugPrint('Sheets: header check error (might be new sheet): $e');
      try {
        final headerRange = sheets.ValueRange()
          ..values = [AppConstants.sheetsHeaders];

        await api.spreadsheets.values.update(
          headerRange,
          spreadsheetId,
          '$sheetName!A1:I1',
          valueInputOption: 'RAW',
        );
      } catch (_) {
        // Ignore — headers will be written on next successful attempt
      }
    }
  }

  /// Check if a receipt ID already exists in column A (idempotency)
  Future<bool> _isReceiptAlreadyInSheet(
    sheets.SheetsApi api,
    String spreadsheetId,
    String sheetName,
    String receiptId,
  ) async {
    try {
      final response = await api.spreadsheets.values.get(
        spreadsheetId,
        '$sheetName!A:A',
      );

      if (response.values == null) return false;

      for (final row in response.values!) {
        if (row.isNotEmpty && row[0].toString() == receiptId) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Sheets: duplicate check error: $e');
      return false; // On error, proceed with append
    }
  }
}

