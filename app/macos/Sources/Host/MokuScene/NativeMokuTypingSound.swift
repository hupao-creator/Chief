import AudioToolbox
import ChiefPluginUI
import CryptoKit
import Foundation

enum NativeMokuTypingSound {
    private static let queue = DispatchQueue(label: "Chief.keyboard-audio", qos: .userInitiated)

    // Registration (including an unavailable result) is cached for the process lifetime.
    private static let character = register("key_press_click", sha256:
        "6acf08272efa46d9bc6ab58e7d00bc58c7055ceeb0f3d41dc60ea9be74de18bd")
    private static let delete = register("key_press_delete", sha256:
        "f3f0064af5fecbf0ad81c42f469a2b6dac97c71ed2ee2273b5cee2df2fa1453f")

    static func play(_ key: NativeComposerTypingKey) {
        queue.async {
            let sound = switch key {
            case .character: character
            case .delete: delete
            }
            if let sound { AudioServicesPlaySystemSound(sound) }
        }
    }

    private static func register(_ name: String, sha256: String) -> SystemSoundID? {
        let directory = "/System/iOSSupport/System/Library/PrivateFrameworks/UIKitCore.framework/Resources"
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name).appendingPathExtension("caf")
        guard let data = try? Data(contentsOf: url),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else { return nil }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr else { return nil }
        return sound
    }
}
