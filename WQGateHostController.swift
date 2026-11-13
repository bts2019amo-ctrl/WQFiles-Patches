import SwiftUI
import UIKit
import Security
import Foundation

@objc protocol WQGateHostControllerDelegate: AnyObject {
    func wqGateDidFinish(withGame game: String)
}

private enum WQGateStep { case calculator, login, game }
private enum WQSelectedGame: String { case normal = "free_fire", max = "free_fire_max" }

private struct WQKeyEnvelope: Decodable { let result: WQKeyResult }
private struct WQKeyResult: Decodable { let data: WQKeyData }
private struct WQKeyData: Decodable { let json: WQKeyPayload }
private struct WQKeyPayload: Decodable {
    let success: Bool?
    let valid: Bool?
    let active: Bool?
    let status: String?
    let message: String?
    let reason: String?
    let errorCode: String?
}

@MainActor
private final class WQKeySession: ObservableObject {
    @Published var checking = false
    @Published var authenticated = false
    @Published var error: String?
    private var storedKey: String?
    private let endpoint = URL(string: "https://proxysystem.org/api/trpc/proxyKeys.publicCheckKey")!
    private let service = "cz.kolbi.wqfiles.key"
    private let account = "license-key"

    init() {
        storedKey = readKey()
    }

    func submit(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { error = "Digite sua key iOS."; return }
        Task { await validate(key, save: true) }
    }

    private func validate(_ key: String, save: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let deviceID = try deviceIdentifier()
            let body: [String: Any] = ["json": ["key": key, "deviceId": deviceID]]
            let data = try JSONSerialization.data(withJSONObject: body)
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "input", value: String(data: data, encoding: .utf8))]
            let (responseData, response) = try await URLSession.shared.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let payload = try JSONDecoder().decode(WQKeyEnvelope.self, from: responseData).result.data.json
            let isActive = payload.active == true || payload.valid == true
            let accepted = payload.success == true && isActive && payload.status?.lowercased() == "active"
            guard accepted else {
                authenticated = false
                error = payload.message ?? payload.reason ?? "Chave inválida ou expirada."
                return
            }
            authenticated = true
            error = nil
            storedKey = key
            if save { writeKey(key) }
        } catch {
            if !authenticated { self.error = "Não foi possível verificar a chave. Verifique sua conexão." }
        }
    }

    private func deviceIdentifier() throws -> String {
        let serviceName = "cz.kolbi.wqfiles.device"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName, kSecAttrAccount as String: "installation-id", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) { return value }
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecReturnData as String] = nil
        item[kSecMatchLimit as String] = nil
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
        return value
    }

    private func readKey() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKey(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

private struct WQLoginView: View {
    @ObservedObject var session: WQKeySession
    @State private var key = ""
    @State private var visible = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.08, green: 0.09, blue: 0.12)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "lock.shield.fill").font(.system(size: 62)).foregroundStyle(.white)
                Text("ACESSO LICENCIADO").font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(.white.opacity(0.72))
                Text("WQ FILES").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white)
                HStack {
                    Image(systemName: "key.fill").foregroundStyle(.white.opacity(0.8))
                    Group { visible ? AnyView(TextField("Digite sua key iOS", text: $key)) : AnyView(SecureField("Digite sua key iOS", text: $key)) }
                        .textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(.white)
                    Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash.fill" : "eye.fill").foregroundStyle(.white.opacity(0.7)) }
                }
                .padding(.horizontal, 15).frame(height: 54).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16)))
                Button { session.submit(key) } label: {
                    HStack { if session.checking { ProgressView().tint(.white) }; Text(session.checking ? "VALIDANDO..." : "VALIDAR KEY").fontWeight(.bold) }
                        .frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }.disabled(session.checking)
                if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red.opacity(0.9)).multilineTextAlignment(.center) }
                Spacer()
            }.padding(24).frame(maxWidth: 440)
        }.preferredColorScheme(.dark)
    }
}

private struct WQGameSelectionView: View {
    let onContinue: (WQSelectedGame) -> Void
    @State private var selected: WQSelectedGame = .normal
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("SELECIONE SEU JOGO").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(.purple)
                    Text("Escolha a versão instalada").font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("Os patches exibidos serão referentes ao jogo selecionado.").foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        gameRow(.normal, title: "Free Fire", subtitle: "EDIÇÃO PADRÃO", image: "FreeFireNormal")
                        gameRow(.max, title: "Free Fire MAX", subtitle: "EDIÇÃO MAX", image: "FreeFireMax")
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.quaternary))
                    Button { onContinue(selected) } label: { Label("CONTINUAR", systemImage: "arrow.right").fontWeight(.bold).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(.white).background(.purple, in: RoundedRectangle(cornerRadius: 16)) }
                }.padding(22)
            }
        }
    }
    private func gameRow(_ game: WQSelectedGame, title: String, subtitle: String, image: String) -> some View {
        Button { selected = game } label: {
            HStack(spacing: 14) {
                WQBundleImage(name: image).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: selected == game ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(selected == game ? .purple : .secondary)
            }.padding(12).background(selected == game ? Color.purple.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

private struct WQBundleImage: View {
    let name: String
    var body: some View {
        if let path = Bundle.main.path(forResource: name, ofType: "jpg"), let image = UIImage(contentsOfFile: path) { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "gamecontroller.fill").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(.gray.opacity(0.2)) }
    }
}

private struct WQGateFlowView: View {
    let onFinish: (String) -> Void
    @State private var step: WQGateStep = .calculator
    @State private var selectedGame = WQSelectedGame.normal
    @StateObject private var keySession = WQKeySession()
    var body: some View {
        Group {
            switch step {
            case .calculator: CalculadoraIPhoneView { withAnimation { step = .login } }
            case .login: WQLoginView(session: keySession).onChange(of: keySession.authenticated) { ok in if ok { withAnimation { step = .game } } }
            case .game: WQGameSelectionView { game in selectedGame = game; onFinish(game.rawValue) }
            }
        }.preferredColorScheme(.dark)
    }
}

@objc(WQGateHostController)
final class WQGateHostController: UIViewController {
    @objc weak var delegate: WQGateHostControllerDelegate?
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: WQGateFlowView { [weak self] game in
            self?.delegate?.wqGateDidFinish(withGame: game)
        })
        addChild(host); host.view.frame = view.bounds; host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(host.view); host.didMove(toParent: self)
    }
}
