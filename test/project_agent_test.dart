import 'package:test/test.dart';
import 'package:command_line_agent/command_line_agent.dart';

void main() {
  test("Create agent", () {
    final agent = ProjectAgent("test_project");
    print(agent.workingDirectory);
  });
}
