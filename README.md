# ht_data_inmemory

![coverage: percentage](https://img.shields.io/badge/coverage-98-green)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License: PolyForm Free Trial](https://img.shields.io/badge/License-PolyForm%20Free%20Trial-blue)](https://polyformproject.org/licenses/free-trial/1.0.0)

An in-memory implementation of the `HtDataClient` interface, designed for testing or local development scenarios. It simulates a remote data source by storing data in memory and mimicking basic API behaviors, including error responses using exceptions defined in `package:ht_http_client`.

## Description

This package provides `HtDataInMemoryClient<T>`, a concrete implementation of the abstract `HtDataClient<T>` from the `ht_data_client` package.

Key characteristics:
- **In-Memory Storage:** Data is stored locally in Dart `Map` objects. Data is lost when the client instance is destroyed.
- **Dependency on `ht_data_client`:** Implements the standard data client interface.
- **Requires ID and JSON Logic:** You must provide functions to extract a unique ID (`getId`) and serialize items to JSON (`toJson`) during instantiation. The client does *not* generate IDs itself.
- **Optional Initial Data:** You can optionally provide a `List<T>` via the `initialData` constructor parameter to pre-populate the client. Throws `ArgumentError` if duplicate IDs are found in the initial data.
- **Simple Querying:** The `readAllByQuery` method performs basic key-value matching on the JSON representation of items. It does not support complex queries (ranges, advanced sorting, etc.).
- **Error Simulation:** Throws exceptions like `NotFoundException` and `BadRequestException` (from `package:ht_http_client`) to simulate common API errors.
- **Pagination:** Supports basic pagination via `startAfterId` and `limit` parameters on `readAll` and `readAllByQuery`.

## Getting Started

Add the following to your `pubspec.yaml` file under `dependencies` (or `dev_dependencies` if only used for testing):

```yaml
dependencies:
  ht_data_inmemory:
    git:
      url: https://github.com/headlines-toolkit/ht-data-inmemory.git
      # Consider adding a ref: tag for a specific commit or tag
  # You also need the base client and http client packages
  ht_data_client:
    git:
      url: https://github.com/headlines-toolkit/ht-data-client.git
  ht_http_client:
    git:
      url: https://github.com/headlines-toolkit/ht-http-client.git

# Or for development/testing only:
dev_dependencies:
  ht_data_inmemory:
    git:
      url: https://github.com/headlines-toolkit/ht-data-inmemory.git
```

Then run `dart pub get` or `flutter pub get`.

## Features

Implements the `HtDataClient<T>` interface, providing the following methods:
- `create(T item)`: Adds an item to the in-memory store. Throws `BadRequestException` if ID already exists.
- `read(String id)`: Retrieves an item by its ID. Throws `NotFoundException` if the ID doesn't exist.
- `readAll({String? startAfterId, int? limit})`: Retrieves all items, with optional pagination.
- `readAllByQuery(Map<String, dynamic> query, {String? startAfterId, int? limit})`: Retrieves items matching a simple key-value query, with optional pagination.
- `update(String id, T item)`: Updates an existing item. Throws `NotFoundException` if the ID doesn't exist or `BadRequestException` if the item's ID doesn't match the path ID.
- `delete(String id)`: Removes an item by its ID. Throws `NotFoundException` if the ID doesn't exist.

## Usage

```dart
import 'package:ht_data_inmemory/ht_data_inmemory.dart';
import 'package:ht_http_client/ht_http_client.dart' show NotFoundException; // For catching errors

// Define your data model
class MyModel {
  final String id;
  final String name;
  final int value;

  MyModel({required this.id, required this.name, required this.value});

  // Required for HtDataInMemoryClient query functionality
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
      };

  // Example factory for deserialization (not directly used by InMemory client,
  // but typically needed when working with data models)
  factory MyModel.fromJson(Map<String, dynamic> json) {
    return MyModel(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as int,
    );
  }
}

void main() async {
  // Instantiate the client (empty)
  final client = HtDataInMemoryClient<MyModel>(
    toJson: (item) => item.toJson(),
    getId: (item) => item.id,
    // Optionally provide initial data:
    // initialData: [
    //   MyModel(id: 'pre1', name: 'Preloaded 1', value: 10),
    //   MyModel(id: 'pre2', name: 'Preloaded 2', value: 20),
    // ],
  );

  // Create an item
  final newItem = MyModel(id: '1', name: 'Test Item', value: 100);
  await client.create(newItem);
  print('Created item: ${newItem.name}');

  // Read the item
  try {
    final readItem = await client.read('1');
    print('Read item: ${readItem.name}');
  } on NotFoundException catch (e) {
    print('Error reading item: ${e.message}');
  }

  // Read all items
  final allItems = await client.readAll();
  print('All items count: ${allItems.length}');

  // Query items
  final query = {'value': 100};
  final queriedItems = await client.readAllByQuery(query);
  print('Queried items count (value=100): ${queriedItems.length}');

  // Update the item
  final updatedItemData = MyModel(id: '1', name: 'Updated Test Item', value: 150);
  final updatedItem = await client.update('1', updatedItemData);
  print('Updated item name: ${updatedItem.name}');

  // Delete the item
  await client.delete('1');
  print('Deleted item with ID 1');

  // Try reading deleted item (will throw NotFoundException)
  try {
    await client.read('1');
  } on NotFoundException catch (e) {
    print('Attempted to read deleted item: ${e.message}');
  }
}
```

## License

This package is licensed under the [PolyForm Free Trial](LICENSE). Please review the terms before use.