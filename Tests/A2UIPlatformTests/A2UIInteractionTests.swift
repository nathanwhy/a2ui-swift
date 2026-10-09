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

/// Interaction / action-dispatch gate.
final class A2UIInteractionTests: XCTestCase {

    private func find<T: PlatformView>(_ type: T.Type, in view: PlatformView) -> T? {
        for sub in view.subviews {
            if let hit = sub as? T { return hit }
            if let hit = find(type, in: sub) { return hit }
        }
        return nil
    }

    private func button(in view: PlatformView) -> A2UIButton? { find(A2UIButton.self, in: view) }

    func testButtonDispatchesEventAction() throws {
        let surface = SurfaceModel(id: "surface-btn")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "btn", type: "Button",
            properties: [
                "child": .string("label"),
                "action": .dictionary([
                    "event": .dictionary(["name": .string("submit")]),
                ]),
            ]
        ))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "label", type: "Text", properties: ["text": .string("Go")]
        ))

        var dispatched: [String] = []
        let token = surface.onAction.subscribe { dispatched.append($0.name) }
        defer { token.unsubscribe() }

        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "btn")

        let btn = try XCTUnwrap(button(in: host), "Button should render")
        btn.handleTap()

        XCTAssertEqual(dispatched, ["submit"], "Tap should dispatch the event action by name")
    }

    func testTextFieldWritesBackToBoundPath() throws {
        let surface = SurfaceModel(id: "surface-tf")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "tf", type: "TextField",
            properties: ["value": .dictionary(["path": .string("/name")])]
        ))
        _ = try surface.dataModel.set("/name", value: .string("initial"))

        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "tf")
        let field = try XCTUnwrap(find(A2UITextField.self, in: host))

        field.simulateEditForTesting("edited")

        XCTAssertEqual(surface.dataModel.get("/name")?.stringValue, "edited",
                       "Editing should write back to the bound data path")
    }

    func testLongTextTextFieldUsesTextViewAndWritesBack() throws {
        let surface = SurfaceModel(id: "surface-long")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "tf", type: "TextField",
            properties: [
                "variant": .string("longText"),
                "value": .dictionary(["path": .string("/notes")]),
            ]
        ))
        _ = try surface.dataModel.set("/notes", value: .string("line1\nline2"))

        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "tf")
        let field = try XCTUnwrap(find(A2UITextField.self, in: host))

        #if canImport(UIKit) && !os(watchOS)
        let textView = try XCTUnwrap(find(UITextView.self, in: field))
        XCTAssertFalse(textView.isHidden, "longText should show the multi-line text view")
        XCTAssertEqual(textView.text, "line1\nline2")
        #elseif canImport(AppKit)
        let textView = try XCTUnwrap(find(NSTextView.self, in: field))
        XCTAssertEqual(textView.string, "line1\nline2")
        #endif

        field.simulateEditForTesting("a\nb\nc")
        XCTAssertEqual(surface.dataModel.get("/notes")?.stringValue, "a\nb\nc",
                       "Multi-line edits should write back to the bound data path")
    }

    private func layOut(_ host: A2UISurfaceHostView, width: CGFloat) {
        host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        #if canImport(UIKit) && !os(watchOS)
        host.layoutIfNeeded()
        #elseif canImport(AppKit)
        host.layoutSubtreeIfNeeded()
        #endif
    }

    private func renderTextField(
        variant: String, label: String = "Name", hostWidth: CGFloat
    ) throws -> (A2UITextField, A2UISurfaceHostView) {
        let surface = SurfaceModel(id: "surface-width-\(variant)-\(hostWidth)")
        try surface.componentsModel.addComponent(ComponentModel(
            id: "col", type: "Column", properties: ["children": .array([.string("tf")])]))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "tf", type: "TextField",
            properties: [
                "variant": .string(variant),
                "label": .string(label),
                "value": .dictionary(["path": .string("/v")]),
            ]
        ))
        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "col")
        layOut(host, width: hostWidth)
        return (try XCTUnwrap(find(A2UITextField.self, in: host)), host)
    }

    func testTextFieldFillsWidthUpToMaximum() throws {
        let (narrow, _) = try renderTextField(variant: "shortText", hostWidth: 300)
        XCTAssertEqual(narrow.frame.width, 300 - 2 * A2UIPlatformStyle.leafMargin, accuracy: 1,
                       "Should fill the available width")

        let (wide, _) = try renderTextField(variant: "shortText", hostWidth: 800)
        XCTAssertEqual(wide.frame.width, A2UIPlatformStyle.textFieldMaxWidth, accuracy: 1,
                       "Should stop growing at textFieldMaxWidth")
    }

    func testLongTextPlaceholderWraps() throws {
        let placeholder = "Dietary requirements, accessibility needs, or anything else we should know"
        let (field, _) = try renderTextField(
            variant: "longText", label: placeholder, hostWidth: 240)
        #if canImport(UIKit) && !os(watchOS)
        let textView = try XCTUnwrap(find(UITextView.self, in: field))
        func labels(in view: UIView) -> [UILabel] {
            view.subviews.flatMap { ($0 as? UILabel).map { [$0] } ?? [] + labels(in: $0) }
        }
        let label = try XCTUnwrap(labels(in: field).first { $0.text == placeholder })
        let lineHeight = label.font.lineHeight
        // The label is a sibling of the text view, so compare in the field's space.
        let textArea = textView.convert(textView.bounds, to: field)
        let labelFrame = label.convert(label.bounds, to: field)
        #elseif canImport(AppKit)
        let textView = try XCTUnwrap(find(NSTextView.self, in: field))
        let label = try XCTUnwrap(find(NSTextField.self, in: textView))
        let lineHeight = (label.font ?? .systemFont(ofSize: NSFont.systemFontSize)).boundingRectForFont.height
        let textArea = textView.bounds
        let labelFrame = label.frame
        #endif
        XCTAssertGreaterThan(labelFrame.height, lineHeight * 1.5,
                             "A long placeholder should wrap onto multiple lines")
        XCTAssertLessThanOrEqual(labelFrame.maxX, textArea.maxX + 0.5,
                                 "The placeholder should stay inside the text area")
    }
}

#endif
