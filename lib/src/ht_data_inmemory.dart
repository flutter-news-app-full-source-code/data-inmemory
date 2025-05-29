import 'dart:async';
import 'dart:math';

import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_shared/ht_shared.dart';

/// {@template ht_data_inmemory_client}
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
/// - **Exact Match:** For other keys, compares the item's field value
///   (as a string) with the query value (string).
/// - **Logic:** All query conditions are ANDed.
/// {@endtemplate}
class HtDataInMemoryClient<T> implements HtDataClient<T> {
  /// {@macro ht_data_inmemory_client}
  HtDataInMemoryClient({
    required ToJson<T> toJson,
    required String Function(T item) getId,
    List<T>? initialData,
  })  : _toJson = toJson,
        _getId = getId {
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
    // This should return the inner map for the user, which is Map<String, Map<String, dynamic>>
    // However, _userScopedJsonStorage stores Map<itemId, jsonDataMap> per user.
    // So, the value associated with a user key is Map<String, Map<String, dynamic>>.
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

    if (userStorage.containsKey(id)) {
      final scope = userId ?? 'global';
      throw BadRequestException(
        'Item with ID "$id" already exists for user "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);

    await Future<void>.delayed(Duration.zero); // Simulate async
    return SuccessApiResponse(data: item);
  }

  @override
  Future<SuccessApiResponse<T>> read({
    required String id,
    String? userId,
  }) async {
    await Future<void>.delayed(Duration.zero); // Simulate async
    final userStorage = _getStorageForUser(userId);
    final item = userStorage[id];

    if (item == null) {
      final scope = userId ?? 'global';
      throw NotFoundException(
        'Item with ID "$id" not found for user "$scope".',
      );
    }
    return SuccessApiResponse(data: item);
  }

  @override
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAll({
    String? userId,
    String? startAfterId,
    int? limit,
  }) async {
    await Future<void>.delayed(Duration.zero); // Simulate async
    final userStorage = _getStorageForUser(userId);
    final allItems = userStorage.values.toList();

    final paginatedResponse = _createPaginatedResponse(
      allItems,
      startAfterId,
      limit,
    );
    return SuccessApiResponse(data: paginatedResponse);
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
        // If startAfterId is provided but not found, return empty
        return const PaginatedResponse(items: [], cursor: null, hasMore: false);
      }
    }

    // Ensure startIndex is within bounds
    if (startIndex >= allMatchingItems.length) {
      return const PaginatedResponse(items: [], cursor: null, hasMore: false);
    }

    // Determine items for this page
    final actualLimit = limit ?? allMatchingItems.length; // Default: all
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
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAllByQuery(
    Map<String, dynamic> query, {
    String? userId,
    String? startAfterId,
    int? limit,
  }) async {
    await Future<void>.delayed(Duration.zero); // Simulate async

    final userJsonStorage = _getJsonStorageForUser(userId);
    final userStorage = _getStorageForUser(userId);

    if (query.isEmpty) {
      final allItems = userStorage.values.toList();
      final paginatedResp =
          _createPaginatedResponse(allItems, startAfterId, limit);
      return SuccessApiResponse(data: paginatedResp);
    }

    final matchedItems = <T>[];
    userJsonStorage.forEach((itemId, Map<String, dynamic> jsonItem) {
      var allConditionsMet = true;
      query.forEach((filterKey, filterValue) {
        if (!allConditionsMet) return; // Already failed, skip others

        var actualPath = filterKey;
        var operation = 'exact'; // 'exact', 'in', 'contains'

        if (filterKey.endsWith('_in')) {
          actualPath = filterKey.substring(0, filterKey.length - 3);
          operation = 'in';
        } else if (filterKey.endsWith('_contains')) {
          actualPath = filterKey.substring(0, filterKey.length - 9);
          operation = 'contains';
        }

        final dynamic actualItemValue = _getNestedValue(jsonItem, actualPath);

        // FilterValue from API query params is always a String.
        final filterValueStr = filterValue as String;

        switch (operation) {
          case 'contains':
            if (actualItemValue == null) {
              allConditionsMet = false;
            } else if (!actualItemValue
                .toString()
                .toLowerCase()
                .contains(filterValueStr.toLowerCase())) {
              allConditionsMet = false;
            }
          case 'in':
            if (actualItemValue == null) {
              allConditionsMet = false;
            } else {
              final expectedQueryValues = filterValueStr
                  .split(',')
                  .map((e) => e.trim().toLowerCase()) // Trim whitespace
                  .where((e) => e.isNotEmpty) // Remove empty strings
                  .toList();
              if (expectedQueryValues.isEmpty && filterValueStr.isNotEmpty) {
                // case where filterValueStr was just commas e.g. ",,"
                allConditionsMet = false;
              } else if (actualItemValue is List) {
                // Handle list field: check if any item in actualItemValue (list)
                // is present in expectedQueryValues (list from query)
                final actualListStr = actualItemValue
                    .map((e) => e.toString().toLowerCase())
                    .toList();
                final foundMatchInList =
                    expectedQueryValues.any(actualListStr.contains);
                if (!foundMatchInList) {
                  allConditionsMet = false;
                }
              } else {
                // Handle single field value
                if (!expectedQueryValues
                    .contains(actualItemValue.toString().toLowerCase())) {
                  allConditionsMet = false;
                }
              }
            }
          case 'exact':
          default:
            if (actualItemValue == null) {
              // Consider "null" string for matching if actualItemValue is null
              if (filterValueStr != 'null') {
                allConditionsMet = false;
              }
            } else if (actualItemValue.toString() != filterValueStr) {
              allConditionsMet = false;
            }
        }
      });

      if (allConditionsMet) {
        final originalItem = userStorage[itemId];
        if (originalItem != null) {
          matchedItems.add(originalItem);
        }
      }
    });

    final paginatedResponse =
        _createPaginatedResponse(matchedItems, startAfterId, limit);
    return SuccessApiResponse(data: paginatedResponse);
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

    if (!userStorage.containsKey(id)) {
      throw NotFoundException(
        'Item with ID "$id" not found for update for user "$scope".',
      );
    }

    final incomingId = _getId(item);
    if (incomingId != id) {
      throw BadRequestException(
        'Item ID ("$incomingId") does not match path ID ("$id") for "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);

    await Future<void>.delayed(Duration.zero); // Simulate async
    return SuccessApiResponse(data: item);
  }

  @override
  Future<void> delete({
    required String id,
    String? userId,
  }) async {
    await Future<void>.delayed(Duration.zero); // Simulate async
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);
    final scope = userId ?? 'global';

    if (!userStorage.containsKey(id)) {
      throw NotFoundException(
        'Item with ID "$id" not found for deletion for user "$scope".',
      );
    }
    userStorage.remove(id);
    userJsonStorage.remove(id);
  }
}
