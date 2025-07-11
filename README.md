# ht_data_inmemory

![coverage: xx%](https://img.shields.io/badge/coverage-100-green)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License: PolyForm Free Trial](https://img.shields.io/badge/License-PolyForm%20Free%20Trial-blue)](https://polyformproject.org/licenses/free-trial/1.0.0)

An in-memory implementation of the `HtDataClient` interface, designed primarily for testing, local development, or scenarios where a lightweight, non-persistent data store is sufficient. This package is part of the Headlines Toolkit (HT) ecosystem.

## Description

`HtDataInMemory` provides a way to simulate a backend data source entirely in memory. It supports:
- Standard CRUD (Create, Read, Update, Delete) operations.
- User-scoped data: Operations can be tied to a specific `userId`.
- Global data: Operations can target data not associated with any user.
- Rich, document-style querying via the `readAll` method's `filter` parameter, which supports:
    - Filtering on nested object properties using dot-notation (e.g., `category.id`).
    - Operators like `$in`, `$nin`, `$ne`, `$gte`, `$gt`, `$lte`, and `$lt`.
- Multi-field sorting via a list of `SortOption` objects.
- Cursor-based pagination via the `PaginationOptions` object.

This client is useful for:
- Unit and integration testing of repositories or BLoCs that depend on `HtDataClient`.
- Rapid prototyping and local development without needing a live backend.
- Demonstrations or examples.

## Getting Started

This package is typically used as a development dependency or a direct dependency in projects that require an in-memory data store for local or test environments.

To use this package, add `ht_data_inmemory` to your `pubspec.yaml` dependencies. If it's from a Git repository (as it is within the HT ecosystem):

```yaml
dependencies:
  # ht_data_client is also required as it defines the interface
  ht_data_client:
    git:
      url: https://github.com/headlines-toolkit/ht-data-client.git
      # ref: <specific_commit_or_tag> # Optional: pin to a version
  ht_data_inmemory:
    git:
      url: https://github.com/headlines-toolkit/ht-data-inmemory.git
      # ref: <specific_commit_or_tag> # Optional: pin to a version
  # ht_shared is needed for models and exceptions
  ht_shared:
    git:
      url: https://github.com/headlines-toolkit/ht-shared.git
      # ref: <specific_commit_or_tag> # Optional: pin to a version
```

Then run `dart pub get` or `flutter pub get`.

## Features

- Implements the `HtDataClient<T>` interface from `package:ht_data_client`.
- In-memory storage for generic data types `T`.
- Support for `initialData` to pre-populate the client.
- User-scoped and global data operations.
- `create`, `read`, `update`, `delete` methods.
- A unified `readAll` method with support for rich filtering, multi-field sorting, and cursor-based pagination.
- Throws standard exceptions from `package:ht_shared` (e.g., `NotFoundException`, `BadRequestException`).

## Usage

Here's a basic example of how to use `HtDataInMemoryClient` with a simple `Article` model:

```dart
import 'package:ht_data_client/ht_data_client.dart'; // Defines HtDataClient
import 'package:ht_data_inmemory/ht_data_inmemory.dart';
import 'package:ht_shared/ht_shared.dart'; // Assuming SuccessApiResponse etc. are here

// 1. Define your model (ensure it has an ID and toJson method)
class Article {
  Article({required this.id, required this.title, this.content});
  final String id;
  final String title; 
  final String? content;

  // Required for HtDataInMemoryClient
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        // Add other fields for querying
        if (content != null) 'content': content,
      };
  
  // For easy comparison in examples/tests
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Article &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          content == other.content;

  @override
  int get hashCode => id.hashCode ^ title.hashCode ^ content.hashCode;
}

void main() async {
  // 2. Define helper functions for the client
  String getArticleId(Article article) => article.id;
  Map<String, dynamic> articleToJson(Article article) => article.toJson();

  // 3. Instantiate the client
  final client = HtDataInMemoryClient<Article>(
    getId: getArticleId,
    toJson: articleToJson,
    initialData: [
      Article(id: 'article1', title: 'First Article', content: 'Hello world!'),
    ],
  );

  // 4. Use the client
  try {
    // Create a new article
    final newArticle = Article(id: 'article2', title: 'Second Article');
    SuccessApiResponse<Article> createResponse =
        await client.create(item: newArticle);
    print('Created: ${createResponse.data.title}');

    // Read an article
    SuccessApiResponse<Article> readResponse =
        await client.read(id: 'article1');
    print('Read: ${readResponse.data.title}');

    // Query articles with filter, sort, and pagination
    final filter = {
      'title': {'\$ne': 'Some Other Title'} // Not equal to
    };
    final sort = [const SortOption('title', SortOrder.desc)];
    final pagination = const PaginationOptions(limit: 5);

    final queryResponse = await client.readAll(
      filter: filter,
      sort: sort,
      pagination: pagination,
    );

    print('Found ${queryResponse.data.items.length} sorted articles matching query:');
    for (final article in queryResponse.data.items) {
      print('- ${article.title}');
    }
    print('Has more pages: ${queryResponse.data.hasMore}');

  } on HtHttpException catch (e) {
    print('An error occurred: ${e.message}');
  }
}
```

## License

This package is licensed under the [PolyForm Free Trial 1.0.0](LICENSE). Please review the terms before use.
