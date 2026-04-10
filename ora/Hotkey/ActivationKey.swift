//
//  ActivationKey.swift
//  ora
//
//  Predefined modifier-only activation keys for hold-to-talk.
//  Maps UI display names to CGKeyCode + CGEventFlags for detection
//  via a CGEventTap watching .flagsChanged events.
//

import Carbon.HIToolbox
import CoreGraphics

enum ActivationKey: String, CaseIterable, Identifiable, Codable {
    case rightCommand = "Right ⌘"
    case rightOption  = "Right ⌥"
    case rightShift   = "Right ⇧"
    case rightControl = "Right ⌃"
    case leftCommand  = "Left ⌘"
    case leftOption   = "Left ⌥"
    case leftShift    = "Left ⇧"
    case leftControl  = "Left ⌃"
    case fn           = "Fn"

    var id: String { rawValue }

    /// The virtual key code for this modifier key, used to identify
    /// which specific key changed in a `.flagsChanged` CGEvent.
    var keyCode: CGKeyCode {
        switch self {
        case .rightCommand: CGKeyCode(kVK_RightCommand)
        case .rightOption:  CGKeyCode(kVK_RightOption)
        case .rightShift:   CGKeyCode(kVK_RightShift)
        case .rightControl: CGKeyCode(kVK_RightControl)
        case .leftCommand:  CGKeyCode(kVK_Command)
        case .leftOption:   CGKeyCode(kVK_Option)
        case .leftShift:    CGKeyCode(kVK_Shift)
        case .leftControl:  CGKeyCode(kVK_Control)
        case .fn:           CGKeyCode(kVK_Function)
        }
    }

    /// The CGEventFlags mask for the modifier family this key belongs to.
    /// Used to determine press vs release: if the flag IS present in the
    /// event's flags after a flagsChanged, the key went down; if absent,
    /// it went up.
    var modifierFlag: CGEventFlags {
        switch self {
        case .rightCommand, .leftCommand: .maskCommand
        case .rightOption, .leftOption:   .maskAlternate
        case .rightShift, .leftShift:     .maskShift
        case .rightControl, .leftControl: .maskControl
        case .fn:                         .maskSecondaryFn
        }
    }

    static let `default`: ActivationKey = .rightCommand
}
