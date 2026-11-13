import Foundation
import SwiftUI
import UIKit
import Darwin

struct IOSKeyLoginView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var session: IOSKeySession
    @State private var key = ""
    @State private var isKeyVisible = false
    @State private var appeared = false
    @State private var clipboardHint: String?
    @State private var vpnAddress: String?
    @State private var vpnDetectionMessage = "O IP detectado é apenas informativo."
    private let accent = Color(red: 0.70, green: 0.72, blue: 0.74)

    private func checkClipboard() {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty, clip.count >= 8, clip.count <= 128 else {
            clipboardHint = nil
            return
        }
        clipboardHint = key.isEmpty ? clip : nil
    }

    private func pasteFromClipboard() {
        if let hint = clipboardHint {
            key = hint
            clipboardHint = nil
        }
    }

    private var trimmedKeyIsEmpty: Bool {
        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func detectVPNAddress() {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            vpnAddress = nil
            vpnDetectionMessage = "Não foi possível consultar as interfaces de rede."
            return
        }
        defer { freeifaddrs(first) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let entry = interface.pointee
            current = entry.ifa_next
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp"),
                  let socketAddress = entry.ifa_addr,
                  socketAddress.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let ipv4 = UnsafeRawPointer(socketAddress).assumingMemoryBound(to: sockaddr_in.self).pointee
            var address = ipv4.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let value = String(cString: buffer)
            guard value != "0.0.0.0" else { continue }
            vpnAddress = value
            vpnDetectionMessage = "IP local encontrado; não é enviado na validação da key."
            return
        }

        vpnAddress = nil
        vpnDetectionMessage = "Nenhuma interface VPN IPv4 ativa foi encontrada."
    }

    var body: some View {
        ZStack {
            ParticleFieldBackground()

            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 24)
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(accent.opacity(0.10))
                                    .frame(width: 82, height: 82)
                                    .overlay(Circle().stroke(accent.opacity(0.26), lineWidth: 1))
                                AppLogo(size: 54)
                                    .shadow(color: accent.opacity(0.18), radius: 16, y: 4)
                            }
                            VStack(spacing: 6) {
                                Text("ACESSO LICENCIADO")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .tracking(1.6)
                                    .foregroundStyle(accent)
                                Text("EXTERNAL X")
                                    .font(.system(size: 27, weight: .black, design: .rounded))
                                    .tracking(2.1)
                                    .foregroundStyle(.white)
                                    .accessibilityAddTraits(.isHeader)
                                Text("Informe sua key para continuar.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.62))
                                    .multilineTextAlignment(.center)
                            }
                        }

                        VStack(alignment: .leading, spacing: 15) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("KEY DE LICENÇA")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(.white.opacity(0.72))
                                HStack(spacing: 11) {
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(accent)
                                        .frame(width: 22)
                                    Group {
                                        if isKeyVisible {
                                            TextField("Digite sua key iOS", text: $key)
                                        } else {
                                            SecureField("Digite sua key iOS", text: $key)
                                        }
                                    }
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white)
                                    .tint(accent)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.go)
                                    .onSubmit { session.submit(key) }
                                    .accessibilityLabel("Key iOS")
                                    Button { isKeyVisible.toggle() } label: {
                                        Image(systemName: isKeyVisible ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.68))
                                            .frame(minWidth: 36, minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isKeyVisible ? "Ocultar key" : "Mostrar key")
                                }
                                .padding(.horizontal, 13)
                                .frame(minHeight: 54)
                                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("IP DA VPN")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(.white.opacity(0.72))
                                HStack(spacing: 10) {
                                    Image(systemName: "network")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(accent)
                                    Text(vpnAddress ?? "Toque para detectar o IP da VPN")
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(vpnAddress == nil ? .white.opacity(0.48) : .white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Spacer(minLength: 4)
                                    Button(action: detectVPNAddress) {
                                        Text("DETECTAR IP DA KEY")
                                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                                            .tracking(0.25)
                                            .foregroundStyle(accent)
                                            .padding(.horizontal, 10)
                                            .frame(minHeight: 38)
                                            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 52)
                                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
                                Text(vpnDetectionMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.48))
                            }

                            if let hint = clipboardHint {
                                Button(action: pasteFromClipboard) {
                                    HStack(spacing: 9) {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Colar key da área de transferência")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer(minLength: 0)
                                        Text(String(hint.prefix(8)) + "…")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.white.opacity(0.50))
                                    }
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 42)
                                    .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            Button { session.submit(key) } label: {
                                HStack(spacing: 9) {
                                    if session.isChecking { ProgressView().tint(.black) }
                                    Text(session.isChecking ? "Verificando…" : "Entrar")
                                        .font(.headline.weight(.bold))
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: accent.opacity(0.16), radius: 14, y: 5)
                            }
                            .buttonStyle(.plain)
                            .disabled(session.isChecking || trimmedKeyIsEmpty)
                            .opacity(session.isChecking || trimmedKeyIsEmpty ? 0.58 : 1)

                            if let error = session.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color(red: 1, green: 0.53, blue: 0.58))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 420)
                        .background(Color(red: 0.055, green: 0.055, blue: 0.055).opacity(0.94), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, minHeight: 0)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.84)) { appeared = true }
            checkClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in checkClipboard() }
    }
}
