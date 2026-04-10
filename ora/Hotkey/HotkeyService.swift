//
//  HotkeyService.swift
//  ora
//
//  Global modifier-only hotkey detection using a CGEventTap watching
//  `.flagsChanged` events. Replaces the previous Carbon
//  `RegisterEventHotKey` approach, which cannot handle modifier-only
//  keys (no virtual keycode to register).
//
//  ## How it works
//
//  A CGEventTap in `.listenOnly` mode watches `flagsChanged` events
//  at the session level. Each event carries the keycode of the
//  physical key that changed and the updated modifier flags. We
//  compare the keycode against the registered `ActivationKey.keyCode`
//  and determine press vs release by checking whether the key's
//  `modifierFlag` is present in the event's flags.
//
//  ## Threading
//
//  The event tap callback fires on a dedicated background thread
//  (same pattern as WhisperIsland's EventMonitor). Press/release
//  callbacks are dispatched to the main actor via
//  `DispatchQueue.main.async` so callers don't need to worry about
//  thread safety.
//
//  ## Permissions
//
//  CGEventTap requires the Accessibility permission (TCC). Ora
//  already requests this for Paster, so no new prompt is needed.
//  If the permission is revoked while the app is running, tapCreate
//  returns nil and we log the failure.
//

@preconcurrency import CoreGraphics
import Foundation

@MainActor
final class HotkeyService {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var registeredKey: ActivationKey?
    private var tapThread: Thread?
    nonisolated(unsafe) private var runLoopRef: CFRunLoop?
    private var machPort: CFMachPort?
    private var handlerBoxPtr: UnsafeMutableRawPointer?

    /// Tracks whether the registered key is currently held down.
    /// Thread-safe because all reads and writes happen on the main
    /// thread: the background tap callback extracts keyCode + flags,
    /// then dispatches to `DispatchQueue.main.async` where
    /// `processFlagsChanged` reads/writes `isPressed` and
    /// `registeredKey`.
    private var isPressed = false

    deinit {
        // deinit is nonisolated on @MainActor classes, so we stop
        // the run loop directly (CFRunLoopStop is thread-safe).
        if let rl = runLoopRef {
            CFRunLoopStop(rl)
        }
        if let port = machPort {
            CFMachPortInvalidate(port)
        }
        // Inline releaseHandlerBox — can't call MainActor methods from deinit.
        if let ptr = handlerBoxPtr {
            Unmanaged<HandlerBox>.fromOpaque(ptr).release()
        }
    }

    // MARK: - Registration

    /// Registers (or re-registers) the modifier-only hotkey.
    /// Starts the CGEventTap if it isn't already running, or
    /// simply swaps the target key if it is.
    func register(_ key: ActivationKey) {
        let wasRunning = registeredKey != nil
        registeredKey = key
        isPressed = false

        if !wasRunning {
            startEventTap()
        }
    }

    /// Tears down the current registration. Stops the event tap.
    func unregister() {
        registeredKey = nil
        isPressed = false
        stopEventTap()
    }

    // MARK: - Event tap lifecycle

    private func startEventTap() {
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        // The handler closure is passed as a C function pointer via
        // the HandlerBox pattern (same as WhisperIsland's EventMonitor).
        let box = Unmanaged.passRetained(
            HandlerBox { [weak self] event in
                self?.handleFlagsChanged(event)
            }
        )
        let ptr = box.toOpaque()
        handlerBoxPtr = ptr

        let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let box = Unmanaged<HandlerBox>.fromOpaque(userInfo).takeUnretainedValue()
                box.handler(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: ptr
        )

        guard let port else {
            print("[Hotkey] CGEvent.tapCreate failed — Accessibility permission may be missing")
            releaseHandlerBox()
            return
        }
        machPort = port

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)

        let thread = Thread { [weak self] in
            guard let self, let source else { return }
            self.runLoopRef = CFRunLoopGetCurrent()
            CFRunLoopAddSource(self.runLoopRef, source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "com.ora.hotkey-eventtap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    private func stopEventTap() {
        // Invalidate the port first — this removes the run loop
        // source, causing CFRunLoopRun to exit even if runLoopRef
        // hasn't been assigned yet (narrow race on startup).
        if let port = machPort {
            CFMachPortInvalidate(port)
            machPort = nil
        }
        if let rl = runLoopRef {
            CFRunLoopStop(rl)
            runLoopRef = nil
        }
        tapThread = nil
        releaseHandlerBox()
    }

    private func releaseHandlerBox() {
        if let ptr = handlerBoxPtr {
            Unmanaged<HandlerBox>.fromOpaque(ptr).release()
            handlerBoxPtr = nil
        }
    }

    // MARK: - Event handling (called on background thread)

    /// Called from the CGEventTap callback on the background thread.
    /// Dispatches press/release to main.
    private nonisolated func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        DispatchQueue.main.async { [weak self] in
            self?.processFlagsChanged(keyCode: keyCode, flags: flags)
        }
    }

    /// Runs on main. Compares the event's keycode against the
    /// registered key and fires press/release callbacks.
    private func processFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let registeredKey else { return }
        guard keyCode == registeredKey.keyCode else { return }

        let isDown = flags.contains(registeredKey.modifierFlag)

        if isDown && !isPressed {
            isPressed = true
            onPress?()
        } else if !isDown && isPressed {
            isPressed = false
            onRelease?()
        }
    }
}

// MARK: - HandlerBox

/// Reference-type wrapper so we can pass a Swift closure through
/// the C function pointer callback via `Unmanaged`.
private final class HandlerBox {
    let handler: (CGEvent) -> Void
    init(_ handler: @escaping (CGEvent) -> Void) {
        self.handler = handler
    }
}
