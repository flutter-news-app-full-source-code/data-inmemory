import 'dart:async';
import 'dart:math';

import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_shared/ht_shared.dart';
import 'package:logging/logging.dart';

/// {@template ht_data_inmemory}
/// An in-memory implementation of [HtDataClient] for testing or local
/// development.
///
/// This client simulates a remote data source by storing data in memory.
/// It supports CRUD operations, querying, pagination, and user scoping.
///
/// **ID Management:** Relies on the provided `getId` function to extract
/// unique IDs from items. It does not generate IDs.
///
/// **Querying (`readAllByQuery`):**
/// - Matches against the JSON representation of items.
/// - **Nested Properties:** Supports dot-notation (e.g., `'category.id'`).
/// - **`_in` Suffix (Case-Insensitive):** For keys like `'category.id_in'`,
///   the query value is a comma-separated string. Checks if the item's
///   field value (lowercased string) is in the list of query values
///   (also lowercased).
/// - **`_contains` Suffix (Case-Insensitive):** For keys like
///   `'title_contains'`, performs a case-insensitive substring check.
///   If multiple `_contains` keys are provided (e.g. from a `q` param
///   searching multiple fields), they are ORed.
/// - **Exact Match:** For other keys, compares the item's field value
///   (as a string) with the query value (string).
/// - **Logic:** Non-`_contains` filters are ANDed. The result of this is
///   then ANDed with the result of ORing all `_contains` filters.
/// {@endtemplate}
class HtDataInMemory<T> implements HtDataClient<T> {
  /// {@macro ht_data_inmemory}
  HtDataInMemory({
    required ToJson<T> toJson,
    required String Function(T item) getId,
    List<T>? initialData,
    Logger? logger,
  })  : _toJson = toJson,
        _getId = getId,
        _logger = logger ?? Logger('HtDataInMemory<$T>') {
    // Initialize global storage once
    _userScopedStorage.putIfAbsent(_globalDataKey, () => <String, T>{});
    _userScopedJsonStorage.putIfAbsent(
      _globalDataKey,
      () => <String, Map<String, dynamic>>{},
    );

    if (initialData != null) {
      for (final item in initialData) {
        final id = _getId(item);
        if (_userScopedStorage[_globalDataKey]!.containsKey(id)) {
          throw ArgumentError('Duplicate ID "$id" found in initialData.');
        }
        _userScopedStorage[_globalDataKey]![id] = item;
        _userScopedJsonStorage[_globalDataKey]![id] = _toJson(item);
      }
    }
  }

  final ToJson<T> _toJson;
  final String Function(T item) _getId;
  final Logger _logger;

  static const String _globalDataKey = '__global_data__';

  // Stores original items, keyed by userId then itemId
  final Map<String, Map<String, T>> _userScopedStorage = {};
  // Stores JSON representations for querying, keyed by userId then itemId
  final Map<String, Map<String, Map<String, dynamic>>> _userScopedJsonStorage =
      {};

  Map<String, T> _getStorageForUser(String? userId) {
    final key = userId ?? _globalDataKey;
    return _userScopedStorage.putIfAbsent(key, () => <String, T>{});
  }

  Map<String, Map<String, dynamic>> _getJsonStorageForUser(String? userId) {
    final key = userId ?? _globalDataKey;
    return _userScopedJsonStorage.putIfAbsent(
      key,
      () => <String, Map<String, dynamic>>{},
    );
  }

  @override
  Future<SuccessApiResponse<T>> create({
    required T item,
    String? userId,
  }) async {
    final id = _getId(item);
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);
    final scope = userId ?? 'global';
    _logger.fine('Create: id="$id", scope="$scope"');

    if (userStorage.containsKey(id)) {
      _logger.warning(
        'Create FAILED: Item with ID "$id" already exists for scope "$scope".',
      );
      throw BadRequestException(
        'Item with ID "$id" already exists for user "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);
    _logger.info(
      'Create SUCCESS: id="$id" added to scope "$scope". Total items: ${userStorage.length}',
    );
    return SuccessApiResponse(
      data: item,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<SuccessApiResponse<T>> read({
    required String id,
    String? userId,
  }) async {
    final userStorage = _getStorageForUser(userId);
    final scope = userId ?? 'global';
    _logger.fine('Read: id="$id", scope="$scope"');

    final item = userStorage[id];

    if (item == null) {
      _logger.warning('Read FAILED: id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for user "$scope".',
      );
    }
    _logger.info('Read SUCCESS: id="$id" FOUND for scope "$scope".');
    return SuccessApiResponse(
      data: item,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAll({
    String? userId,
    Map<String, dynamic>? filter,
    PaginationOptions? pagination,
    List<SortOption>? sort,
  }) async {
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);
    var allItems = userStorage.values.toList();

    // 1. Apply filtering if a filter is provided
    if (filter != null && filter.isNotEmpty) {
      final allJsonItems = userJsonStorage.values.toList();
      final matchedJsonItems = allJsonItems.where((jsonItem) {
        return _matchesFilter(jsonItem, filter);
      }).toList();
      // Get the original items from the matched JSON items
      final matchedIds =
          matchedJsonItems.map((json) => json['id'] as String).toSet();
      allItems =
          allItems.where((item) => matchedIds.contains(_getId(item))).toList();
    }

    // 2. Apply sorting if sort options are provided
    if (sort != null && sort.isNotEmpty) {
      _sortItems(allItems, sort);
    }

    final paginatedResponse = _createPaginatedResponse(
      allItems,
      pagination?.cursor,
      pagination?.limit,
    );
    return SuccessApiResponse(
      data: paginatedResponse,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Checks if a given [jsonItem] matches all conditions in the [filter].
  bool _matchesFilter(
    Map<String, dynamic> jsonItem,
    Map<String, dynamic> filter,
  ) {
    for (final entry in filter.entries) {
      final key = entry.key;
      final queryValue = entry.value;
      final itemValue = _getNestedValue(jsonItem, key);

      if (queryValue is Map<String, dynamic>) {
        // Handle operators like $in, $gte, etc.
        if (!_evaluateOperator(itemValue, queryValue)) {
          return false; // This condition failed
        }
      } else {
        // Simple exact match
        if (itemValue?.toString() != queryValue?.toString()) {
          return false; // This condition failed
        }
      }
    }
    return true; // All conditions passed
  }

  /// Evaluates a single operator condition (e.g., {'$in': [...]}).
  bool _evaluateOperator(dynamic itemValue, Map<String, dynamic> operatorMap) {
    for (final opEntry in operatorMap.entries) {
      final operator = opEntry.key;
      final operatorValue = opEntry.value;

      switch (operator) {
        case r'$in':
          if (operatorValue is! List) return false;
          if (itemValue == null) return false;
          final lowercasedList =
              operatorValue.map((e) => e.toString().toLowerCase()).toList();
          return lowercasedList.contains(itemValue.toString().toLowerCase());
        case r'$nin': // not in
          if (operatorValue is! List) return false;
          if (itemValue == null) return true;
          final lowercasedList =
              operatorValue.map((e) => e.toString().toLowerCase()).toList();
          return !lowercasedList.contains(itemValue.toString().toLowerCase());
        case r'$ne': // not equal
          return itemValue?.toString() != operatorValue?.toString();
        case r'$gte' || r'$gt' || r'$lte' || r'$lt':
          if (itemValue == null) return false;
          if (itemValue is Comparable && operatorValue is Comparable) {
            final cmp = itemValue.compareTo(operatorValue);
            return (operator == r'$gte' && cmp >= 0) ||
                (operator == r'$gt' && cmp > 0) ||
                (operator == r'$lte' && cmp <= 0) ||
                (operator == r'$lt' && cmp < 0);
          }
          return false; // Cannot compare non-comparable types
      }
    }
    return true; // Default to true if no known operators are found
  }

  dynamic _getNestedValue(Map<String, dynamic> item, String dotPath) {
    if (dotPath.isEmpty) return null;
    final parts = dotPath.split('.');
    dynamic currentValue = item;
    for (final part in parts) {
      if (currentValue is Map<String, dynamic> &&
          currentValue.containsKey(part)) {
        currentValue = currentValue[part];
      } else {
        return null; // Path not found or intermediate value is not a map
      }
    }
    return currentValue;
  }

  void _sortItems(List<T> items, List<SortOption> sortOptions) {
    items.sort((a, b) {
      for (final option in sortOptions) {
        final jsonA = _toJson(a);
        final jsonB = _toJson(b);

        final valueA = _getNestedValue(jsonA, option.field);
        final valueB = _getNestedValue(jsonB, option.field);

        // Handle nulls: items with null values for the sort key go last.
        if (valueA == null && valueB == null) continue; // try next sort option
        if (valueA == null) return 1; // a is greater (put at end)
        if (valueB == null) return -1; // b is greater (put at end)

        int compareResult;
        if (valueA is Comparable && valueB is Comparable) {
          compareResult = valueA.compareTo(valueB);
        } else {
          compareResult = valueA.toString().toLowerCase().compareTo(
                valueB.toString().toLowerCase(),
              );
        }

        if (compareResult != 0) {
          return option.order == SortOrder.asc ? compareResult : -compareResult;
        }
      }
      return 0; // all sort options resulted in equality
    });
  }

  PaginatedResponse<T> _createPaginatedResponse(
    List<T> allMatchingItems,
    String? startAfterId,
    int? limit,
  ) {
    var startIndex = 0;
    if (startAfterId != null) {
      final index =
          allMatchingItems.indexWhere((item) => _getId(item) == startAfterId);
      if (index != -1) {
        startIndex = index + 1;
      } else {
        return const PaginatedResponse(items: [], cursor: null, hasMore: false);
      }
    }

    if (startIndex >= allMatchingItems.length) {
      return const PaginatedResponse(items: [], cursor: null, hasMore: false);
    }

    final actualLimit = limit ?? allMatchingItems.length;
    final count = min(actualLimit, allMatchingItems.length - startIndex);
    final endIndex = startIndex + count;
    final pageItems = allMatchingItems.sublist(startIndex, endIndex);

    final hasMore = endIndex < allMatchingItems.length;
    final cursor =
        (pageItems.isNotEmpty && hasMore) ? _getId(pageItems.last) : null;

    return PaginatedResponse(
      items: pageItems,
      cursor: cursor,
      hasMore: hasMore,
    );
  }

  @override
  Future<SuccessApiResponse<T>> update({
    required String id,
    required T item,
    String? userId,
  }) async {
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);
    final scope = userId ?? 'global';
    _logger.fine('Update: id="$id", scope="$scope"');

    if (!userStorage.containsKey(id)) {
      _logger.warning('Update FAILED: id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for update for user "$scope".',
      );
    }

    final incomingId = _getId(item);
    if (incomingId != id) {
      _logger.warning('Update FAILED: ID mismatch: incoming '
          '"$incomingId", path "$id" for scope "$scope".');
      throw BadRequestException(
        'Item ID ("$incomingId") does not match path ID ("$id") for "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);
    _logger.info('Update SUCCESS: id="$id" updated for scope "$scope".');
    return SuccessApiResponse(
      data: item,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> delete({
    required String id,
    String? userId,
  }) async {
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);
    final scope = userId ?? 'global';
    _logger.fine('Delete: id="$id", scope="$scope"');

    if (!userStorage.containsKey(id)) {
      _logger.warning('Delete FAILED: id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for deletion for user "$scope".',
      );
    }
    userStorage.remove(id);
    userJsonStorage.remove(id);
    _logger.info('Delete SUCCESS: id="$id" deleted for scope "$scope". '
        'Total items: ${userStorage.length}');
  }

  @override
  Future<SuccessApiResponse<int>> count({
    String? userId,
    Map<String, dynamic>? filter,
  }) async {
    final userJsonStorage = _getJsonStorageForUser(userId);
    var allItems = userJsonStorage.values.toList();

    if (filter != null && filter.isNotEmpty) {
      allItems = allItems.where((item) => _matchesFilter(item, filter)).toList();
    }

    return SuccessApiResponse(
      data: allItems.length,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<SuccessApiResponse<List<Map<String, dynamic>>>> aggregate({
    required List<Map<String, dynamic>> pipeline,
    String? userId,
  }) async {
    final userJsonStorage = _getJsonStorageForUser(userId);
    var results = userJsonStorage.values.toList();

    for (final stage in pipeline) {
      final stageName = stage.keys.first;
      final stageSpec = stage[stageName] as Object;

      switch (stageName) {
        case r'$match':
          results = _processMatchStage(results, stageSpec as Map<String, dynamic>);
        case r'$group':
          results = _processGroupStage(results, stageSpec as Map<String, dynamic>);
        case r'$sort':
          results = _processSortStage(results, stageSpec as Map<String, dynamic>);
        case r'$limit':
          results = _processLimitStage(results, stageSpec as int);
        default:
          _logger.warning('Unsupported aggregation stage: $stageName');
      }
    }

    return SuccessApiResponse(
      data: results,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
  }

  List<Map<String, dynamic>> _processMatchStage(
    List<Map<String, dynamic>> input,
    Map<String, dynamic> filter,
  ) {
    return input.where((item) => _matchesFilter(item, filter)).toList();
  }

  List<Map<String, dynamic>> _processGroupStage(
    List<Map<String, dynamic>> input,
    Map<String, dynamic> groupSpec,
  ) {
    final idExpression = groupSpec['_id'] as String?;
    if (idExpression == null) return [];

    final groupedResults = <dynamic, Map<String, dynamic>>{};

    for (final item in input) {
      // Remove '$' prefix from field path
      final idValue = _getNestedValue(item, idExpression.substring(1));
      final group = groupedResults.putIfAbsent(
        idValue,
        () => {'_id': idValue},
      );

      // Process accumulators
      for (final entry in groupSpec.entries) {
        if (entry.key == '_id') continue;

        final fieldName = entry.key;
        final accumulator = entry.value as Map<String, dynamic>;
        final op = accumulator.keys.first;

        if (op == r'$sum') {
          final value = accumulator[op];
          if (value == 1) {
            group[fieldName] = (group[fieldName] ?? 0) + 1;
          } else if (value is String) {
            final fieldValue = _getNestedValue(item, value.substring(1));
            if (fieldValue is num) {
              group[fieldName] = (group[fieldName] ?? 0) + fieldValue;
            }
          }
        }
        // Other accumulators like $avg, $min, $max can be added here
      }
    }

    return groupedResults.values.toList();
  }

  List<Map<String, dynamic>> _processSortStage(
    List<Map<String, dynamic>> input,
    Map<String, dynamic> sortSpec,
  ) {
    final sortedList = List<Map<String, dynamic>>.from(input);
    sortedList.sort((a, b) {
      for (final entry in sortSpec.entries) {
        final field = entry.key;
        final order = entry.value as int; // 1 for asc, -1 for desc

        final valueA = _getNestedValue(a, field);
        final valueB = _getNestedValue(b, field);

        if (valueA == null && valueB == null) continue;
        if (valueA == null) return 1 * order;
        if (valueB == null) return -1 * order;

        if (valueA is Comparable && valueB is Comparable) {
          final cmp = valueA.compareTo(valueB) * order;
          if (cmp != 0) return cmp;
        }
      }
      return 0;
    });
    return sortedList;
  }

  List<Map<String, dynamic>> _processLimitStage(
    List<Map<String, dynamic>> input,
    int limit,
  ) {
    return input.take(limit).toList();
  }
}
