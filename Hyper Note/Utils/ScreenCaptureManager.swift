//import Foundation
//import Vision
//import AppKit
//
//// MARK: - Protocols
//protocol SelectionViewDelegate: AnyObject {
//    func selectionView(_ view: SelectionView, didCaptureImage image: NSImage)
//    func selectionViewDidCancel(_ view: SelectionView)
//}
//
//// MARK: - ScreenCaptureManager
//class ScreenCaptureManager: ObservableObject {
//    // MARK: - Properties
//    static let shared = ScreenCaptureManager()
//    
//    private var captureWindow: NSWindow?
//    private var selectionView: SelectionView?
//    private var originalActiveApp: NSRunningApplication?
//    
//    @Published var isCapturing = false
//    @Published var isProcessing = false
//    @Published var lastError: Error?
//    
//    var textHandler: ((String) -> Void)?
//    
//    // MARK: - Error Types
//    enum CaptureError: LocalizedError {
//        case screenCaptureNotAuthorized
//        case failedToCreateCaptureWindow
//        case failedToCapture
//        case ocrFailed
//        
//        var errorDescription: String? {
//            switch self {
//            case .screenCaptureNotAuthorized:
//                return "需要屏幕录制权限才能使用OCR功能"
//            case .failedToCreateCaptureWindow:
//                return "创建截图窗口失败"
//            case .failedToCapture:
//                return "截图失败"
//            case .ocrFailed:
//                return "文字识别失败"
//            }
//        }
//    }
//    
//    // MARK: - Public Methods
//    func startCapture(completion: @escaping (String) -> Void) {
//        // Save current active app
//        originalActiveApp = NSWorkspace.shared.frontmostApplication
//        
//        // Check screen recording permission
//        if !checkScreenRecordingPermission() {
//            handleError(.screenCaptureNotAuthorized)
//            return
//        }
//        
//        self.textHandler = completion
//        
//        guard let screen = NSScreen.main else {
//            handleError(.failedToCreateCaptureWindow)
//            return
//        }
//        
//        // Create and configure capture window
//        let window = createCaptureWindow(for: screen)
//        
//        // Create and configure selection view
//        let selectionView = createSelectionView()
//        window.contentView = selectionView
//        self.selectionView = selectionView
//        
//        // Show window
//        showCaptureWindow(window)
//        
//        self.captureWindow = window
//        self.isCapturing = true
//    }
//    
//    func cancelCapture() {
//        cleanup()
//    }
//    
//    // MARK: - Private Methods
//    private func checkScreenRecordingPermission() -> Bool {
//        let type = CGWindowListOption.optionOnScreenOnly
//        let windowId = CGWindowID(0)
//        let screenshot = CGWindowListCreateImage(.null, type, windowId, .bestResolution)
//        return screenshot != nil
//    }
//    
//    private func createCaptureWindow(for screen: NSScreen) -> NSWindow {
//        let window = NSWindow(
//            contentRect: screen.frame,
//            styleMask: [.borderless, .fullSizeContentView],
//            backing: .buffered,
//            defer: false
//        )
//        
//        // Configure window properties
//        window.level = .popUpMenu
//        window.backgroundColor = .clear
//        window.isOpaque = false
//        window.hasShadow = false
//        
//        // Configure window behavior
//        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
//        window.isMovableByWindowBackground = false
//        window.ignoresMouseEvents = false
//        window.acceptsMouseMovedEvents = true
//        
//        return window
//    }
//    
//    private func createSelectionView() -> SelectionView {
//        let selectionView = SelectionView()
//        selectionView.delegate = self
//        selectionView.wantsLayer = true
//        selectionView.acceptsTouchEvents = true
////        selectionView.acceptsFirstResponder = true
//        return selectionView
//    }
//    
//    private func showCaptureWindow(_ window: NSWindow) {
//        NSApp.activate(ignoringOtherApps: true)
//        window.makeKeyAndOrderFront(nil)
//        window.orderFrontRegardless()
//    }
//    
//    private func cleanup() {
//        captureWindow?.close()
//        captureWindow = nil
//        selectionView = nil
//        isCapturing = false
//        isProcessing = false
//        
//        // Restore original active app
//        if let originalApp = originalActiveApp {
//            originalApp.activate(options: .activateIgnoringOtherApps)
//            originalActiveApp = nil
//        }
//    }
//    
//    private func handleError(_ error: CaptureError) {
//        lastError = error
//        cleanup()
//    }
//    
//    private func playScreenshotSound() {
//        NSSound(named: "Screenshot")?.play()
//    }
//    
//    private func performOCR(on image: NSImage, completion: @escaping (String?) -> Void) {
//        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
//            completion(nil)
//            return
//        }
//        
//        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
//        let request = VNRecognizeTextRequest { [weak self] request, error in
//            guard error == nil,
//                  let results = request.results as? [VNRecognizedTextObservation] else {
//                self?.handleError(.ocrFailed)
//                completion(nil)
//                return
//            }
//            
//            let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
//            completion(text)
//        }
//        
//        // Configure recognition
//        request.recognitionLanguages = ["zh-Hans", "en-US"]
//        request.recognitionLevel = .accurate
//        request.usesLanguageCorrection = true
//        
//        do {
//            try requestHandler.perform([request])
//        } catch {
//            handleError(.ocrFailed)
//            completion(nil)
//        }
//    }
//}
//
//// MARK: - SelectionViewDelegate
//extension ScreenCaptureManager: SelectionViewDelegate {
//    func selectionView(_ view: SelectionView, didCaptureImage image: NSImage) {
//        playScreenshotSound()
//        isProcessing = true
//        
//        performOCR(on: image) { [weak self] text in
//            DispatchQueue.main.async {
//                if let text = text {
//                    self?.textHandler?(text)
//                }
//                self?.cleanup()
//            }
//        }
//    }
//    
//    func selectionViewDidCancel(_ view: SelectionView) {
//        cleanup()
//    }
//}
//
//// MARK: - SelectionView
//class SelectionView: NSView {
//    // MARK: - Properties
//    weak var delegate: SelectionViewDelegate?
//    private var startPoint: NSPoint?
//    private var currentRect: NSRect?
//    private let overlayLayer = CAShapeLayer()
//    private let backgroundView = NSView()
//    
//    // MARK: - Initialization
//    override init(frame frameRect: NSRect) {
//        super.init(frame: frameRect)
//        setupView()
//    }
//    
//    required init?(coder: NSCoder) {
//        super.init(coder: coder)
//        setupView()
//    }
//    
//    // MARK: - Setup
//    private func setupView() {
//        wantsLayer = true
//        
//        // Setup background view
//        backgroundView.wantsLayer = true
//        backgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
//        addSubview(backgroundView)
//        
//        // Setup overlay layer
//        overlayLayer.fillColor = NSColor.clear.cgColor
//        overlayLayer.strokeColor = NSColor.systemBlue.cgColor
//        overlayLayer.lineWidth = 2
//        layer?.addSublayer(overlayLayer)
//    }
//    
//    override func layout() {
//        super.layout()
//        backgroundView.frame = bounds
//    }
//    
//    
//    override var acceptsFirstResponder: Bool {
//        get { return true }
//    }
//    
//    override func becomeFirstResponder() -> Bool {
//        return true
//    }
//    
//    // MARK: - Mouse Events
//    override func mouseDown(with event: NSEvent) {
//        startPoint = convert(event.locationInWindow, from: nil)
//        currentRect = nil
//        updateSelectionPath()
//    }
//    
//    override func mouseDragged(with event: NSEvent) {
//        guard let startPoint = startPoint else { return }
//        let currentPoint = convert(event.locationInWindow, from: nil)
//        
//        currentRect = NSRect(
//            x: min(startPoint.x, currentPoint.x),
//            y: min(startPoint.y, currentPoint.y),
//            width: abs(currentPoint.x - startPoint.x),
//            height: abs(currentPoint.y - startPoint.y)
//        )
//        
//        updateSelectionPath()
//    }
//    
//    override func mouseUp(with event: NSEvent) {
//        defer {
//            startPoint = nil
//            currentRect = nil
//        }
//        
//        guard let rect = currentRect, rect.width > 5, rect.height > 5 else {
//            delegate?.selectionViewDidCancel(self)
//            return
//        }
//        
//        // Convert to screen coordinates
//        guard let window = window,
//              let screen = window.screen else {
//            delegate?.selectionViewDidCancel(self)
//            return
//        }
//        
//        let screenRect = window.convertToScreen(rect)
//        
//        // Ensure the rect is within screen bounds
//        let validRect = screenRect.intersection(screen.frame)
//        
//        guard validRect.width > 0, validRect.height > 0,
//              let screenshot = captureRect(validRect) else {
//            delegate?.selectionViewDidCancel(self)
//            return
//        }
//        
//        delegate?.selectionView(self, didCaptureImage: screenshot)
//    }
//    
//    // MARK: - Selection Path
//    private func updateSelectionPath() {
//        if let rect = currentRect {
//            // Create selection rectangle
//            let path = CGMutablePath()
//            path.addRect(rect)
//            overlayLayer.path = path
//            
//            // Update background mask
//            let maskPath = CGMutablePath()
//            maskPath.addRect(bounds)
//            maskPath.addRect(rect)
//            
//            let maskLayer = CAShapeLayer()
//            maskLayer.path = maskPath
//            maskLayer.fillRule = .evenOdd
//            backgroundView.layer?.mask = maskLayer
//        } else {
//            overlayLayer.path = nil
//            backgroundView.layer?.mask = nil
//        }
//    }
//    
//    // MARK: - Screen Capture
//    private func captureRect(_ rect: NSRect) -> NSImage? {
//        guard rect.width > 0, rect.height > 0 else { return nil }
//        
//        if let screenshot = CGWindowListCreateImage(
//            rect,
//            .optionOnScreenOnly,
//            kCGNullWindowID,
//            .bestResolution
//        ) {
//            return NSImage(cgImage: screenshot, size: rect.size)
//        }
//        
//        return nil
//    }
//    
//    // MARK: - Keyboard Events
//    override func keyDown(with event: NSEvent) {
//        if event.keyCode == 53 { // ESC key
//            delegate?.selectionViewDidCancel(self)
//        }
//        super.keyDown(with: event)
//    }
//}
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
