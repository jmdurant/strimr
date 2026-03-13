import CarPlay

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var tabBuilder: CarPlayTabBuilder?
    private var observationTask: Task<Void, Never>?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        startSessionObservation()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        observationTask?.cancel()
        observationTask = nil
        self.interfaceController = nil
        tabBuilder = nil
    }

    // MARK: - Session Observation

    private func startSessionObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let sessionManager = AppDependencies.shared.sessionManager

            while !Task.isCancelled {
                let status = sessionManager.status
                self.handleSessionStatus(status)

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = sessionManager.status
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func handleSessionStatus(_ status: SessionManager.Status) {
        guard interfaceController != nil else { return }

        switch status {
        case .ready:
            showTabBar()
        case .hydrating:
            showLoadingTemplate()
        case .signedOut, .needsProfileSelection, .needsServerSelection:
            showSignInPrompt()
        }
    }

    // MARK: - Templates

    private func showTabBar() {
        guard let interfaceController else { return }

        let deps = AppDependencies.shared
        let builder = CarPlayTabBuilder(context: deps.plexApiContext, libraryStore: deps.libraryStore)
        tabBuilder = builder

        let tabBar = builder.buildTabBar(interfaceController: interfaceController)
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    private func showLoadingTemplate() {
        guard let interfaceController else { return }
        let template = CPListTemplate(title: "Slingshot", sections: [])
        template.emptyViewSubtitleVariants = ["Loading..."]
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
    }

    private func showSignInPrompt() {
        guard let interfaceController else { return }

        let item = CPListItem(text: "Open Slingshot on iPhone to sign in", detailText: nil)
        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Slingshot", sections: [section])
        interfaceController.setRootTemplate(template, animated: true, completion: nil)
    }
}
