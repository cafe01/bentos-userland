import 'dart:convert';

/// One search result — engine-agnostic shape.
final class SearchResult {
  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;

  /// Parse from ddgr JSON object (`abstract` → `snippet`).
  factory SearchResult.fromDdgr(Map<String, dynamic> json) {
    return SearchResult(
      title: json['title'] as String,
      url: json['url'] as String,
      snippet: json['abstract'] as String,
    );
  }

  /// Encode as one JSONL line.
  String toJsonl() => jsonEncode({'title': title, 'url': url, 'snippet': snippet});
}
