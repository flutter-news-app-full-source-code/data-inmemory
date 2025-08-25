// ignore_for_file: avoid_dynamic_calls, cascade_invocations

import 'dart:async';
import 'dart:math';

import 'package:core/core.dart';
import 'package:data_client/data_client.dart';
import 'package:logging/logging.dart';

/// {@template data_inmemory}
/// An in-memory implementation of [DataClient] for testing or local
/// development.
///
/// This client simulates a remote data source by storing data in memory.
/// It supports CRUD operations, querying, pagination, and user scoping.
///
/// **ID Management:** Relies on the provided `getId` function to extract
/// unique IDs from items. It does not generate IDs.
///
/// **Querying (`readAll`):**
/// - **General Filtering:** Supports filtering on any property in the item's
///   JSON representation, including nested properties using dot-notation
///   (e.g., `'category.id'`). It supports operators like `$in`, `$ne`, `$gte`, etc.
/// - **Special Search Query (`q`):** To simulate a full-text search, the
///   `filter` map accepts a special key: `'q'`.
///   - When `filter: {'q': 'search term'}` is provided, the client performs a
///     case-insensitive substring search.
///   - The search is performed on the `title` field for `Headline` types, and
///     on the `name` field for `Topic` and `Source` types.
///   - The `q` key is processed separately and removed from the filter before
///     other conditions are evaluated, allowing search and other filters to be
///     combined.
/// {@endtemplate}
class DataInMemory<T> implements DataClient<T> {
  /// {@macro data_inmemory}
  DataInMemory({
    required ToJson<T> toJson,
    required String Function(T item) getId,
    List<T>? initialData,
    Logger? logger,
  })  : _toJson = toJson,
        _getId = getId,
        _logger = logger ?? Logger('DataInMemory<$T>') {
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
    final scope = userId ?? 'global';
    _logger.fine('CREATE START: id="$id", scope="$scope"');

    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);

    if (userStorage.containsKey(id)) {
      _logger.warning(
        'CREATE FAILED: Item with ID "$id" already exists for scope "$scope".',
      );
      throw BadRequestException(
        'Item with ID "$id" already exists for user "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);
    _logger.info(
      'CREATE SUCCESS: id="$id" added to scope "$scope". Total items: ${userStorage.length}',
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
    final scope = userId ?? 'global';
    _logger.fine('READ START: id="$id", scope="$scope"');
    final userStorage = _getStorageForUser(userId);

    final item = userStorage[id];

    if (item == null) {
      _logger.warning('READ FAILED: id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for user "$scope".',
      );
    }
    _logger.info('READ SUCCESS: id="$id" FOUND for scope "$scope".');
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
    final scope = userId ?? 'global';
    _logger.fine('ReadAll START: scope="$scope", filter="$filter"');

    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);
    final effectiveFilter =
        filter != null ? Map<String, dynamic>.from(filter) : null;

    // Special handling for 'q' search parameter, which is removed from the
    // main filter to be processed by a dedicated function.
    final searchTerm = effectiveFilter?.remove('q') as String?;
    _logger.fine(
      'ReadAll PARAMS: effectiveFilter="$effectiveFilter", searchTerm="$searchTerm"',
    );

    // 1. Apply all filtering in a single pass.
    // This is more efficient and ensures consistent behavior.
    final allJsonItems = userJsonStorage.values.toList();
    _logger.fine('ReadAll: Total items to filter: ${allJsonItems.length}');

    final matchedJsonItems = allJsonItems.where((jsonItem) {
      final itemId = jsonItem['id'] as String?;
      final matches =
          _itemMatchesAllFilters(jsonItem, effectiveFilter, searchTerm);
      _logger.finer(
        'ReadAll FILTERING: item id="$itemId", matches="$matches"',
      );
      return matches;
    }).toList();

    // Get the original items from the matched JSON items.
    final matchedIds =
        matchedJsonItems.map((json) => json['id'] as String).toSet();
    final allItems = userStorage.values
        .where((item) => matchedIds.contains(_getId(item)))
        .toList();

    // 2. Apply sorting if sort options are provided
    if (sort != null && sort.isNotEmpty) {
      _sortItems(allItems, sort);
    }

    // 3. Create the paginated response from the final sorted and filtered list.
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
    final itemId = jsonItem['id'] as String?;
    _logger.finer('_matchesFilter: Checking item id="$itemId"');

    for (final entry in filter.entries) {
      final key = entry.key;
      final queryValue = entry.value;
      final itemValue = _getNestedValue(jsonItem, key);

      _logger.finest(
        '_matchesFilter [id="$itemId"]: key="$key", queryValue="$queryValue", itemValue="$itemValue"',
      );

      if (queryValue is Map<String, dynamic>) {
        // Handle operators like $in, $gte, etc.
        if (!_evaluateOperator(itemValue, queryValue)) {
          _logger.finer(
            '_matchesFilter [id="$itemId"]: FAILED operator check for key="$key"',
          );
          return false; // This condition failed
        }
      } else {
        // Simple exact match
        if (itemValue?.toString() != queryValue?.toString()) {
          _logger.finer(
            '_matchesFilter [id="$itemId"]: FAILED exact match for key="$key"',
          );
          return false; // This condition failed
        }
      }
    }
    _logger.finer('_matchesFilter: PASSED for item id="$itemId"');
    return true; // All conditions passed
  }

  /// Checks if a given [jsonItem] matches the search query.
  bool _matchesSearchQuery(Map<String, dynamic> jsonItem, String searchTerm) {
    final itemId = jsonItem['id'] as String?;
    if (searchTerm.isEmpty) {
      _logger.finer('_matchesSearchQuery [id="$itemId"]: PASSED (empty term)');
      return true;
    }
    final lowercasedSearchTerm = searchTerm.toLowerCase();

    // Determine which field to search based on the item's 'type'
    final type = jsonItem['type'] as String?;
    String? fieldValue;

    switch (type) {
      case 'headline':
        fieldValue = jsonItem['title'] as String?;
      case 'topic':
      case 'source':
      case 'country':
        fieldValue = jsonItem['name'] as String?;
      default:
        _logger.finer(
          '_matchesSearchQuery [id="$itemId"]: FAILED (unknown type "$type")',
        );
        return false;
    }

    if (fieldValue != null) {
      final match = fieldValue.toLowerCase().contains(lowercasedSearchTerm);
      _logger.finer(
        '_matchesSearchQuery [id="$itemId"]: field="$fieldValue", term="$searchTerm", match="$match"',
      );
      return match;
    }

    _logger.finer(
      '_matchesSearchQuery [id="$itemId"]: FAILED (field value is null)',
    );
    return false;
  }

  /// Checks if a given [jsonItem] matches all conditions in the [filter]
  /// and the [searchTerm].
  bool _itemMatchesAllFilters(
    Map<String, dynamic> jsonItem,
    Map<String, dynamic>? filter,
    String? searchTerm,
  ) {
    // Apply property filtering first
    if (filter != null && filter.isNotEmpty) {
      if (!_matchesFilter(jsonItem, filter)) {
        return false;
      }
    }

    // Apply search term filtering
    if (searchTerm != null && searchTerm.isNotEmpty) {
      if (!_matchesSearchQuery(jsonItem, searchTerm)) {
        return false;
      }
    }

    return true;
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
      final index = allMatchingItems.indexWhere(
        (item) => _getId(item) == startAfterId,
      );
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
    final scope = userId ?? 'global';
    _logger.fine('UPDATE START: id="$id", scope="$scope"');
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);

    if (!userStorage.containsKey(id)) {
      _logger.warning('UPDATE FAILED: id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for update for user "$scope".',
      );
    }

    final incomingId = _getId(item);
    if (incomingId != id) {
      _logger.warning(
        'Update FAILED: ID mismatch: incoming '
        '"$incomingId", path "$id" for scope "$scope".',
      );
      throw BadRequestException(
        'Item ID ("$incomingId") does not match path ID ("$id") for "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);
    _logger.info('UPDATE SUCCESS: id="$id" updated for scope "$scope".');
    return SuccessApiResponse(
      data: item,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> delete({required String id, String? userId}) async {
    final scope = userId ?? 'global';
    _logger.fine('DELETE START: id="$id", scope="$scope"');
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);

    if (!userStorage.containsKey(id)) {
      _logger.warning('DELETE FAILED: id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for deletion for user "$scope".',
      );
    }
    userStorage.remove(id);
    userJsonStorage.remove(id);
    _logger.info(
      'DELETE SUCCESS: id="$id" deleted for scope "$scope". '
      'Total items: ${userStorage.length}',
    );
  }

  @override
  Future<SuccessApiResponse<int>> count({
    String? userId,
    Map<String, dynamic>? filter,
  }) async {
    final scope = userId ?? 'global';
    _logger.fine('COUNT START: scope="$scope", filter="$filter"');
    final userJsonStorage = _getJsonStorageForUser(userId);
    var allItems = userJsonStorage.values.toList();

    if (filter != null && filter.isNotEmpty) {
      allItems =
          allItems.where((item) => _matchesFilter(item, filter)).toList();
    }

    _logger.info('COUNT SUCCESS: scope="$scope", count=${allItems.length}');
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
    final scope = userId ?? 'global';
    _logger.fine('AGGREGATE START: scope="$scope", pipeline="$pipeline"');
    final userJsonStorage = _getJsonStorageForUser(userId);
    var results = userJsonStorage.values.toList();

    for (final stage in pipeline) {
      final stageName = stage.keys.first;
      final stageSpec = stage[stageName] as Object;

      switch (stageName) {
        case r'$match':
          results = _processMatchStage(
            results,
            stageSpec as Map<String, dynamic>,
          );
        case r'$group':
          results = _processGroupStage(
            results,
            stageSpec as Map<String, dynamic>,
          );
        case r'$sort':
          results = _processSortStage(
            results,
            stageSpec as Map<String, dynamic>,
          );
        case r'$limit':
          results = _processLimitStage(results, stageSpec as int);
        default:
          _logger.warning('Unsupported aggregation stage: $stageName');
      }
    }

    _logger.info(
      'AGGREGATE SUCCESS: scope="$scope", resultCount=${results.length}',
    );
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
      final group = groupedResults.putIfAbsent(idValue, () => {'_id': idValue});

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
