/// Support for doing something awesome.
///
/// More dartdocs go here.
library terminal;

import 'dart:async';
import 'dart:io';

import 'package:pubspec2/pubspec2.dart';

/// A [CommandLineAgent] with additional behavior for managing a 'Dart package' directory.
class ProjectAgent extends CommandLineAgent {
  /// Creates a new package and terminal on that package's working directory.
  ///
  /// Make sure to call [tearDownAll] in your test's method of the same name to
  /// delete the [projectsDirectory] ]where the package is written to. ('$PWD/tmp')
  ///
  /// Both [dependencies] and [devDependencies] are a valid dependency map,
  /// e.g. `{"aqueduct": "^3.0.0"}` or `{"relative" : {"path" : "../"}}`
  ProjectAgent(this.name,
      {Map<String, dynamic> dependencies = const {},
      Map<String, dynamic> devDependencies = const {}})
      : super(Directory.fromUri(projectsDirectory.uri.resolve("$name/"))) {
    if (!projectsDirectory.existsSync()) {
      projectsDirectory.createSync();
    }
    workingDirectory.createSync(recursive: true);

    final libDir = Directory.fromUri(workingDirectory.uri.resolve("lib/"));
    libDir.createSync(recursive: true);

    addOrReplaceFile("analysis_options.yaml", _analysisOptionsContents);
    addOrReplaceFile(
        "pubspec.yaml", _pubspecContents(name, dependencies, devDependencies));
    addOrReplaceFile("lib/$name.dart", "");
  }

  ProjectAgent.existing(Uri uri) : super(Directory.fromUri(uri)) {
    final pubspecFile =
        File.fromUri(workingDirectory.uri.resolve("pubspec.yaml"));
    if (!pubspecFile.existsSync()) {
      throw ArgumentError(
          "the uri '$uri' is not a Dart project directory; does not contain pubspec.yaml");
    }

    final pubspec = PubSpec.fromYamlString(pubspecFile.readAsStringSync());
    name = pubspec.name!;
  }

  /// Temporary directory where projects are stored ('$PWD/tmp')
  static Directory get projectsDirectory =>
      Directory.fromUri(Directory.current.uri.resolve("tmp/"));

  /// Name of this project
  late String name;

  /// Directory of lib/ in project
  Directory get libraryDirectory {
    return Directory.fromUri(workingDirectory.uri.resolve("lib/"));
  }

  /// Directory of test/ in project
  Directory get testDirectory {
    return Directory.fromUri(workingDirectory.uri.resolve("test/"));
  }

  /// Directory of lib/src/ in project
  Directory get srcDirectory {
    return Directory.fromUri(
        workingDirectory.uri.resolve("lib/").resolve("src/"));
  }

  /// Deletes [projectsDirectory]. Call after tests are complete
  static void tearDownAll() {
    try {
      projectsDirectory.deleteSync(recursive: true);
    } catch (_) {}
  }

  String _analysisOptionsContents = """analyzer:
  strong-mode:
    implicit-casts: false
""";

  static String _asYaml(Map<String, dynamic> m, {int indent = 0}) {
    final buf = StringBuffer();

    final indentBuffer = StringBuffer();
    for (var i = 0; i < indent; i++) {
      indentBuffer.write("  ");
    }
    final indentString = indentBuffer.toString();

    m.forEach((k, v) {
      buf.write("$indentString$k: ");
      if (v is String) {
        buf.writeln("$v");
      } else if (v is Map<String, dynamic>) {
        buf.writeln();
        buf.write(_asYaml(v, indent: indent + 1));
      }
    });

    return buf.toString();
  }

  String _pubspecContents(
      String name, Map<String, dynamic> deps, Map<String, dynamic> devDeps,
      {bool nullsafe = true}) {
    return """
name: $name
description: desc
version: 0.0.1

environment:
  sdk: ">=2.${nullsafe ? "12" : "0"}.0 <3.0.0"

dependencies:
${_asYaml(deps, indent: 1)}

dev_dependencies:
${_asYaml(devDeps, indent: 1)}    
""";
  }

  /// Creates a new $name.dart file in lib/src/
  ///
  /// Imports the library file for this terminal.
  void addSourceFile(String fileName, String contents, {bool export = true}) {
    addOrReplaceFile("lib/src/$fileName.dart", """
import 'package:$name/$name.dart';

$contents
  """);

    addLibraryExport("src/$fileName.dart");
  }

  /// Creates a new $name.dart file in lib/
  ///
  /// Imports the library file for this terminal.
  void addLibraryFile(String fileName, String contents, {bool export = true}) {
    addOrReplaceFile("lib/$fileName.dart", """
import 'package:$name/$name.dart';

$contents
  """);

    addLibraryExport("$fileName.dart");
  }

  /// Adds [exportUri] as an export to the main library file of this project.
  ///
  /// e.g. `addLibraryExport('package:aqueduct/aqueduct.dart')
  void addLibraryExport(String exportUri) {
    modifyFile("lib/$name.dart", (c) {
      return "export '$exportUri';\n$c";
    });
  }
}

/// A utility for manipulating files and directories in [workingDirectory].
class CommandLineAgent {
  CommandLineAgent(this.workingDirectory, {bool create = true}) {
    if (create) {
      workingDirectory.createSync(recursive: true);
    }
  }

  CommandLineAgent.current() : this(Directory.current);

  final Directory workingDirectory;

  static void copyDirectory({required Uri src, required Uri dst}) {
    final srcDir = Directory.fromUri(src);
    final dstDir = Directory.fromUri(dst);
    if (!dstDir.existsSync()) {
      dstDir.createSync(recursive: true);
    }

    srcDir.listSync().forEach((fse) {
      if (fse is File) {
        final outPath = dstDir.uri
            .resolve(fse.uri.pathSegments.last)
            .toFilePath(windows: Platform.isWindows);
        fse.copySync(outPath);
      } else if (fse is Directory) {
        final segments = fse.uri.pathSegments;
        final outPath = dstDir.uri.resolve(segments[segments.length - 2]);
        copyDirectory(src: fse.uri, dst: outPath);
      }
    });
  }

  /// Adds or replaces file in this terminal's working directory
  ///
  /// [path] is relative path to file e.g. "lib/src/file.dart"
  /// [contents] is the string contents of the file
  /// [imports] are import uri strings, e.g. 'package:aqueduct/aqueduct.dart' (don't use quotes)
  void addOrReplaceFile(String path, String contents,
      {List<String> imports = const []}) {
    final pathComponents = path.split("/");

    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);

    final uri = relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/"));

    final directory = Directory.fromUri(uri);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    final directives = imports.map((i) => "import '$i';").join("\n");
    file.writeAsStringSync("$directives\n$contents");
  }

/*
Path Components: [analysis_options.yaml]
Relative: []
Uri: file:///C:/projects/dart-test-terminal/tmp/test_project/

Path Components: [pubspec.yaml]
Relative: []
Uri: file:///C:/projects/dart-test-terminal/tmp/test_project/

Path Components: [, C:, projects, dart-test-terminal, tmp, test_project, lib, test_project.dart]
Relative: [, C:, projects, dart-test-terminal, tmp, test_project, lib]
Uri: c:/projects/dart-test-terminal/tmp/test_project/lib/

 */

  /*
  Unsupported operation: Cannot extract a file path from a c URI
  dart:io                                                    new Directory.fromUri
  package:command_line_agent/command_line_agent.dart 209:33  CommandLineAgent.addOrReplaceFile
  package:command_line_agent/command_line_agent.dart 35:5    new ProjectAgent
  test\project_agent_test.dart 6:19
 */

  /// Updates the contents of an existing file
  ///
  /// [path] is relative path to file e.g. "lib/src/file.dart"
  /// [contents] is a function that takes the current contents of the file and returns
  /// the modified contents of the file
  void modifyFile(String path, String contents(String current)) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);
    final directory = Directory.fromUri(relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/")));
    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    if (!file.existsSync()) {
      throw ArgumentError("File at '${file.uri}' doesn't exist.");
    }

    final output = contents(file.readAsStringSync());
    file.writeAsStringSync(output);
  }

  File? getFile(String path) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);
    final directory = Directory.fromUri(relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/")));
    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    if (!file.existsSync()) {
      return null;
    }
    return file;
  }

  Future<ProcessResult> getDependencies({bool offline = true}) async {
    var args = ["get"];
    if (offline) {
      args.add("--offline");
    }

    final cmd = Platform.isWindows ? "pub.bat" : "pub";
    var result = await Process.run(cmd, args,
            workingDirectory: workingDirectory.absolute.path, runInShell: true)
        .timeout(const Duration(seconds: 45));

    if (result.exitCode != 0) {
      throw Exception("${result.stderr}");
    }

    return result;
  }
}
