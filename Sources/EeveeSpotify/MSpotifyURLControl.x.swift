import Foundation
import ObjectiveC.runtime
import UIKit

private final class MSpotifyURLControl: NSObject {
    static let shared = MSpotifyURLControl()
    private var pendingCommand: String?
    private var attempts = 0
    private var installedApplicationClass: AnyClass?
    private var installedSceneClass: AnyClass?

    func activate() {
        NotificationCenter.default.addObserver(self, selector: #selector(installHooks), name: UIApplication.didFinishLaunchingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(installHooks), name: UIApplication.didBecomeActiveNotification, object: nil)
        DispatchQueue.main.async { [weak self] in self?.installHooks() }
    }

    @objc private func installHooks() {
        if let delegate = UIApplication.shared.delegate {
            let cls: AnyClass = object_getClass(delegate)!
            if installedApplicationClass == nil {
                install(on: cls,
                        original: NSSelectorFromString("application:openURL:options:"),
                        replacement: #selector(MSpotifyURLControl.eevee_application(_:open:options:)))
                installedApplicationClass = cls
            }
        }

        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                guard let delegate = scene.delegate else { continue }
                let cls: AnyClass = object_getClass(delegate)!
                if installedSceneClass == nil {
                    install(on: cls,
                            original: NSSelectorFromString("scene:openURLContexts:"),
                            replacement: #selector(MSpotifyURLControl.eevee_scene(_:openURLContexts:)))
                    installedSceneClass = cls
                }
            }
        }
    }

    private func install(on targetClass: AnyClass, original: Selector, replacement: Selector) {
        guard let replacementMethod = class_getInstanceMethod(MSpotifyURLControl.self, replacement) else { return }
        let replacementIMP = method_getImplementation(replacementMethod)
        let replacementTypes = method_getTypeEncoding(replacementMethod)

        if let originalMethod = class_getInstanceMethod(targetClass, original) {
            class_addMethod(targetClass, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
            class_replaceMethod(targetClass, original, replacementIMP, replacementTypes)
        } else {
            class_addMethod(targetClass, original, replacementIMP, replacementTypes)
        }
    }

    @objc(eevee_application:openURL:options:)
    func eevee_application(_ application: UIApplication,
                           open url: URL,
                           options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        if handle(url) { return true }
        if class_getInstanceMethod(type(of: self), #selector(MSpotifyURLControl.eevee_application(_:open:options:))) != nil {
            return eevee_application(application, open: url, options: options)
        }
        return false
    }

    @available(iOS 13.0, *)
    @objc(eevee_scene:openURLContexts:)
    func eevee_scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        if contexts.contains(where: { handle($0.url) }) { return }
        eevee_scene(scene, openURLContexts: contexts)
    }

    private func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "mspotify" else { return false }
        let command = (url.host?.isEmpty == false ? url.host! : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        guard ["play", "pause", "toggle", "next", "previous"].contains(command) else { return false }
        pendingCommand = command
        attempts = 0
        runPendingCommand()
        return true
    }

    private func runPendingCommand() {
        guard let command = pendingCommand else { return }
        if PlayerGestures.performMSpotifyCommand(command) {
            pendingCommand = nil
            eeveeLog("[EeveeSpotify][mspotify] Executed %@", command)
            return
        }
        attempts += 1
        guard attempts < 30 else {
            eeveeLog("[EeveeSpotify][mspotify] Timed out: %@", command)
            pendingCommand = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.runPendingCommand() }
    }
}

func activateMSpotifyURLControl() {
    MSpotifyURLControl.shared.activate()
}