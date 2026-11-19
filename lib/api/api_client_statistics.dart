part of 'api_client.dart';

/// Raised when the backend reports 404 for statistics endpoints or records.
class ScriptStatisticsNotFoundException implements Exception {
  ScriptStatisticsNotFoundException([this.message = 'Not Found']);

  final String message;

  @override
  String toString() => message;
}

extension ApiClientStatisticsX on ApiClient {
  bool _isNotFoundResult(ApiResult<dynamic> res) {
    if (res.code == 404) {
      return true;
    }
    final err = (res.error ?? '').trim().toLowerCase();
    return err == 'not found' || err.contains('404');
  }

  Future<ScriptStatisticsDateList> getScriptStatisticsDates(
    String scriptName,
  ) async {
    final path = '/stats/${Uri.encodeComponent(scriptName)}/dates';
    final res = await request(
      () => get(
        path,
        options: Options(extra: const {'silent404': true}),
      ),
    );
    if (!res.isSuccess || res.data is! Map) {
      if (_isNotFoundResult(res)) {
        throw ScriptStatisticsNotFoundException(res.error ?? 'Not Found');
      }
      throw Exception(res.error ?? 'Invalid statistics dates response');
    }
    return ScriptStatisticsDateList.fromJson(
      Map<String, dynamic>.from(res.data),
    );
  }

  Future<ScriptStatisticsDay> getScriptStatisticsDay(
    String scriptName,
    String dateKey,
  ) async {
    final path = '/stats/${Uri.encodeComponent(scriptName)}?date=$dateKey';
    final res = await request(
      () => get(
        path,
        options: Options(extra: const {'silent404': true}),
      ),
    );
    if (!res.isSuccess || res.data is! Map) {
      if (_isNotFoundResult(res)) {
        throw ScriptStatisticsNotFoundException(res.error ?? 'Not Found');
      }
      throw Exception(res.error ?? 'Invalid statistics day response');
    }
    return parseScriptStatisticsDayAsync(
      Map<String, dynamic>.from(res.data),
      dateKey: dateKey,
    );
  }

  Uri buildScriptStatisticsSseUri(String scriptName, String dateKey) {
    final addressText = address.trim().replaceAll(RegExp(r'/+$'), '');
    final baseAddress =
        addressText.startsWith('http://') || addressText.startsWith('https://')
            ? addressText
            : 'http://$addressText';
    return Uri.parse(
      '$baseAddress/stats/${Uri.encodeComponent(scriptName)}/stream?date=$dateKey',
    );
  }
}
