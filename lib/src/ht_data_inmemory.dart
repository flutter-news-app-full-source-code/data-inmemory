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
/// and pagination.
///
/// **Important:**
/// - **ID Management:** This client relies on the provided `getId` function
///   to extract a unique identifier from items of type [T]. It does **not**
///   generate IDs itself. Ensure items provided to `create` have unique IDs.
/// - **Querying:** The `readAllByQuery` method performs a simple key-value match
///   against the JSON representation of the stored items (obtained via the
///   provided `toJson` function). It does not support complex query logic
///   (like range queries, sorting beyond natural order, etc.).
/// - **Error Simulation:** Throws exceptions like [NotFoundException] and
///   [BadRequestException] to mimic potential API errors, using types defined
///   in `package:ht_http_client`. It does not simulate network or auth errors
///   unless explicitly added.
/// {@endtemplate}
class HtDataInMemoryClient<T> implements HtDataClient<T> {
  /// {@macro ht_data_inmemory_client}
  ///
  /// Requires:
  /// - [toJson]: A function to convert an item of type [T] to a JSON map.
  ///             Used for storing data for querying.
  /// - [getId]: A function to extract the unique string ID from an item of type [T].
  /// - [initialData]: An optional list of items to populate the client with initially.
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
        if (_storage.containsKey(id)) {
          throw ArgumentError(
            'Duplicate ID "$id" found in initialData.',
          );
        }
        _storage[id] = item;
        _jsonStorage[id] = _toJson(item);
      }
    }
  }

  final ToJson<T> _toJson;
  final String Function(T item) _getId;

  // In-memory storage for the actual items.
  final Map<String, T> _storage = {};
  // Parallel storage for the JSON representation, used for querying.
  final Map<String, Map<String, dynamic>> _jsonStorage = {};

  @override
  Future<SuccessApiResponse<T>> create(T item) async {
    final id = _getId(item);
    if (_storage.containsKey(id)) {
      throw BadRequestException(
        'Item with ID "$id" already exists.',
      );
    }
    _storage[id] = item;
    _jsonStorage[id] = _toJson(item);
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);
    return SuccessApiResponse(data: item);
  }

  @override
  Future<SuccessApiResponse<T>> read(String id) async {
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);
    final item = _storage[id];
    if (item == null) {
      throw NotFoundException('Item with ID "$id" not found.');
    }
    return SuccessApiResponse(data: item);
  }

  @override
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAll({
    String? startAfterId,
    int? limit,
  }) async {
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);

    final allItems = _storage.values.toList(); // Get all items

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
    String? startAfterId,
    int? limit,
  }) async {
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);

    final List<T> matchedItems;
    if (query.isEmpty) {
      // If query is empty, use all items
      matchedItems = _storage.values.toList();
    } else {
      // Otherwise, filter based on the query
      matchedItems = <T>[];
      _jsonStorage.forEach((id, jsonItem) {
        var match = true;
        query.forEach((key, value) {
          // Check if the key exists and the value matches
          if (!jsonItem.containsKey(key) || jsonItem[key] != value) {
            match = false;
          }
        });

        if (match) {
          // Retrieve the original item from _storage using the ID
          // We assume consistency between _storage and _jsonStorage
          final originalItem = _storage[id];
          if (originalItem != null) {
            matchedItems.add(originalItem);
          } else {
            // This case should ideally not happen if create/update/delete
            // maintain consistency. Log or handle as an internal error if needed.
            print(
              'Warning: Inconsistency detected. JSON found for ID "$id" '
              'but original item is missing in _storage.',
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
  Future<SuccessApiResponse<T>> update(String id, T item) async {
    final existingItem = _storage[id];
    if (existingItem == null) {
      throw NotFoundException('Item with ID "$id" not found for update.');
    }

    final incomingId = _getId(item);
    if (incomingId != id) {
      throw BadRequestException(
        'The ID of the item ("$incomingId") does not match the ID '
        'in the path ("$id").',
      );
    }

    _storage[id] = item;
    _jsonStorage[id] = _toJson(item);
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);
    return SuccessApiResponse(data: item);
  }

  @override
  Future<void> delete(String id) async {
    // Simulate async operation
    await Future<void>.delayed(Duration.zero);
    if (!_storage.containsKey(id)) {
      throw NotFoundException('Item with ID "$id" not found for deletion.');
    }
    _storage.remove(id);
    _jsonStorage.remove(id);
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
