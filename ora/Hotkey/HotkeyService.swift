//
//  HotkeyService.swift
//  ora
//
//  Global hotkey registration using raw Carbon `RegisterEventHotKey`.
//  Zero third-party dependencies, runs without any special TCC prompts,
//  ~120 lines. See M4 in the roadmap for why we picked Carbon over the
//  `HotKey` SPM package.
//
//  ## Why press AND release
//
//  Dictation v1 is hold-to-talk: press starts recording, release stops
//  it and fires the transcription pipeline. Carbon's keyboard event
//  class delivers both `kEventHotKeyPressed` and `kEventHotKeyReleased`
//  as separate events for a single registration, so one `register`
//  call is enough — no polling, no second code path.
//
//  ## Why not modifier-only (right-option / fn)
//
//  The original M4 brief said "default hotkey (right-option or fn)".
//  Carbon's `RegisterEventHotKey` cannot register a modifier-only
//  hotkey — the API takes a virtual keycode, and a bare modifier has
//  no keycode. The `HotKey` SPM package has the same limitation.
//
//  Modifier-only press/release is possible via a `CGEventTap` watching
//  `.flagsChanged` events, but that path requires the Input Monitoring
//  permission (TCC prompt on first run) and a dedicated run-loop
//  source. It's a bigger chunk of work than M4 deserves, so it's
//  deferred to M7 polish. For now the default is **Option+Space**,
//  which RegisterEventHotKey handles natively with no permissions.
//
//  ## Thread model
//
//  Carbon events dispatched through `GetApplicationEventTarget()`
//  deliver on the main run loop, i.e. the main thread. The C handler
//  function is therefore already on the main actor in practice — we
//  use `MainActor.assumeIsolated` to cross the type-system boundary
//  without hopping threads, so press/release latency stays at zero.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    /// Immutable description of a hotkey combo. `keyCode` is a Carbon
    /// virtual keycode (e.g. `kVK_Space`); `modifiers` is a bitfield of
    /// Carbon modifier flags (`cmdKey`, `optionKey`, `shiftKey`,
    /// `controlKey`).
    struct Config {
        let keyCode: UInt32
        let modifiers: UInt32

        /// Option+Space — the default shipped in M4. Comfortable for
        /// hold-to-talk, doesn't conflict with Spotlight (Cmd+Space)
        /// or the system input-source switcher (Ctrl+Space).
        static let optionSpace = Config(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey)
        )
    }

    /// Called on the main actor the instant the hotkey goes down.
    var onPress: (() -> Void)?
    /// Called on the main actor the instant the hotkey goes up. For a
    /// held key, this fires exactly once per press — key repeat does
    /// not generate spurious release events.
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// `RegisterEventHotKey` takes an application-scoped ID; any
    /// non-zero value works. 'ora ' as an OSType (four-byte code) is
    /// only used for debugging inside Activity Monitor / Instruments.
    private static let signature: OSType = 0x6F_72_61_20 // 'ora '

    deinit {
        // Deinit can't touch MainActor-isolated state, so call the
        // Carbon APIs directly. Both are safe to call on any thread
        // and are no-ops with a nil argument check.
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    // MARK: - Registration

    /// Registers (or re-registers) the global hotkey. Replacing an
    /// existing registration is supported — the old one is torn down
    /// first so the event handler and hotkey ref never leak.
    func register(_ config: Config) {
        unregister()

        var eventTypes: [EventTypeSpec] = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]

        // Pass `self` as the userData pointer so the C handler can
        // locate the service instance. `passUnretained` is correct
        // here — the service owns the registration and always
        // outlives the handler (see unregister / deinit).
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Carbon's `EventHandlerUPP` is a `@convention(c)` pointer, so
        // the callback must be a literal closure (or a top-level func)
        // with no captures. A reference to a separately-declared Swift
        // function compiles but trips "a C function pointer can only
        // be formed from a reference to a 'func' or a literal closure"
        // in some Swift versions, so we use the literal-closure form
        // which is unambiguously convertible.
        var handler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let event, let userData else { return noErr }
                let service = Unmanaged<HotkeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let kind = GetEventKind(event)
                MainActor.assumeIsolated {
                    service.dispatch(kind: kind)
                }
                return noErr
            },
            2,
            &eventTypes,
            selfPtr,
            &handler
        )
        guard installStatus == noErr else {
            print("[Hotkey] InstallEventHandler failed with OSStatus \(installStatus)")
            return
        }
        handlerRef = handler

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr else {
            // Common failure mode: another app has already registered
            // the same combo. Tear down the handler we just installed
            // so we don't sit on a dangling subscription.
            print("[Hotkey] RegisterEventHotKey failed with OSStatus \(registerStatus)")
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
            return
        }
        hotKeyRef = ref
    }

    /// Tears down the current registration if any. Idempotent.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    // MARK: - Dispatch (called from the C handler)

    /// Invoked from the top-level C handler once it has resolved the
    /// service pointer. Guaranteed to be on the main thread (Carbon
    /// dispatches application-target events there), so we use
    /// `assumeIsolated` to cross into MainActor without a hop.
    fileprivate func dispatch(kind: UInt32) {
        switch Int(kind) {
        case kEventHotKeyPressed:
            onPress?()
        case kEventHotKeyReleased:
            onRelease?()
        default:
            break
        }
    }
}

