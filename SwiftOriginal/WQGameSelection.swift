import SwiftUI
import UIKit

private enum WQGame: String {
    case normal
    case max
}

private struct WQGameSelectionView: View {
    let onContinue: () -> Void
    @State private var selectedGame: WQGame = .normal
    @State private var pressed = false

    var body: some View {
        ZStack {
            ParticleFieldBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("SELECIONE SEU JOGO")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.82))
                        Text("Escolha a versão instalada")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.4)
                            .foregroundStyle(.white)
                        Text("Os patches exibidos serão referentes ao jogo selecionado.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(.top, 38)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("VERSÃO DO JOGO")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundStyle(.white.opacity(0.82))
                                Text("Selecione uma opção")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.56))
                            }
                            Spacer()
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.bottom, 3)

                        WQGameRow(title: "Free Fire", subtitle: "EDIÇÃO PADRÃO", image: "FreeFireNormal", selected: selectedGame == .normal) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedGame = .normal }
                        }
                        WQGameRow(title: "Free Fire MAX", subtitle: "EDIÇÃO MAX", image: "FreeFireMax", selected: selectedGame == .max) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedGame = .max }
                        }
                    }
                    .padding(16)
                    .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1))

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { pressed = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { pressed = false }
                            UserDefaults.standard.set(selectedGame.rawValue, forKey: "WQSelectedGame")
                            onContinue()
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Text("CONTINUAR")
                                .font(.subheadline.weight(.heavy))
                                .tracking(0.7)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.20), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(pressed ? 0.96 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct WQGameRow: View {
    let title: String
    let subtitle: String
    let image: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(subtitle)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
                ZStack {
                    Circle().stroke(selected ? .white.opacity(0.92) : .white.opacity(0.28), lineWidth: 1.5).frame(width: 21, height: 21)
                    if selected { Circle().fill(.white.opacity(0.92)).frame(width: 11, height: 11) }
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 74)
            .background(selected ? .white.opacity(0.13) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? .white.opacity(0.60) : .white.opacity(0.13), lineWidth: selected ? 1.3 : 1))
        }
        .buttonStyle(.plain)
    }
}

@objc(WQGameSelectionViewController)
final class WQGameSelectionViewController: UIViewController {
    @objc var onGameSelected: (() -> Void)?
    private var host: UIHostingController<WQGameSelectionView>?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = WQGameSelectionView { [weak self] in self?.onGameSelected?() }
        let controller = UIHostingController(rootView: root)
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear
        view.backgroundColor = .clear
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        controller.didMove(toParent: self)
        host = controller
    }
}
