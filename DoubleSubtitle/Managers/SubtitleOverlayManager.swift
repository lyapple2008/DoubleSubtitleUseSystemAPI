import Foundation
import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Manages subtitle overlay display using Picture-in-Picture.
final class SubtitleOverlayManager: NSObject, ObservableObject {
    static let shared = SubtitleOverlayManager()

    @Published var isPiPActive = false
    @Published var isPiPPossible = false
    @Published var currentSubtitle: SubtitleItem?
    @Published private(set) var currentOriginalText = ""
    @Published private(set) var currentTranslatedText = ""

    private var pipController: AVPictureInPictureController?
    private weak var pipSourceView: UIView?
    private let pipSourceAspectRatio: CGFloat = 16.0 / 9.0

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Setup PiP with a custom subtitle UI (video-call style PiP source).
    @available(iOS 15.0, *)
    func setupPiP(with sampleBufferDisplayLayer: AVSampleBufferDisplayLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPiPPossible = false
            return
        }

        guard pipController == nil else {
            isPiPPossible = true
            return
        }

        guard let sourceView = ensurePiPSourceView() else {
            isPiPPossible = false
            return
        }

        let contentController = AVPictureInPictureVideoCallViewController()
        contentController.view.backgroundColor = .black
        contentController.preferredContentSize = sourceView.bounds.size

        let hostingController = UIHostingController(rootView: PiPSubtitleOverlayView(overlayManager: self))
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        contentController.addChild(hostingController)
        contentController.view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: contentController.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentController.view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: contentController.view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentController.view.bottomAnchor)
        ])
        hostingController.didMove(toParent: contentController)

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentController
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true

        pipController = controller
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

    /// Update current subtitle item (kept for compatibility with existing call sites).
    func updateSubtitle(_ subtitle: SubtitleItem?) {
        currentSubtitle = subtitle
    }

    /// Update original text shown in PiP upper half.
    func updateCurrentOriginalText(_ text: String) {
        currentOriginalText = text
    }

    /// Update translated text shown in PiP lower half.
    func updateCurrentTranslatedText(_ text: String) {
        currentTranslatedText = text
    }

    /// Reset PiP text payload.
    func resetDisplayedTexts() {
        currentOriginalText = ""
        currentTranslatedText = ""
    }

    /// Check if PiP is currently active
    var isActive: Bool {
        pipController?.isPictureInPictureActive ?? false
    }

    private func ensurePiPSourceView() -> UIView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            return nil
        }

        let sourceFrame = preferredSourceFrame(in: window.bounds)

        if let pipSourceView = pipSourceView, pipSourceView.window != nil {
            pipSourceView.frame = sourceFrame
            return pipSourceView
        }

        let sourceView = UIView(frame: sourceFrame)
        sourceView.backgroundColor = .clear
        sourceView.isUserInteractionEnabled = false
        sourceView.alpha = 0.01
        window.addSubview(sourceView)
        pipSourceView = sourceView
        return sourceView
    }

    private func preferredSourceFrame(in windowBounds: CGRect) -> CGRect {
        let width = max(windowBounds.width, 240)
        let height = max(width / pipSourceAspectRatio, 135)
        return CGRect(x: 0, y: 0, width: width, height: height)
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

// MARK: - PiP Subtitle View

private struct PiPSubtitleOverlayView: View {
    @ObservedObject var overlayManager: SubtitleOverlayManager

    private var originalText: String {
        let value = overlayManager.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "等待识别中..." : value
    }

    private var translatedText: String {
        let value = overlayManager.currentTranslatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "等待翻译中..." : value
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                PiPSubtitlePanel(text: originalText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                PiPSubtitlePanel(text: translatedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .padding(8)
            .background(Color.black.opacity(0.86))
        }
    }
}

private struct PiPSubtitlePanel: View {
    let text: String

    private let bottomAnchorID = "pip-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(height: 1)
                    .id(bottomAnchorID)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: text) { _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }
}
