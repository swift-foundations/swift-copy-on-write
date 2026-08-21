import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CopyOnWritePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CoWMacro.self,
        CoWPropertyMacro.self,
    ]
}
