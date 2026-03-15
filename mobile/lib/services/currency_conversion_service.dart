import 'dart:convert';

import 'package:http/http.dart' as http;

class CurrencyConversionService {
  static final CurrencyConversionService instance =
      CurrencyConversionService._();

  CurrencyConversionService._();

  static const String _baseUrl = 'https://api.frankfurter.dev/v1';
  static const Set<String> _supportedCurrencies = {'ILS', 'USD', 'EUR'};

  final Map<String, _WeeklyRateCacheEntry> _previewRateCache = {};

  Future<double?> getEstimatedIlsPreview({
    required double amount,
    required String fromCurrency,
  }) async {
    final normalizedFrom = _normalizeCurrency(fromCurrency);
    if (amount.isNaN || amount.isInfinite) return null;
    if (normalizedFrom.isEmpty) return null;
    if (normalizedFrom == 'ILS') return _roundMoney(amount);

    final rateEntry = await _getOrFetchWeeklyPreviewRate(
      fromCurrency: normalizedFrom,
      toCurrency: 'ILS',
    );
    return _roundMoney(amount * rateEntry.rate);
  }

  Future<FinalIlsConversion> getFinalIlsConversion({
    required double amount,
    required String fromCurrency,
    required String receiptDate,
  }) async {
    final normalizedFrom = _normalizeCurrency(fromCurrency);
    if (amount.isNaN || amount.isInfinite) {
      throw Exception('Invalid amount for conversion');
    }
    if (normalizedFrom.isEmpty) {
      throw Exception('Currency is required for conversion');
    }
    if (normalizedFrom == 'ILS') {
      return FinalIlsConversion(
        convertedAmountIls: _roundMoney(amount),
        rateUsed: 1,
        rateDate: receiptDate,
      );
    }

    final uri = Uri.parse(
      '$_baseUrl/$receiptDate?base=$normalizedFrom&symbols=ILS',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch exchange rate');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = data['rates'] as Map<String, dynamic>?;
    final rateRaw = rates?['ILS'];
    final rate = _asDouble(rateRaw);
    if (rate == null || rate <= 0) {
      throw Exception('Exchange rate unavailable for receipt date');
    }

    final rateDate = (data['date'] as String?)?.trim();
    return FinalIlsConversion(
      convertedAmountIls: _roundMoney(amount * rate),
      rateUsed: rate,
      rateDate: (rateDate != null && rateDate.isNotEmpty) ? rateDate : receiptDate,
    );
  }

  Future<_WeeklyRateCacheEntry> _getOrFetchWeeklyPreviewRate({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final now = DateTime.now();
    final weekStart = _startOfWeekSunday(now);
    final cacheKey = '${fromCurrency}_${toCurrency}_${_formatIsoDate(weekStart)}';
    final cached = _previewRateCache[cacheKey];
    if (cached != null) return cached;

    final uri = Uri.parse(
      '$_baseUrl/latest?base=$fromCurrency&symbols=$toCurrency',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch preview exchange rate');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = data['rates'] as Map<String, dynamic>?;
    final rateRaw = rates?[toCurrency];
    final rate = _asDouble(rateRaw);
    if (rate == null || rate <= 0) {
      throw Exception('Preview exchange rate unavailable');
    }

    final rateDate = (data['date'] as String?)?.trim();
    final entry = _WeeklyRateCacheEntry(
      rate: rate,
      fetchedAt: now,
      sourceDate: (rateDate != null && rateDate.isNotEmpty)
          ? rateDate
          : _formatIsoDate(now),
    );
    _previewRateCache[cacheKey] = entry;
    return entry;
  }

  DateTime _startOfWeekSunday(DateTime date) {
    final localDate = DateTime(date.year, date.month, date.day);
    final daysFromSunday = localDate.weekday % 7;
    return localDate.subtract(Duration(days: daysFromSunday));
  }

  String _formatIsoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _normalizeCurrency(String raw) {
    final value = raw.trim().toUpperCase();
    return _supportedCurrencies.contains(value) ? value : '';
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}

class FinalIlsConversion {
  final double convertedAmountIls;
  final double rateUsed;
  final String rateDate;

  const FinalIlsConversion({
    required this.convertedAmountIls,
    required this.rateUsed,
    required this.rateDate,
  });
}

class _WeeklyRateCacheEntry {
  final double rate;
  final DateTime fetchedAt;
  final String sourceDate;

  const _WeeklyRateCacheEntry({
    required this.rate,
    required this.fetchedAt,
    required this.sourceDate,
  });
}
