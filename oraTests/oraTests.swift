//
//  oraTests.swift
//  oraTests
//
//  Created by Kristamps Wang on 4/8/26.
//

import Testing
@testable import ora

struct oraTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func generalPageInstantiates() async throws {
        // Smoke test: GeneralPage should be constructible without throwing.
        // This proves the view exists and its @State defaults are valid.
        _ = GeneralPage()
    }

}
