import Foundation
import AVFoundation
import AVKit
import SwiftUI

/// Manages subtitle overlay display using Picture-in-Picture
final class SubtitleOverlayManager: NSObject, ObservableObject {
    static let shared = SubtitleOverlayManager()

    @Published var isPiPActive = false
    @Published var isPiPPossible = false
    @Published var currentSubtitle: SubtitleItem?

    private var pipController: AVPictureInPictureController?
    private var subtitleLayer: CATextLayer?

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Setup PiP with a sample buffer layer
    @available(iOS 15.0, *)
    func setupPiP(with sampleBufferDisplayLayer: AVSampleBufferDisplayLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPiPPossible = false
            return
        }

        pipController = AVPictureInPictureController(playerLayer: AVPlayerLayer())
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true

        isPiPPossible = true
    }

    /// Start Picture-in-Picture
    func startPiP() {
        guard let pipController = pipController, isPiPPossible else { return }

        if pipController.isPictureInPictureActive {
            return
        }

        pipController.startPictureInPicture()
    }

    /// Stop Picture-in-Picture
    func stopPiP() {
        guard let pipController = pipController else { return }

        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        }
    }

    /// Update current subtitle to display
    func updateSubtitle(_ subtitle: SubtitleItem?) {
        currentSubtitle = subtitle
    }

    /// Check if PiP is currently active
    var isActive: Bool {
        pipController?.isPictureInPictureActive ?? false
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension SubtitleOverlayManager: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = true
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = true
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = false
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = false
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        DispatchQueue.main.async {
            self.isPiPActive = false
        }
        print("PiP failed to start: \(error.localizedDescription)")
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

// MARK: - Subtitle Layer Management

extension SubtitleOverlayManager {

    /// Update subtitle text - using SwiftUI Text views instead
    func updateSubtitleText(originalText: String, translatedText: String) {
        // This will be handled by the SwiftUI view directly
        // The subtitle is stored in currentSubtitle
    }
}
