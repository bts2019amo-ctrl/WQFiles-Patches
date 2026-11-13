import SwiftUI
import UIKit

private struct WQOriginalEntryView: View {
    let onAuthenticated: () -> Void
    @State private var hasEnteredApp = false
    @State private var keySession: IOSKeySession?

    var body: some View {
        Group {
            if hasEnteredApp {
                if let keySession {
                    if keySession.isAuthenticated {
                        Color.black
                            .onAppear { onAuthenticated() }
                    } else {
                        IOSKeyLoginView(session: keySession)
                    }
                } else {
                    ProgressView()
                }
            } else {
                CalculadoraIPhoneView {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        hasEnteredApp = true
                        let session = IOSKeySession()
                        session.passCalculatorGate()
                        keySession = session
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

@objc(WQSwiftEntryViewController)
final class WQSwiftEntryViewController: UIViewController {
    @objc var onAuthenticated: (() -> Void)?
    private var host: UIHostingController<WQOriginalEntryView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = WQOriginalEntryView { [weak self] in
            self?.onAuthenticated?()
        }
        let controller = UIHostingController(rootView: root)
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
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

@objc(WQParticleBackgroundView)
final class WQParticleBackgroundView: UIView {
    private var host: UIHostingController<ParticleFieldBackground>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let controller = UIHostingController(rootView: ParticleFieldBackground())
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear
        addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        host = controller
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
