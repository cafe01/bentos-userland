/// Utility: parse a FunctionDefinition from a JSON file on disk.
library;

import 'dart:convert';
import 'dart:io';

import 'package:chat_inference/chat_inference.dart';

/// Loads a [FunctionDefinition] from [path].
///
/// The file must be a JSON object with string fields "name" and "description"
/// and an object field "inputSchema" (JSON Schema).
///
/// Throws [ArgumentError] if the file is not found or the shape is wrong.
/// Throws [FormatException] if the file is not valid JSON.
FunctionDefinition loadFunctionDefinitionFromFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw ArgumentError.value(path, 'path', 'file not found');
  }
  final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final name = map['name'];
  final description = map['description'];
  final inputSchema = map['inputSchema'];
  if (name is! String ||
      description is! String ||
      inputSchema is! Map<String, dynamic>) {
    throw ArgumentError.value(
      path,
      'path',
      'JSON must have string "name", string "description", and object "inputSchema"',
    );
  }
  return FunctionDefinition(
    name: name,
    description: description,
    inputSchema: inputSchema,
  );
}
