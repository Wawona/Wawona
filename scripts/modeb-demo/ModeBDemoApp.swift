import UIKit

@main
enum ModeBDemoMain {
  static func main() {
    if CommandLine.argc == 2, CommandLine.arguments[1] == "--wwn-jit-child" {
      exit(Int32(modeb_demo_ptrace_trace_me()))
    }
    modeb_demo_try_self_enable_jit(CommandLine.arguments[0])
    autoreleasepool {
      exit(UIApplicationMain(
        CommandLine.argc,
        CommandLine.unsafeArgv,
        nil,
        NSStringFromClass(ModeBDemoAppDelegate.self)
      ))
    }
  }
}
