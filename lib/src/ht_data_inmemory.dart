//
// ignore_for_file: unused_shown_name, lines_longer_than_80_chars, avoid_print

import 'dart:async';
import 'dart:math';

import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_shared/ht_shared.dart';

/// {@template ht_data_inmemory_client}
/// An in-memory implementation of [HtDataClient] for testing or local development.
///
/// This client simulates the behavior of a remote data source by storing data
/// of type [T] in memory. It supports standard CRUD operations, basic querying,
/// and pagination, including user-scoped and global data.
///
/// **Important:**
/// - **ID Management:** This client relies on the provided `getId` function
///   to extract a unique identifier from items of type [T]. It does **not**
///   generate IDs itself. Ensure items provided to `create` have unique IDs.
/// - **Querying (`readAllByQuery`):**
///   - Matches against the JSON representation of stored items.
///   - **Nested Property Access:** Supports dot-notation in query keys to target
///     nested fields within the JSON structure (e.g., a query key like
///     `'category.id'` will attempt to access `item['category']['id']`).
///   - **"IN List" Filtering:** For query keys ending with an `_in` suffix
///     (e.g., `'category.id_in'`, `'tags_in'`), the corresponding query value
///     is expected to be a single string containing comma-separated values.
///     The client will check if the actual property's value (obtained via the
///     dot-notation path before `_in`, and converted to a string) is one of
///     the values in the comma-separated list.
///   - **"CONTAINS Text" Filtering:** For query keys ending with a `_contains`
///     suffix (e.g., `'title_contains'`, `'description_contains'`), the
///     corresponding query value is treated as a search term. The client
///     performs a case-insensitive substring check to see if the actual
///     property's string value (obtained via the dot-notation path before
///     `_contains`) contains the search term.
///   - **Exact Match Filtering:** For query keys that do not use the `_in` or
///     `_contains` suffixes, an exact equality match is performed between the
///     actual property's value (obtained via the dot-notation path) and the
///     query value.
///   - **Logic:** All conditions derived from the provided query map are ANDed
///     together to determine a match.
///   - **Caller Responsibility:** The structure of the query map, including the
///     use of dot-notation and suffixes like `_in` or `_contains`, is determined
///     by the caller (e.g., the API layer), which should align with the
///     model-specific filtering rules.
///   - **Limitations:** Does not support range queries, complex sorting beyond
///     natural order of retrieval, or full-text search engine capabilities.
/// - **Error Simulation:** Throws exceptions like [NotFoundException] and
///   [BadRequestException] to mimic potential API errors, using types defined
///   in `package:ht_shared`. It does not simulate network or auth errors
///   unless explicitly added.
/// - **User Scoping:** Data is stored and accessed based on the provided
///   `userId`. A special key (`_globalDataKey`) is used for data where
///   `userId` is `null`.
/// {@endtemplate}
class HtDataInMemoryClient<T> implements HtDataClient<T> {
  /// {@macro ht_data_inmemory_client}
  ///
  /// Requires:
  /// - [toJson]: A function to convert an item of type [T] to a JSON map.
  ///             Used for storing data for querying.
  /// - [getId]: A function to extract the unique string ID from an item of type [T].
  /// - [initialData]: An optional list of items to populate the client with initially.
  ///                  These items are treated as global data (userId = null).
  ///                  Throws [ArgumentError] if duplicate IDs are found in the
  ///                  initial data.
  HtDataInMemoryClient({
    required ToJson<T> toJson,
    required String Function(T item) getId,
    List<T>? initialData,
  })  : _toJson = toJson,
        _getId = getId {
    if (initialData != null) {
      for (final item in initialData) {
        final id = _getId(item);
        if (_userScopedStorage[_globalDataKey]?.containsKey(id) ?? false) {
          throw ArgumentError(
            'Duplicate ID "$id" found in initialData.',
          );
        }
        // Store initial data as global data
        _userScopedStorage.putIfAbsent(
          _globalDataKey,
          () => <String, T>{},
        )[id] = item;
        _userScopedJsonStorage.putIfAbsent(
          _globalDataKey,
          () => <String, Map<String, dynamic>>{},
        )[id] = _toJson(item);
      }
    }
  }

  final ToJson<T> _toJson;
  final String Function(T item) _getId;

  // Key used for storing global data (when userId is null).
  static const String _globalDataKey = '__global__';

  // In-memory storage for the actual items, nested by userId.
  // Outer map key: userId (or _globalDataKey for null userId)
  // Inner map key: item ID
  final Map<String, Map<String, T>> _userScopedStorage = {};
  // Parallel storage for the JSON representation, nested by userId, used for querying.
  final Map<String, Map<String, dynamic>> _userScopedJsonStorage = {};

  // Helper to get the storage map for a given userId.
  Map<String, T> _getStorageForUser(String? userId) {
    final key = userId ?? _globalDataKey;
    return _userScopedStorage.putIfAbsent(key, () => <String, T>{});
  }

  // Helper to get the JSON storage map for a given userId.
  Map<String, dynamic> _getJsonStorageForUser(String? userId) {
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

    if (userStorage.containsKey(id)) {
      throw BadRequestException(
        'Item with ID "$id" already exists for user "$userId".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);

    // Simulate async operation
    await Future<void>.delayed(Duration.zero);
    return SuccessApiResponse(data: item);
  }

  @override
  Future<SuccessApiResponse<T>> read({
    required String id,
    String? userId,
  }) async {
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);

    final userStorage = _getStorageForUser(userId);
    final item = userStorage[id];

    if (item == null) {
      throw NotFoundException(
        'Item with ID "$id" not found for user "$userId".',
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
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);

    final userStorage = _getStorageForUser(userId);
    final allItems = userStorage.values.toList(); // Get all items for the user

    final paginatedResponse = _createPaginatedResponse(
      allItems,
      startAfterId,
      limit,
    );
    return SuccessApiResponse(data: paginatedResponse);
  }

  @override
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAllByQuery(
    Map<String, dynamic> query, {
    String? userId,
    String? startAfterId,
    int? limit,
  }) async {
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);

    final userJsonStorage = _getJsonStorageForUser(userId);
    final userStorage = _getStorageForUser(userId);

    final List<T> matchedItems;
    if (query.isEmpty) {
      // If query is empty, use all items for the user
      matchedItems = userStorage.values.toList();
    } else {
      // Otherwise, filter based on the query
      matchedItems = <T>[];
      userJsonStorage.forEach((id, dynamic jsonItemDynamic) {
        final jsonItem = jsonItemDynamic as Map<String, dynamic>;
        var match = true;

        query.forEach((filterKey, filterValue) {
          if (!match) return; // Already failed a condition, skip others

          var actualPath = filterKey;
          var isContainsSearch = false;
          var isInListSearch = false;

          if (filterKey.endsWith('_in')) {
            actualPath = filterKey.substring(0, filterKey.length - 3);
            isInListSearch = true;
          } else if (filterKey.endsWith('_contains')) {
            actualPath = filterKey.substring(0, filterKey.length - 9);
            isContainsSearch = true;
          }

          final dynamic actualItemValue = _getNestedValue(jsonItem, actualPath);

          if (isInListSearch) {
            if (filterValue is! String) {
              // Expected comma-separated string for _in queries
              match = false;
              print(
                'Warning: Filter value for "$filterKey" is not a String.',
              );
              return;
            }
            final expectedValues = filterValue.split(',');
            if (actualItemValue == null ||
                !expectedValues.contains(actualItemValue.toString())) {
              match = false;
            }
          } else if (isContainsSearch) {
            if (actualItemValue == null || filterValue is! String) {
              match = false;
              if (filterValue is! String) {
                print(
                  'Warning: Filter value for "$filterKey" is not a String.',
                );
              }
              // Removed return; to allow loop to continue if match is false
            } else if (!actualItemValue
                .toString()
                .toLowerCase()
                // ignore: unnecessary_parenthesis
                .contains((filterValue).toLowerCase())) {
              match = false;
            }
          } else {
            // Exact match
            if (actualItemValue != filterValue) {
              match = false;
            }
          }
        });

        if (match) {
          // Retrieve the original item from userStorage using the ID
          // We assume consistency between userStorage and userJsonStorage
          final originalItem = userStorage[id];
          if (originalItem != null) {
            matchedItems.add(originalItem);
          } else {
            // This case should ideally not happen if create/update/delete
            // maintain consistency. Log or handle as an internal error if needed.
            print(
              'Warning: Inconsistency detected for user "$userId". '
              'JSON found for ID "$id" but original item is missing in storage.',
            );
          }
        }
      });
    } // End of else block for non-empty query

    final paginatedResponse = _createPaginatedResponse(
      matchedItems,
      startAfterId,
      limit,
    );
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

    final existingItem = userStorage[id];
    if (existingItem == null) {
      throw NotFoundException(
        'Item with ID "$id" not found for update for user "$userId".',
      );
    }

    final incomingId = _getId(item);
    if (incomingId != id) {
      throw BadRequestException(
        'The ID of the item ("$incomingId") does not match the ID '
        'in the path ("$id") for user "$userId".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);

    // Simulate async operation
    await Future<void>.delayed(Duration.zero);
    return SuccessApiResponse(data: item);
  }

  @override
  Future<void> delete({
    required String id,
    String? userId,
  }) async {
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);

    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);

    if (!userStorage.containsKey(id)) {
      throw NotFoundException(
        'Item with ID "$id" not found for deletion for user "$userId".',
      );
    }

    userStorage.remove(id);
    userJsonStorage.remove(id);
  }

  // Helper to safely access nested values in a map using dot notation.
  dynamic _getNestedValue(Map<String, dynamic> item, String dotPath) {
    if (dotPath.isEmpty) {
      return null;
    }
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

  // Helper function to create a PaginatedResponse object
  PaginatedResponse<T> _createPaginatedResponse(
    List<T> allMatchingItems,
    String? startAfterId,
    int? limit,
  ) {
    var startIndex = 0;

    if (startAfterId != null) {
      // Find the index of the item *after* which we should start
      final index = allMatchingItems.indexWhere(
        (item) => _getId(item) == startAfterId,
      );
      if (index != -1) {
        startIndex = index + 1; // Start after the found item
      } else {
        // If startAfterId is provided but not found, return an empty response
        return const PaginatedResponse(items: [], cursor: null, hasMore: false);
      }
    }

    // Ensure startIndex is within bounds
    if (startIndex >= allMatchingItems.length) {
      return const PaginatedResponse(items: [], cursor: null, hasMore: false);
    }

    // Determine the actual number of items to take for this page
    final actualLimit =
        limit ?? allMatchingItems.length; // Default: take all remaining
    final count = min(actualLimit, allMatchingItems.length - startIndex);

    // Calculate the end index (exclusive)
    final endIndex = startIndex + count;

    // Get the items for the current page
    final pageItems = allMatchingItems.sublist(startIndex, endIndex);

    // Determine if there are more items after this page
    final hasMore = endIndex < allMatchingItems.length;

    // Determine the cursor for the next page (ID of the last item on this page)
    final cursor =
        (pageItems.isNotEmpty && hasMore) ? _getId(pageItems.last) : null;

    return PaginatedResponse(
      items: pageItems,
      cursor: cursor,
      hasMore: hasMore,
    );
  }
}
