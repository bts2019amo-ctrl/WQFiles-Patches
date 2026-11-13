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

    func restoreIfAvailable() {
        guard !authenticated, !checking, let key = storedKey, !key.isEmpty else { return }
        Task { await validate(key, save: false) }
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

private struct WQSwiftParticleBackground: View {
    private let points: [(CGFloat, CGFloat)] = [
        (0.03, 0.13), (0.17, 0.74), (0.31, 0.42), (0.46, 0.88), (0.62, 0.22), (0.79, 0.61),
        (0.91, 0.35), (0.11, 0.28), (0.25, 0.96), (0.39, 0.57), (0.54, 0.08), (0.68, 0.77),
        (0.84, 0.48), (0.97, 0.91), (0.07, 0.52), (0.21, 0.19), (0.36, 0.69), (0.50, 0.34),
        (0.65, 0.93), (0.73, 0.14), (0.88, 0.82), (0.14, 0.87), (0.44, 0.16), (0.57, 0.54)
    ]
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let light = UserDefaults.standard.string(forKey: "WQAppearanceMode") == "light"
                let color = (light ? Color.black : Color.white).opacity(0.15)
                for (index, point) in points.enumerated() {
                    let y = ((point.1 * size.height) + CGFloat(t.truncatingRemainder(dividingBy: 18.0)) * CGFloat(2 + index % 3)).truncatingRemainder(dividingBy: size.height)
                    let radius: CGFloat = UserDefaults.standard.string(forKey: "WQParticleStyleName") == "embers" ? 2.2 : 1.5
                    context.fill(Path(ellipseIn: CGRect(x: point.0 * size.width - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct WQLoginView: View {
    @ObservedObject var session: WQKeySession
    @State private var key = ""
    @AppStorage("WQLanguageCode") private var language = "pt-BR"
    @State private var visible = false
    private var accent: Color {
        switch UserDefaults.standard.string(forKey: "WQAccentColorName") {
        case "purple": return .purple
        case "teal": return .teal
        case "orange": return .orange
        case "pink": return .pink
        case "mint": return .mint
        case "indigo": return .indigo
        case "red": return .red
        case "yellow": return .yellow
        default: return .blue
        }
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.08, green: 0.09, blue: 0.12)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            WQSwiftParticleBackground()
            VStack(spacing: 18) {
                Spacer()
                if let path = Bundle.main.path(forResource: "ExternalSystemLogin", ofType: "png"), let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 28)).overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.22), lineWidth: 1))
                }
                Text(language == "en" ? "LICENSED ACCESS" : language == "ja" ? "ライセンスアクセス" : "ACESSO LICENCIADO").font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(.white.opacity(0.72))
                Text("EXTERNAL SYSTEM").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white)
                HStack {
                    Image(systemName: "key.fill").foregroundStyle(.white.opacity(0.8))
                    Group { visible ? AnyView(TextField(language == "en" ? "Enter your iOS key" : language == "ja" ? "iOSキーを入力" : "Digite sua key iOS", text: $key)) : AnyView(SecureField(language == "en" ? "Enter your iOS key" : language == "ja" ? "iOSキーを入力" : "Digite sua key iOS", text: $key)) }
                        .textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(.white)
                    Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash.fill" : "eye.fill").foregroundStyle(.white.opacity(0.7)) }
                }
                .padding(.horizontal, 15).frame(height: 54).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16)))
            Button { session.submit(key) } label: {
                    HStack { if session.checking { ProgressView().tint(.white) }; Text(session.checking ? (language == "en" ? "VALIDATING..." : language == "ja" ? "確認中..." : "VALIDANDO...") : (language == "en" ? "VALIDATE KEY" : language == "ja" ? "キーを確認" : "VALIDAR KEY")).fontWeight(.bold) }
                        .frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 14))
                }.disabled(session.checking).task { session.restoreIfAvailable() }
                Picker(language == "en" ? "Language" : language == "ja" ? "言語" : "Idioma", selection: $language) {
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                    Text("Português (Portugal)").tag("pt-PT")
                }.pickerStyle(.menu).tint(.white).frame(maxWidth: .infinity, alignment: .center)
                if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red.opacity(0.9)).multilineTextAlignment(.center) }
                Spacer()
            }.padding(24).frame(maxWidth: 440)
        }.preferredColorScheme(.dark)
    }
}

private struct WQGameSelectionView: View {
    let onContinue: (WQSelectedGame) -> Void
    @AppStorage("WQLanguageCode") private var language = "pt-BR"
    @State private var selected: WQSelectedGame = .normal
    private var accent: Color {
        switch UserDefaults.standard.string(forKey: "WQAccentColorName") {
        case "purple": return .purple
        case "teal": return .teal
        case "orange": return .orange
        case "pink": return .pink
        case "mint": return .mint
        case "indigo": return .indigo
        case "red": return .red
        case "yellow": return .yellow
        default: return .blue
        }
    }
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            WQSwiftParticleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(language == "en" ? "SELECT YOUR GAME" : language == "ja" ? "ゲームを選択" : "SELECIONE SEU JOGO").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(accent)
                    Text(language == "en" ? "Choose the installed version" : language == "ja" ? "インストール済みのバージョンを選択" : "Escolha a versão instalada").font(.system(size: 29, weight: .bold, design: .rounded))
                    Text(language == "en" ? "Displayed patches match the selected game." : language == "ja" ? "表示されるパッチは選択したゲームに対応します。" : "Os patches exibidos serão referentes ao jogo selecionado.").foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        gameRow(.normal, title: "Free Fire", subtitle: language == "en" ? "STANDARD EDITION" : language == "ja" ? "通常版" : "EDIÇÃO PADRÃO", image: "FreeFireNormal")
                        gameRow(.max, title: "Free Fire MAX", subtitle: language == "en" ? "MAX EDITION" : language == "ja" ? "MAX版" : "EDIÇÃO MAX", image: "FreeFireMax")
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.quaternary))
                    Button { onContinue(selected) } label: { Label(language == "en" ? "CONTINUE" : language == "ja" ? "続ける" : "CONTINUAR", systemImage: "arrow.right").fontWeight(.bold).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 16)) }
                }.padding(22)
            }
        }
    }
    private func gameRow(_ game: WQSelectedGame, title: String, subtitle: String, image: String) -> some View {
        Button { selected = game } label: {
            HStack(spacing: 14) {
                WQBundleImage(name: image).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: selected == game ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(selected == game ? accent : .secondary)
            }.padding(12).background(selected == game ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
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
