/// Export service — builds ZIP files from selected months' receipts.
///
/// Preserves the same hierarchy as Google Drive:
///   month/category/receipt-files
///
/// Also generates a summary.csv with per-month, per-category aggregations.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../models/receipt.dart';
import 'auth_service.dart';

class ExportService {
  static final ExportService instance = ExportService._();
  ExportService._();

  /// Create an export ZIP containing receipts for the given months.
  ///
  /// [monthKeys] — list of month keys in "YYYY-MM" format.
  /// [userName] — user's display name for the ZIP filename.
  /// [onProgress] — callback for progress messages shown in loading UI.
  ///
  /// Returns the absolute path to the created ZIP file.
  Future<String> createExportZip({
    required List<String> monthKeys,
    required String userName,
    void Function(String)? onProgress,
  }) async {
    final db = DatabaseHelper.instance;
    final archive = Archive();

    // ── 1. Gather receipts for selected months ──
    onProgress?.call('אוסף את הקבלות…');
    final allReceipts = <String, List<Receipt>>{};
    for (final mk in monthKeys) {
      final receipts = await db.getReceiptsByMonth(mk);
      if (receipts.isNotEmpty) {
        allReceipts[mk] = receipts;
      }
    }

    // ── 2. Download files and add to archive ──
    onProgress?.call('מוריד קבצים מ-Drive…');

    // Authenticate once for all Drive downloads
    final client = await AuthService.instance.getAuthenticatedClient();
    drive.DriveApi? driveApi;
    if (client != null) {
      driveApi = drive.DriveApi(client);
    }

    try {
      for (final entry in allReceipts.entries) {
        final monthKey = entry.key;
        final receipts = entry.value;

        for (final receipt in receipts) {
          final category = receipt.category ?? 'אחר';
          final fileName = _buildFileName(receipt);
          final archivePath = '$monthKey/$category/$fileName';

          try {
            Uint8List? fileBytes;

            // Try downloading from Drive first (original quality)
            if (driveApi != null &&
                receipt.driveFileId != null &&
                receipt.driveFileId!.isNotEmpty) {
              fileBytes =
                  await _downloadDriveFile(driveApi, receipt.driveFileId!);
            }

            // Fall back to local file
            if (fileBytes == null) {
              final localPath =
                  (receipt.pdfPath != null && receipt.pdfPath!.isNotEmpty)
                      ? receipt.pdfPath!
                      : receipt.imagePath;
              final localFile = File(localPath);
              if (await localFile.exists()) {
                fileBytes = await localFile.readAsBytes();
              }
            }

            if (fileBytes != null) {
              archive.addFile(
                ArchiveFile(archivePath, fileBytes.length, fileBytes),
              );
            }
          } catch (e) {
            debugPrint('ExportService: failed to add $archivePath: $e');
            // Continue with other receipts — don't let one failure break export
          }
        }
      }
    } finally {
      client?.close();
    }

    // ── 3. Generate summary.csv ──
    onProgress?.call('מכין סיכום חודשי…');
    final csvContent = _generateSummaryCsv(allReceipts);
    // UTF-8 BOM so Excel opens Hebrew correctly
    final csvBytes = Uint8List.fromList(
      [0xEF, 0xBB, 0xBF, ...utf8.encode(csvContent)],
    );
    archive.addFile(ArchiveFile('summary.csv', csvBytes.length, csvBytes));

    // ── 4. Encode ZIP ──
    onProgress?.call('יוצר קובץ ZIP…');
    final zipData = ZipEncoder().encode(archive);

    // ── 5. Write to cache directory ──
    onProgress?.call('מכין את הקובץ לשליחה…');
    final cacheDir = await getTemporaryDirectory();
    final exportsDir = Directory('${cacheDir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }

    final zipFileName = _buildZipFileName(monthKeys, userName);
    final zipFile = File('${exportsDir.path}/$zipFileName');
    await zipFile.writeAsBytes(zipData);

    debugPrint(
      'ExportService: created ZIP at ${zipFile.path} '
      '(${zipData.length} bytes, ${archive.length} files)',
    );
    return zipFile.path;
  }

  // ─── Helpers ──────────────────────────────────────────────────

  /// Download a file from Google Drive by its file ID.
  Future<Uint8List?> _downloadDriveFile(
    drive.DriveApi api,
    String fileId,
  ) async {
    try {
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } catch (e) {
      debugPrint('ExportService: Drive download failed for $fileId: $e');
      return null;
    }
  }

  /// Build a filename for a receipt in the ZIP.
  /// Matches the naming format used in Google Drive.
  String _buildFileName(Receipt receipt) {
    final merchant = receipt.merchantName ?? 'קבלה';
    final shortId = receipt.id.substring(0, 4);
    final isPdf = receipt.pdfPath != null && receipt.pdfPath!.isNotEmpty;
    final ext = isPdf ? 'pdf' : 'jpg';
    // Sanitize merchant name for filesystem safety
    final safeMerchant = merchant.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    return '$safeMerchant ($shortId).$ext';
  }

  /// Build the ZIP filename.
  /// Format: expenses_MM-YY_MM-YY_Firstname_Lastname.zip
  String _buildZipFileName(List<String> monthKeys, String userName) {
    final sorted = List<String>.from(monthKeys)..sort();

    final monthParts = sorted.map((mk) {
      final parts = mk.split('-');
      final year = parts[0].substring(2); // YYYY → YY
      final month = parts[1];
      return '$month-$year';
    }).join('_');

    // Sanitize username for filesystem safety
    final safeName = userName
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(' ', '_');

    return 'expenses_${monthParts}_$safeName.zip';
  }

  /// Generate summary CSV content.
  String _generateSummaryCsv(Map<String, List<Receipt>> receiptsByMonth) {
    final buffer = StringBuffer();
    buffer.writeln('Month,Category,Receipts Count,Total Amount');

    final sortedMonths = receiptsByMonth.keys.toList()..sort();

    for (final monthKey in sortedMonths) {
      final receipts = receiptsByMonth[monthKey]!;

      // Group by category
      final byCategory = <String, List<Receipt>>{};
      for (final r in receipts) {
        final cat = r.category ?? 'אחר';
        byCategory.putIfAbsent(cat, () => []).add(r);
      }

      // Format month as MM/YY
      final parts = monthKey.split('-');
      final displayMonth = '${parts[1]}/${parts[0].substring(2)}';

      final sortedCategories = byCategory.keys.toList()..sort();
      for (final category in sortedCategories) {
        final catReceipts = byCategory[category]!;
        final count = catReceipts.length;
        final total = catReceipts.fold<double>(
          0.0,
          (sum, r) => sum + (r.totalAmount ?? 0.0),
        );
        buffer.writeln(
          '$displayMonth,$category,$count,${total.toStringAsFixed(2)}',
        );
      }
    }

    return buffer.toString();
  }
}
