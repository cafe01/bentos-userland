import "dart:io";
void main() { stderr.writeln("OBJ=${Platform.environment["GIT_OBJECT_DIRECTORY"]} DIR=${Platform.environment["GIT_DIR"]}"); }
