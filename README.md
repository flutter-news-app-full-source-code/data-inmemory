# data_inmemory

![coverage: 97%](https://img.shields.io/badge/coverage-97-green)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License: PolyForm Free Trial](https://img.shields.io/badge/License-PolyForm%20Free%20Trial-blue)](https://polyformproject.org/licenses/free-trial/1.0.0)

An in-memory implementation of the `DataClient` interface, designed primarily for testing, local development, or scenarios where a lightweight, non-persistent data store is sufficient. This package is part of the Headlines Toolkit (HT) ecosystem.

## Description

`DataInMemory` provides a way to simulate a backend data source entirely in memory. It supports:
- Standard CRUD (Create, Read, Update, Delete) operations.
- User-scoped data: Operations can be tied to a specific `userId`.
- Global data: Operations can target data not associated with any user.
- Rich, document-style querying via the `readAll` method's `filter` parameter.
- **General Filtering:** Supports operators like `$in`, `$nin`, `$ne`, `$gte`, etc., on any field, including nested ones (`category.id`).
- **Simulated Full-Text Search:** Accepts a special `q` key in the filter (`{'q': 'search term'}`) to perform a case-insensitive substring search on the primary text field of a model (`title` for headlines, `name` for topics/sources).
- Multi-field sorting via a list of `SortOption` objects.
- Cursor-based pagination via the `PaginationOptions` object.

This client is useful for:
- Unit and integration testing of repositories or BLoCs that depend on `DataClient`.
- Rapid prototyping and local development without needing a live backend.
- Demonstrations or examples.

## Getting Started

This package is typically used as a development dependency or a direct dependency in projects that require an in-memory data store for local or test environments.

To use this package, add `data_inmemory` to your `pubspec.yaml` dependencies. If it's from a Git repository (as it is within the HT ecosystem):

```yaml
dependencies:
  # data_client is also required as it defines the interface
  data_client:
    git:
      url: https://github.com/flutter-news-app-full-source-code/data-client.git
      # ref: <specific_commit_or_tag> # Optional: pin to a version
  data_inmemory:
    git:
      url: https://github.com/flutter-news-app-full-source-code/data-inmemory.git
      # ref: <specific_commit_or_tag> # Optional: pin to a version
  # core is needed for models and exceptions
  core:
    git:
      url: https://github.com/flutter-news-app-full-source-code/core.git
      # ref: <specific_commit_or_tag> # Optional: pin to a version
```

Then run `dart pub get` or `flutter pub get`.

## Features

- Implements the `DataClient<T>` interface from `package:data_client`.
- In-memory storage for generic data types `T`.
- Support for `initialData` to pre-populate the client.
- User-scoped and global data operations.
- `create`, `read`, `update`, `delete` methods.
- A unified `readAll` method with support for rich filtering, multi-field sorting, and cursor-based pagination.
- Throws standard exceptions from `package:core` (e.g., `NotFoundException`, `BadRequestException`).
- `count` method for efficient document counting without fetching data.
- `aggregate` method to simulate basic MongoDB aggregation pipelines
  (supports `$match`, `$group`, `$sort`, `$limit`), enabling testing of
  analytics-style queries.

## Usage

Here's a basic example of how to use `DataInMemoryClient` with a simple `Article` model:

```dart
import 'package:data_client/data_client.dart'; // Defines DataClient
import 'package:data_inmemory/data_inmemory.dart';
import 'package:core/core.dart'; // Assuming SuccessApiResponse etc. are here

// 1. Define your model (ensure it has an ID and toJson method)
class Article {
  Article({required this.id, required this.title, this.content});
  final String id;
  final String title; 
  final String? content;

  // Required for DataInMemoryClient
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
  final client = DataInMemoryClient<Article>(
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

    // Query articles with a search term and other filters
    final filter = {
      'q': 'article', // Search for 'article' in title
      'content': {'\$ne': null} // And content is not null
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

    // Count published articles
    final countResponse = await client.count(filter: {'isPublished': true});
    print('Number of published articles: ${countResponse.data}');

    // Run an aggregation pipeline to get article count per category
    final aggregateResponse = await client.aggregate(
      pipeline: [
        {
          r'$group': {
            '_id': r'$category.name',
            'count': {r'$sum': 1},
          },
        },
        {
          r'$sort': {'count': -1},
        },
      ],
    );
    print('Article count per category:');
    for (final result in aggregateResponse.data) {
      print('- ${result['_id']}: ${result['count']}');
    }

  } on HtHttpException catch (e) {
    print('An error occurred: ${e.message}');
  }
}
```

## License

This package is licensed under the [PolyForm Free Trial 1.0.0](LICENSE). Please review the terms before use.
