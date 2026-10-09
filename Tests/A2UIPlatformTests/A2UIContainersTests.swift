// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
import XCTest
import A2UISwiftCore
@testable import A2UIPlatform

/// Container / complex-component gate (Card child resolution, Tabs, ChoicePicker).
final class A2UIContainersTests: XCTestCase {

    private func find<T: PlatformView>(_ type: T.Type, in view: PlatformView) -> T? {
        for sub in view.subviews {
            if let hit = sub as? T { return hit }
            if let hit = find(type, in: sub) { return hit }
        }
        return nil
    }

    private func texts(in view: PlatformView) -> [A2UIText] {
        var found: [A2UIText] = []
        for sub in view.subviews {
            if let t = sub as? A2UIText { found.append(t) }
            found.append(contentsOf: texts(in: sub))
        }
        return found
    }

    /// Validates the type-aware tree builder: Card uses `child`, not `children`.
    func testCardResolvesSingleChild() throws {
        let surface = SurfaceModel(id: "s-card")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "card", type: "Card", properties: ["child": .string("inner")]
        ))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "inner", type: "Text", properties: ["text": .string("Hi")]
        ))
        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "card")
        XCTAssertEqual(texts(in: host).map(\.currentText), ["Hi"])
    }

    func testTabsSwitchPanels() throws {
        let surface = SurfaceModel(id: "s-tabs")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "tabs", type: "Tabs", properties: ["tabs": .array([
                .dictionary(["title": .string("A"), "child": .string("ta")]),
                .dictionary(["title": .string("B"), "child": .string("tb")]),
            ])]
        ))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "ta", type: "Text", properties: ["text": .string("PanelA")]))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "tb", type: "Text", properties: ["text": .string("PanelB")]))

        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "tabs")
        let tabs = try XCTUnwrap(find(A2UITabs.self, in: host))

        XCTAssertEqual(tabs.currentIndex, 0)
        XCTAssertEqual(texts(in: host).map(\.currentText), ["PanelA"])
        tabs.select(1)
        XCTAssertEqual(tabs.currentIndex, 1)
        XCTAssertEqual(texts(in: host).map(\.currentText), ["PanelB"])
    }

    func testChoicePickerWritesSelection() throws {
        let surface = SurfaceModel(id: "s-cp")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "cp", type: "ChoicePicker", properties: [
                "variant": .string("multipleSelection"),
                "value": .dictionary(["path": .string("/sel")]),
                "options": .array([
                    .dictionary(["label": .string("X"), "value": .string("x")]),
                    .dictionary(["label": .string("Y"), "value": .string("y")]),
                ]),
            ]
        ))
        _ = try surface.dataModel.set("/sel", value: .array([]))

        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "cp")
        let picker = try XCTUnwrap(find(A2UIChoicePicker.self, in: host))

        picker.toggle("x")
        XCTAssertEqual(picker.selectedValues, ["x"])
        XCTAssertEqual(surface.dataModel.get("/sel")?.arrayValue?.compactMap(\.stringValue), ["x"])
    }

    /// A `stretch` Column makes its buttons full-width, and each button keeps its
    /// label centered rather than left-aligned.
    func testStretchColumnButtonsAreFullWidthWithCenteredLabels() throws {
        let surface = SurfaceModel(id: "s-btn-col")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "col", type: "Column", properties: [
                "align": .string("stretch"),
                "children": .array([.string("b1"), .string("b2")]),
            ]
        ))
        for (id, title) in [("b1", "Register"), ("b2", "Save as draft for later")] {
            try surface.componentsModel.addComponent(ComponentModel(
                id: id, type: "Button", properties: [
                    "child": .string("\(id)_label"),
                    "action": .dictionary(["event": .dictionary(["name": .string(id)])]),
                ]
            ))
            try surface.componentsModel.addComponent(ComponentModel(
                id: "\(id)_label", type: "Text", properties: ["text": .string(title)]))
        }

        let host = A2UISurfaceHostView()
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        host.render(surface: surface, rootComponentId: "col")
        #if canImport(UIKit) && !os(watchOS)
        host.layoutIfNeeded()
        #elseif canImport(AppKit)
        host.layoutSubtreeIfNeeded()
        #endif

        var buttons: [A2UIButton] = []
        func collect(_ view: PlatformView) {
            for sub in view.subviews {
                if let b = sub as? A2UIButton { buttons.append(b) } else { collect(sub) }
            }
        }
        collect(host)
        XCTAssertEqual(buttons.count, 2)

        let widths = buttons.map { $0.frame.width }
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.5, "Stretch should give equal button widths")

        for button in buttons {
            let label = try XCTUnwrap(find(A2UIText.self, in: button))
            let labelCenter = label.convert(CGPoint(x: label.bounds.midX, y: 0), to: button).x
            XCTAssertEqual(labelCenter, button.bounds.midX, accuracy: 0.5,
                           "Button child should stay centered when the button is wider than its content")
        }
    }
}

#endif
