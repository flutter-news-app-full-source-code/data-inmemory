// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_shared/ht_shared.dart';

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
    print('[HtDataInMemory<$T>] create: id="$id", scope="$scope"');

    if (userStorage.containsKey(id)) {
      print('[HtDataInMemory<$T>] create: FAILED - Item with ID "$id" '
          'already exists for scope "$scope".');
      throw BadRequestException(
        'Item with ID "$id" already exists for user "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);
    print('[HtDataInMemory<$T>] create: SUCCESS - id="$id" added to scope '
        '"$scope". Total items: ${userStorage.keys.length}');
    // await Future<void>.delayed(Duration.zero); // Simulate async
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
    // await Future<void>.delayed(Duration.zero); // Simulate async
    final userStorage = _getStorageForUser(userId);
    final scope = userId ?? 'global';
    print('[HtDataInMemory<$T>] read: id="$id", scope="$scope"');

    final item = userStorage[id];

    if (item == null) {
      print(
          '[HtDataInMemory<$T>] read: FAILED - id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for user "$scope".',
      );
    }
    print(
        '[HtDataInMemory<$T>] read: SUCCESS - id="$id" FOUND for scope "$scope".');
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
    String? startAfterId,
    int? limit,
    String? sortBy,
    SortOrder? sortOrder,
  }) async {
    // await Future<void>.delayed(Duration.zero); // Simulate async
    final userStorage = _getStorageForUser(userId);
    final allItems = userStorage.values.toList();

    if (sortBy != null) {
      _sortItems(allItems, sortBy, sortOrder ?? SortOrder.asc);
    }

    final paginatedResponse = _createPaginatedResponse(
      allItems,
      startAfterId,
      limit,
    );
    return SuccessApiResponse(
      data: paginatedResponse,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
    );
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

  void _sortItems(List<T> items, String sortBy, SortOrder sortOrder) {
    items.sort((a, b) {
      final jsonA = _toJson(a);
      final jsonB = _toJson(b);

      final valueA = _getNestedValue(jsonA, sortBy);
      final valueB = _getNestedValue(jsonB, sortBy);

      // Handle nulls: items with null values for the sort key go last.
      if (valueA == null && valueB == null) return 0;
      if (valueA == null) return 1; // a is greater (put at end)
      if (valueB == null) return -1; // b is greater (put at end)

      int compareResult;
      if (valueA is num && valueB is num) {
        compareResult = valueA.compareTo(valueB);
      } else {
        compareResult = valueA.toString().toLowerCase().compareTo(
              valueB.toString().toLowerCase(),
            );
      }

      return sortOrder == SortOrder.asc ? compareResult : -compareResult;
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

  /// Transforms raw query parameters (like those from URL queries) into the
  /// internal format expected by the in-memory client's filtering logic.
  ///
  /// This method mimics the query translation performed by the `ht-api`
  /// backend's data route handlers, allowing the `HtDataInMemoryClient` to
  /// directly consume queries from the Flutter app's `HeadlinesFeedBloc`.
  Map<String, dynamic> _transformQuery(Map<String, dynamic> rawQuery) {
    // DEBUG: Log the raw query received by _transformQuery
    print('[HtDataInMemory<$T>] _transformQuery: received rawQuery: $rawQuery');

    final transformed = <String, dynamic>{};

    // Always pass through pagination parameters directly.
    // These are expected to be already present in rawQuery if applicable.
    if (rawQuery.containsKey('startAfterId')) {
      transformed['startAfterId'] = rawQuery['startAfterId'];
    }
    if (rawQuery.containsKey('limit')) {
      transformed['limit'] = rawQuery['limit'];
    }

    // Determine the model type at runtime to apply specific transformations.
    // This makes the generic client behave correctly for known model types.
    // Using `T == SomeType` for correct generic type comparison.
    print('[HtDataInMemory<$T>] _transformQuery: detected generic type T: $T');

    Set<String> allowedKeys;
    String? modelNameForError;

    if (T == Headline) {
      modelNameForError = 'headline';
      allowedKeys = {'topics', 'sources', 'q'};
      final qValue = rawQuery['q'] as String?;
      if (qValue != null && qValue.isNotEmpty) {
        transformed['titleContains'] = qValue;
        print('[HtDataInMemory<$T>] _transformQuery: Headline: Applied '
            'titleContains for q: $qValue');
      } else {
        final topics = rawQuery['topics'] as String?;
        if (topics != null && topics.isNotEmpty) {
          transformed['topic.idIn'] = topics;
          print('[HtDataInMemory<$T>] _transformQuery: Headline: Applied '
              'topic.idIn: $topics');
        }
        final sources = rawQuery['sources'] as String?;
        if (sources != null && sources.isNotEmpty) {
          transformed['source.idIn'] = sources;
          print('[HtDataInMemory<$T>] _transformQuery: Headline: Applied '
              'source.idIn: $sources');
        }
      }
    } else if (T == Source) {
      modelNameForError = 'source';
      allowedKeys = {'countries', 'sourceTypes', 'languages', 'q'};
      final qValue = rawQuery['q'] as String?;
      if (qValue != null && qValue.isNotEmpty) {
        transformed['nameContains'] = qValue; // Simplified for in-memory
        print('[HtDataInMemory<$T>] _transformQuery: Source: Applied '
            'nameContains for q: $qValue');
      } else {
        final countries = rawQuery['countries'] as String?;
        if (countries != null && countries.isNotEmpty) {
          transformed['headquarters.isoCodeIn'] = countries;
          print('[HtDataInMemory<$T>] _transformQuery: Source: Applied '
              'headquarters.isoCodeIn: $countries');
        }
        final sourceTypes = rawQuery['sourceTypes'] as String?;
        if (sourceTypes != null && sourceTypes.isNotEmpty) {
          transformed['sourceTypeIn'] = sourceTypes;
          print('[HtDataInMemory<$T>] _transformQuery: Source: Applied '
              'sourceTypeIn: $sourceTypes');
        }
        final languages = rawQuery['languages'] as String?;
        if (languages != null && languages.isNotEmpty) {
          transformed['languageIn'] = languages;
          print('[HtDataInMemory<$T>] _transformQuery: Source: Applied '
              'languageIn: $languages');
        }
      }
    } else if (T == Topic) {
      modelNameForError = 'topic';
      allowedKeys = {'q'};
      final qValue = rawQuery['q'] as String?;
      if (qValue != null && qValue.isNotEmpty) {
        transformed['nameContains'] = qValue;
        print('[HtDataInMemory<$T>] _transformQuery: Topic: Applied '
            'nameContains for q: $qValue');
      }
    } else if (T == Country) {
      modelNameForError = 'country';
      allowedKeys = {'q'};
      final qValue = rawQuery['q'] as String?;
      if (qValue != null && qValue.isNotEmpty) {
        transformed['nameContains'] = qValue;
        transformed['isoCodeContains'] = qValue;
        print('[HtDataInMemory<$T>] _transformQuery: Country: Applied '
            'nameContains and isoCodeContains for q: $qValue');
      }
    } else {
      // For other models (e.g., User, UserAppSettings, AppConfig),
      // pass through all non-standard query params directly.
      // This assumes they are already in the correct format for exact match.
      allowedKeys = rawQuery.keys.toSet()..removeAll({'startAfterId', 'limit'});
      rawQuery.forEach((key, value) {
        if (key != 'startAfterId' && key != 'limit') {
          transformed[key] = value;
        }
      });
    }

    // Validate received keys against allowed keys for the specific models
    final receivedKeysForValidation = rawQuery.keys.toSet()
      ..removeAll({'startAfterId', 'limit', 'model'});

    if (modelNameForError != null) {
      for (final key in receivedKeysForValidation) {
        if (!allowedKeys.contains(key)) {
          print('[HtDataInMemory<$T>] _transformQuery: FAILED - Invalid '
              'query parameter "$key" for model "$modelNameForError". '
              'Allowed: ${allowedKeys.join(', ')}.');
          throw BadRequestException(
            'Invalid query parameter "$key" for model "$modelNameForError". '
            'Allowed parameters are: ${allowedKeys.join(', ')}.',
          );
        }
      }
    }

    // DEBUG: Log the final transformed query
    print(
        '[HtDataInMemory<$T>] _transformQuery: returning transformed: $transformed');
    return transformed;
  }

  @override
  Future<SuccessApiResponse<PaginatedResponse<T>>> readAllByQuery(
    Map<String, dynamic> query, {
    String? userId,
    String? startAfterId,
    int? limit,
    String? sortBy,
    SortOrder? sortOrder,
  }) async {
    // await Future<void>.delayed(Duration.zero);

    final userJsonStorage = _getJsonStorageForUser(userId);
    final userStorage = _getStorageForUser(userId);

    // Transform the incoming query parameters before processing
    final transformedQuery = _transformQuery(query);

    if (transformedQuery.isEmpty) {
      final allItems = userStorage.values.toList();
      final paginatedResp =
          _createPaginatedResponse(allItems, startAfterId, limit);
      return SuccessApiResponse(
        data: paginatedResp,
        metadata: ResponseMetadata(
          requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
          timestamp: DateTime.now(),
        ),
      );
    }

    final matchedItems = <T>[];
    userJsonStorage.forEach((itemId, Map<String, dynamic> jsonItem) {
      final containsFilters = <MapEntry<String, String>>[];
      final otherFilters = <String, String>{};

      // Use transformedQuery for filtering
      transformedQuery.forEach((key, value) {
        if (key.endsWith('Contains')) {
          containsFilters.add(MapEntry(key, value as String));
        } else if (key != 'startAfterId' && key != 'limit') {
          // Exclude pagination params from otherFilters
          otherFilters[key] = value as String;
        }
      });

      var matchesOtherFilters = true;
      if (otherFilters.isNotEmpty) {
        otherFilters.forEach((filterKey, filterValueStr) {
          if (!matchesOtherFilters) return;

          var actualPath = filterKey;
          var operation = 'exact';

          if (filterKey.endsWith('In')) {
            actualPath = filterKey.substring(0, filterKey.length - 2);
            operation = 'in';
          }

          final dynamic actualItemValue = _getNestedValue(jsonItem, actualPath);

          switch (operation) {
            case 'in':
              if (actualItemValue == null) {
                matchesOtherFilters = false;
              } else {
                final expectedQueryValues = filterValueStr
                    .split(',')
                    .map((e) => e.trim().toLowerCase())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (expectedQueryValues.isEmpty && filterValueStr.isNotEmpty) {
                  matchesOtherFilters = false;
                } else if (actualItemValue is List) {
                  final actualListStr = actualItemValue
                      .map((e) => e.toString().toLowerCase())
                      .toList();
                  final foundMatchInList =
                      expectedQueryValues.any(actualListStr.contains);
                  if (!foundMatchInList) {
                    matchesOtherFilters = false;
                  }
                } else {
                  if (!expectedQueryValues
                      .contains(actualItemValue.toString().toLowerCase())) {
                    matchesOtherFilters = false;
                  }
                }
              }
            case 'exact':
            default:
              if (actualItemValue == null) {
                if (filterValueStr != 'null') {
                  matchesOtherFilters = false;
                }
              } else if (actualItemValue.toString() != filterValueStr) {
                matchesOtherFilters = false;
              }
          }
        });
      }

      var matchesAnyContains = false;
      if (containsFilters.isNotEmpty) {
        for (final entry in containsFilters) {
          final filterKey = entry.key;
          final filterValueStr = entry.value;
          final actualPath = filterKey.substring(0, filterKey.length - 8);
          final dynamic actualItemValue = _getNestedValue(jsonItem, actualPath);

          if (actualItemValue != null &&
              actualItemValue
                  .toString()
                  .toLowerCase()
                  .contains(filterValueStr.toLowerCase())) {
            matchesAnyContains = true;
            break;
          }
        }
      }

      if (matchesOtherFilters &&
          (containsFilters.isEmpty || matchesAnyContains)) {
        final originalItem = userStorage[itemId];
        if (originalItem != null) {
          matchedItems.add(originalItem);
        }
      }
    });

    if (sortBy != null) {
      _sortItems(matchedItems, sortBy, sortOrder ?? SortOrder.asc);
    }

    // Extract pagination parameters from the original query, not the transformed one
    final finalStartAfterId = query['startAfterId'] as String?;
    final finalLimit =
        query['limit'] != null ? int.tryParse(query['limit'] as String) : null;

    final paginatedResponse =
        _createPaginatedResponse(matchedItems, finalStartAfterId, finalLimit);
    return SuccessApiResponse(
      data: paginatedResponse,
      metadata: ResponseMetadata(
        requestId: 'in-memory-req-${DateTime.now().toIso8601String()}',
        timestamp: DateTime.now(),
      ),
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
    print('[HtDataInMemory<$T>] update: id="$id", scope="$scope"');

    if (!userStorage.containsKey(id)) {
      print(
          '[HtDataInMemory<$T>] update: FAILED - id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for update for user "$scope".',
      );
    }

    final incomingId = _getId(item);
    if (incomingId != id) {
      print('[HtDataInMemory<$T>] update: FAILED - ID mismatch: incoming '
          '"$incomingId", path "$id" for scope "$scope".');
      throw BadRequestException(
        'Item ID ("$incomingId") does not match path ID ("$id") for "$scope".',
      );
    }

    userStorage[id] = item;
    userJsonStorage[id] = _toJson(item);
    print(
        '[HtDataInMemory<$T>] update: SUCCESS - id="$id" updated for scope "$scope".');
    // await Future<void>.delayed(Duration.zero);
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
    // await Future<void>.delayed(Duration.zero);
    final userStorage = _getStorageForUser(userId);
    final userJsonStorage = _getJsonStorageForUser(userId);
    final scope = userId ?? 'global';
    print('[HtDataInMemory<$T>] delete: id="$id", scope="$scope"');

    if (!userStorage.containsKey(id)) {
      print(
          '[HtDataInMemory<$T>] delete: FAILED - id="$id" NOT FOUND for scope "$scope".');
      throw NotFoundException(
        'Item with ID "$id" not found for deletion for user "$scope".',
      );
    }
    userStorage.remove(id);
    userJsonStorage.remove(id);
    print('[HtDataInMemory<$T>] delete: SUCCESS - id="$id" deleted for scope '
        '"$scope". Total items: ${userStorage.keys.length}');
  }
}
