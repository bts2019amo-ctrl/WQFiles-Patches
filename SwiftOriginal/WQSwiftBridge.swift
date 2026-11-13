import SwiftUI
import UIKit

private struct WQOriginalEntryView: View {
    let onAuthenticated: () -> Void
    @State private var hasEnteredApp = false
    @StateObject private var keySession = IOSKeySession()

    var body: some View {
        Group {
            if hasEnteredApp {
                if keySession.isAuthenticated {
                    Color.black
                        .onAppear { onAuthenticated() }
                } else {
                    IOSKeyLoginView(session: keySession)
                }
            } else {
                CalculadoraIPhoneView {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        hasEnteredApp = true
                        keySession.passCalculatorGate()
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
