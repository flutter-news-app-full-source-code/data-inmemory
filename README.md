<div align="center">
  <img src="https://avatars.githubusercontent.com/u/202675624?s=400&u=dc72a2b53e8158956a3b672f8e52e39394b6b610&v=4" alt="Flutter News App Toolkit Logo" width="220">
  <h1>Data In-Memory</h1>
  <p><strong>An in-memory implementation of the `DataClient` interface for the Flutter News App Toolkit.</strong></p>
</div>

<p align="center">
  <img src="https://img.shields.io/badge/coverage-96%25-green?style=for-the-badge" alt="coverage">
  <a href="https://flutter-news-app-full-source-code.github.io/docs/"><img src="https://img.shields.io/badge/LIVE_DOCS-VIEW-slategray?style=for-the-badge" alt="Live Docs: View"></a>
  <a href="https://github.com/flutter-news-app-full-source-code"><img src="https://img.shields.io/badge/MAIN_PROJECT-BROWSE-purple?style=for-the-badge" alt="Main Project: Browse"></a>
</p>

This `data_inmemory` package provides a lightweight, non-persistent in-memory implementation of the `DataClient` interface within the [**Flutter News App Full Source Code Toolkit**](https://github.com/flutter-news-app-full-source-code). It is designed primarily for testing, local development, or scenarios where a temporary data store is sufficient. This package allows for simulating a backend data source entirely in memory, supporting standard CRUD operations, advanced querying, and aggregation capabilities without requiring a live database connection.

## ⭐ Feature Showcase: Flexible In-Memory Data Management

This package offers a comprehensive set of features for managing data entities in memory.

<details>
<summary><strong>🧱 Core Functionality</strong></summary>

### 🚀 `DataClient` Implementation
- **`DataInMemoryClient<T>` Class:** A concrete in-memory implementation of the `DataClient<T>` interface, enabling type-safe interactions with various data models.
- **Flexible Initialization:** Supports `initialData` to pre-populate the client with existing data, accelerating setup for testing and development.

### 🌐 Comprehensive Data Operations
- **CRUD Operations:** Implements `create`, `read`, `update`, and `delete` methods for standard data manipulation.
- **User-Scoped & Global Data:** Supports operations tied to a specific `userId` for user-scoped data, as well as operations targeting global data not associated with any user.
- **Rich Document-Style Querying:** The `readAll` method supports advanced filtering with operators like `$in`, `$nin`, `$ne`, `$gte` on any field (including nested ones), multi-field sorting via `SortOption` objects, and cursor-based pagination via `PaginationOptions`.
- **Generic Text Search:** Supports the `$regex` operator for powerful, case-insensitive text searches on any string field (e.g., `{'name': {'$regex': 'term', '$options': 'i'}}`).
- **Efficient Counting & Aggregation:** Includes a `count` method for efficient document counting and an `aggregate` method to simulate basic MongoDB aggregation pipelines (supporting `$match`, `$group`, `$sort`, `$limit`), enabling testing of analytics-style queries.

### 🛡️ Standardized Error Handling
- **`HttpException` Propagation:** Throws standard exceptions from `package:core` (e.g., `NotFoundException`, `BadRequestException`) for consistent error handling, ensuring predictable error management across the application layers.

> **💡 Your Advantage:** You get a meticulously designed, production-quality in-memory data client that simplifies testing, accelerates local development, and provides robust data management capabilities without the overhead of a persistent backend. This package is ideal for rapid prototyping and reliable unit/integration testing.

</details>

## 🔑 Licensing

This source code is licensed for commercial use and is provided for local evaluation. A **Lifetime Commercial License** is required for any production or public-facing application.

Please visit the main [Flutter News App Full Source Code Toolkit](https://github.com/flutter-news-app-full-source-code) organization page to review the full license terms and to purchase.

