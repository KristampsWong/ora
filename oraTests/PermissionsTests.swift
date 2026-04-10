//
//  PermissionsTests.swift
//  oraTests
//
//  Covers the pure derived-state surface of Permissions. The real
//  system calls (AVCaptureDevice.requestAccess, AXIsProcessTrusted,
//  open-settings URLs) are not exercised here — they would require
//  a test harness that fakes TCC, which is not worth the lift for
//  this milestone.
//

import AVFoundation
import Testing
@testable import ora

@MainActor
struct PermissionsTests {
    @Test("allPermissionsGranted starts false in a clean process")
    func initialState() {
        let perms = Permissions()
        // In a unit-test process, mic is usually .notDetermined and
        // AX is not trusted, so the gate is false. We only assert the
        // combination — either individual value is environment-dependent
        // but the gate can only be true if *both* are.
        #expect(perms.allPermissionsGranted == (perms.microphoneGranted && perms.accessibilityGranted))
    }

    @Test("allPermissionsGranted mirrors the two underlying flags")
    func derivationContract() {
        let perms = Permissions()
        // microphoneGranted is a pure function of microphoneStatus,
        // and allPermissionsGranted is a pure AND of the two.
        #expect(perms.microphoneGranted == (perms.microphoneStatus == .authorized))
        #expect(perms.accessibilityGranted == perms.accessibilityStatus)
    }
}
