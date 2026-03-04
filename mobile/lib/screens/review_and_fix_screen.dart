/// Review & Fix Screen — shows extracted receipt fields for review/editing.
///
/// UX requirements:
///   - Large, easy-to-edit fields
///   - One-tap save
///   - Confidence indicators per field
///   - Receipt image preview
///   - If still processing, show loading state
///   - Category dropdown
///   - Must never block with complicated forms

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/receipt.dart';
import '../providers/app_state.dart';
import '../utils/constants.dart';

class ReviewAndFixScreen extends StatefulWidget {
  final String receiptId;

  const ReviewAndFixScreen({super.key, required this.receiptId});

  @override
  State<ReviewAndFixScreen> createState() => _ReviewAndFixScreenState();
}

class _ReviewAndFixScreenState extends State<ReviewAndFixScreen> {
  Receipt? _receipt;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers for editable fields
  final _merchantController = TextEditingController();
  final _dateController = TextEditingController();
  final _amountController = TextEditingController();
  final _currencyController = TextEditingController();
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _dateController.dispose();
    _amountController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _loadReceipt() async {
    final appState = context.read<AppState>();
    final receipt = await appState.refreshReceipt(widget.receiptId);

    if (receipt != null && mounted) {
      _populateFields(receipt);
    }

    setState(() {
      _receipt = receipt;
      _isLoading = false;
    });

    // If not yet processed, poll for updates
    if (receipt != null && receipt.rawOcrText == null) {
      _pollForProcessing();
    }
  }

  void _populateFields(Receipt receipt) {
    _merchantController.text = receipt.merchantName ?? '';
    _dateController.text = receipt.receiptDate ?? '';
    _amountController.text =
        receipt.totalAmount?.toStringAsFixed(2) ?? '';
    _currencyController.text = receipt.currency;
    _selectedCategory = receipt.category;
  }

  /// Poll every 2 seconds until processing is complete
  Future<void> _pollForProcessing() async {
    for (int i = 0; i < 30; i++) {
      // Max 60 seconds
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final appState = context.read<AppState>();
      final updated = await appState.refreshReceipt(widget.receiptId);

      if (updated != null && updated.rawOcrText != null) {
        setState(() => _receipt = updated);
        _populateFields(updated);
        return;
      }
    }
  }

  Future<void> _save() async {
    if (_receipt == null || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final updated = _receipt!.copyWith(
        merchantName: _merchantController.text.isNotEmpty
            ? _merchantController.text
            : null,
        receiptDate: _dateController.text.isNotEmpty
            ? _dateController.text
            : null,
        totalAmount: double.tryParse(_amountController.text),
        currency: _currencyController.text.isNotEmpty
            ? _currencyController.text
            : 'ILS',
        category: _selectedCategory,
        status: ReceiptStatus.reviewed,
      );

      await context.read<AppState>().saveReview(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הקבלה נשמרה בהצלחה ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה בשמירה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dateController.text) ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      locale: const Locale('he', 'IL'),
    );
    if (picked != null) {
      _dateController.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Color _confidenceColor(double? confidence) {
    if (confidence == null) return Colors.grey;
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('סקירת קבלה'),
        actions: [
          if (_receipt != null)
            IconButton(
              icon: const Icon(Icons.image),
              onPressed: _showImagePreview,
              tooltip: 'הצג תמונה',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _receipt == null
              ? const Center(child: Text('הקבלה לא נמצאה'))
              : _buildForm(theme),
      bottomNavigationBar: _receipt != null ? _buildSaveBar(theme) : null,
    );
  }

  Widget _buildForm(ThemeData theme) {
    final isProcessing = _receipt!.rawOcrText == null;
    final confidences = _receipt!.fieldConfidences ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Processing indicator
          if (isProcessing)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'מעבד את הקבלה... תוכל לערוך ידנית או לחכות לתוצאות',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Overall confidence
          if (_receipt!.overallConfidence != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _confidenceColor(_receipt!.overallConfidence).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _receipt!.overallConfidence! >= 0.8
                        ? Icons.check_circle
                        : Icons.info_outline,
                    color: _confidenceColor(_receipt!.overallConfidence),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ביטחון כללי: ${(_receipt!.overallConfidence! * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _confidenceColor(_receipt!.overallConfidence),
                    ),
                  ),
                ],
              ),
            ),

          // Receipt image thumbnail
          GestureDetector(
            onTap: _showImagePreview,
            child: Container(
              height: 120,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade100,
              ),
              clipBehavior: Clip.antiAlias,
              child: File(_receipt!.imagePath).existsSync()
                  ? Image.file(
                      File(_receipt!.imagePath),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                  : const Center(
                      child: Icon(Icons.image_not_supported, size: 48),
                    ),
            ),
          ),

          // Merchant Name
          _buildField(
            label: 'שם עסק',
            controller: _merchantController,
            icon: Icons.store,
            confidence: confidences['merchant_name'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // Receipt Date
          _buildField(
            label: 'תאריך קבלה',
            controller: _dateController,
            icon: Icons.calendar_today,
            confidence: confidences['receipt_date'],
            suffix: IconButton(
              icon: const Icon(Icons.edit_calendar),
              onPressed: _pickDate,
            ),
            keyboardType: TextInputType.datetime,
            hint: 'YYYY-MM-DD',
          ),
          const SizedBox(height: 16),

          // Total Amount + Currency (side by side)
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildField(
                  label: 'סכום',
                  controller: _amountController,
                  icon: Icons.payments,
                  confidence: confidences['total_amount'],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  label: 'מטבע',
                  controller: _currencyController,
                  icon: Icons.currency_exchange,
                  confidence: confidences['currency'],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category dropdown
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'קטגוריה',
              prefixIcon: const Icon(Icons.category),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedCategory,
                isExpanded: true,
                hint: const Text('בחר קטגוריה'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('ללא'),
                  ),
                  ...AppConstants.categories.map(
                    (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                  ),
                ],
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status badge
          _buildStatusBadge(),
          const SizedBox(height: 80), // Space for bottom bar
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    double? confidence,
    Widget? suffix,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction ?? TextInputAction.next,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffix ??
            (confidence != null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _confidenceColor(confidence),
                      ),
                    ),
                  )
                : null),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      style: const TextStyle(fontSize: 18),
    );
  }

  Widget _buildStatusBadge() {
    final status = _receipt!.status;
    final (String label, Color color, IconData icon) = switch (status) {
      ReceiptStatus.captured => ('צולם', Colors.grey, Icons.camera_alt),
      ReceiptStatus.processing => ('מעבד', Colors.blue, Icons.sync),
      ReceiptStatus.reviewed => ('נבדק', Colors.orange, Icons.check),
      ReceiptStatus.synced => ('מסונכרן', Colors.green, Icons.cloud_done),
      ReceiptStatus.error => ('שגיאה', Colors.red, Icons.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            'סטטוס: $label',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            'ID: ${_receipt!.id.substring(0, 8)}…',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check, size: 24),
            label: Text(
              _isSaving ? 'שומר...' : 'שמור קבלה',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showImagePreview() {
    if (_receipt == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.file(File(_receipt!.imagePath)),
        ),
      ),
    );
  }
}

