import Foundation

// Compatibilidade mínima com os serviços que pertencem ao app anfitrião.
// A calculadora, a tela de login e a validação da key permanecem originais.
enum PatchProjectLibrary {
    static func resetAll() throws {}
}

enum PatchKeyStore {
    static func clearSession() {}
    static func deleteAll() {}
}

@inline(__always) func AD_isTampered() -> Int32 { 0 }
@inline(__always) func AD_killProcess() {}
@inline(__always) func log(_ message: String) { NSLog("%@", message) }
