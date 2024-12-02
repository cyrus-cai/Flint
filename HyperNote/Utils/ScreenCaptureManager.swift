import Foundation
import Vision
import AppKit

// MARK: - Protocols
protocol SelectionViewDelegate: AnyObject {
    func selectionView(_ view: SelectionView, didCaptureImage image: NSImage)
    func selectionViewDidCancel(_ view: SelectionView)
}

// MARK: - ScreenCaptureManager
class ScreenCaptureManager: ObservableObject {
    static let shared = ScreenCaptureManager()
    
    private var captureWindow: NSWindow?
    private var selectionView: SelectionView?
    private var originalActiveApp: NSRunningApplication?
    
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var lastError: Error?
    
    var textHandler: ((String) -> Void)?
    
    // MARK: - Public Methods
    func startCapture(completion: @escaping (String) -> Void) {
        originalActiveApp = NSWorkspace.shared.frontmostApplication
        
        guard checkScreenRecordingPermission() else {
//            handleError(.screenCaptureNotAuthorized)
            return
        }
        
        textHandler = completion
        
        guard let screen = NSScreen.main else {
//            handleError(.failedToCreateCaptureWindow)
            return
        }
        
        let window = createCaptureWindow(for: screen)
        let selectionView = createSelectionView()
        window.contentView = selectionView
        self.selectionView = selectionView
        
        showCaptureWindow(window)
        self.captureWindow = window
        self.isCapturing = true
    }
    
    func cancelCapture() {
        cleanup()
    }
    
    // MARK: - Private Methods
    private func checkScreenRecordingPermission() -> Bool {
        let type = CGWindowListOption.optionOnScreenOnly
        let windowId = CGWindowID(0)
        let screenshot = CGWindowListCreateImage(.null, type, windowId, .bestResolution)
        return screenshot != nil
    }
    
    private func createCaptureWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        
        return window
    }
    
    private func createSelectionView() -> SelectionView {
        let selectionView = SelectionView()
        selectionView.delegate = self
        selectionView.wantsLayer = true
        return selectionView
    }
    
    private func showCaptureWindow(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    
    private func cleanup() {
        DispatchQueue.main.async {
            self.captureWindow?.contentView = nil
            self.captureWindow?.close()
            self.captureWindow = nil
            self.selectionView = nil
            self.isCapturing = false
            self.isProcessing = false

            // Restore original active app
            if let originalApp = self.originalActiveApp {
                originalApp.activate(options: .activateIgnoringOtherApps)
                self.originalActiveApp = nil
            }
        }
    }
    
//    private func handleError(_ error: CaptureError) {
//        DispatchQueue.main.async {
//            self.lastError = error
//            self.cleanup()
//        }
//    }
    
    private func playScreenshotSound() {
        NSSound(named: "Screenshot")?.play()
    }
    
    private func performOCR(on image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self, error == nil,
                  let results = request.results as? [VNRecognizedTextObservation] else {
//                self?.handleError(.ocrFailed)
                completion(nil)
                return
            }

            let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            completion(text)
        }

        do {
            try requestHandler.perform([request])
        } catch {
//            handleError(.ocrFailed)
            completion(nil)
        }
    }
}

// MARK: - SelectionViewDelegate
extension ScreenCaptureManager: SelectionViewDelegate {
    func selectionView(_ view: SelectionView, didCaptureImage image: NSImage) {
        playScreenshotSound()
        isProcessing = true
        
        performOCR(on: image) { [weak self] text in
            DispatchQueue.main.async {
                if let text = text {
                    self?.textHandler?(text)
                }
                self?.cleanup()
            }
        }
    }
    
    func selectionViewDidCancel(_ view: SelectionView) {
        cleanup()
    }
}

// MARK: - SelectionView
class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?
    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private let overlayLayer = CAShapeLayer()
    private let backgroundView = NSView()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        addSubview(backgroundView)
        
        overlayLayer.fillColor = NSColor.clear.cgColor
        overlayLayer.strokeColor = NSColor.systemBlue.cgColor
        overlayLayer.lineWidth = 2
        layer?.addSublayer(overlayLayer)
    }
    
    override func layout() {
        super.layout()
        backgroundView.frame = bounds
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        updateSelectionPath()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = startPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        
        currentRect = NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        
        updateSelectionPath()
    }
    
    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            currentRect = nil
        }
        
        guard let rect = currentRect, rect.width > 5, rect.height > 5 else {
            delegate?.selectionViewDidCancel(self)
            return
        }
        
        guard let window = window, let screen = window.screen else {
            delegate?.selectionViewDidCancel(self)
            return
        }
        
        let screenRect = window.convertToScreen(rect)
        let validRect = screenRect.intersection(screen.frame)
        
        guard validRect.width > 0, validRect.height > 0,
              let screenshot = captureRect(validRect) else {
            delegate?.selectionViewDidCancel(self)
            return
        }
        
        delegate?.selectionView(self, didCaptureImage: screenshot)
    }
    
    private func updateSelectionPath() {
        if let rect = currentRect {
            let path = CGMutablePath()
            path.addRect(rect)
            overlayLayer.path = path
            
            let maskPath = CGMutablePath()
            maskPath.addRect(bounds)
            maskPath.addRect(rect)
            
            let maskLayer = CAShapeLayer()
            maskLayer.path = maskPath
            maskLayer.fillRule = .evenOdd
            backgroundView.layer?.mask = maskLayer
        } else {
            overlayLayer.path = nil
            backgroundView.layer?.mask = nil
        }
    }
    
    private func captureRect(_ rect: NSRect) -> NSImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        
        if let screenshot = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) {
            return NSImage(cgImage: screenshot, size: rect.size)
        }
        
        return nil
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            delegate?.selectionViewDidCancel(self)
        }
        super.keyDown(with: event)
    }
}
