import SwiftUI
import UIKit

private struct WQOriginalEntryView: View {
    let onAuthenticated: () -> Void
    @State private var hasEnteredApp = false

    var body: some View {
        Group {
            if hasEnteredApp {
                WQDeferredLoginView(onAuthenticated: onAuthenticated)
            } else {
                CalculadoraIPhoneView {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        hasEnteredApp = true
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct WQDeferredLoginView: View {
    let onAuthenticated: () -> Void
    @State private var session: IOSKeySession?
    @State private var didNotifyAuthentication = false

    var body: some View {
        Group {
            if let session {
                IOSKeyLoginView(session: session)
                    // Observe the object's Published value, not the optional reference.
                    .onReceive(session.$isAuthenticated.removeDuplicates()) { authenticated in
                        guard authenticated, !didNotifyAuthentication else { return }
                        didNotifyAuthentication = true
                        onAuthenticated()
                    }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            // The session is created only after the calculator has been released.
            guard session == nil else { return }
            let created = IOSKeySession()
            created.passCalculatorGate()
            session = created
        }
    }
}

@objc(WQSwiftEntryViewController)
final class WQSwiftEntryViewController: UIViewController {
    @objc var onAuthenticated: (() -> Void)?
    private var host: UIHostingController<WQOriginalEntryView>?

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
