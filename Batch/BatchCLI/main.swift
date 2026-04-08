import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let runner = BatchCommandRunner()
let exitCode = runner.run(arguments: Array(CommandLine.arguments.dropFirst()))
if exitCode != 0 {
    exit(Int32(exitCode))
}
