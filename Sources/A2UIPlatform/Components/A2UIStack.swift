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
import A2UISwiftCore

#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Spec v0.9 `Row` (horizontal) and `Column` (vertical) — pure layout containers.
///
/// Fully shared: stack hosting, child building via the factory, add/clear logic.
/// The `axis` vs `orientation` difference is absorbed by `a2ui_makeStack`, so
/// this component has NO `#if` of its own — both platforms run the same body.
final class A2UIStack: PlatformView, A2UIPlatformComponent {

    private let stack: PlatformStackView
    private let vertical: Bool
    /// Cross-axis alignment used when the component doesn't specify `align`.
    private let defaultAlign: Align?
    /// When true, `align`/`justify` from the component are ignored and
    /// `defaultAlign` is always used (Row rendered vertically, where the spec's
    /// horizontal-layout `align`/`justify` no longer apply).
    private let ignoresLayoutProps: Bool

    init(vertical: Bool, defaultAlign: Align? = nil, ignoresLayoutProps: Bool = false) {
        self.vertical = vertical
        self.defaultAlign = defaultAlign
        self.ignoresLayoutProps = ignoresLayoutProps
        self.stack = a2ui_makeStack(vertical: vertical)
        super.init(frame: .zero)
        a2ui_pinEdges(of: stack)
    }

    required init?(coder: NSCoder) {
        self.defaultAlign = nil
        self.ignoresLayoutProps = false
        self.vertical = true
        self.stack = a2ui_makeStack(vertical: true)
        super.init(coder: coder)
        a2ui_pinEdges(of: stack)
    }

    func configure(node: ComponentNode, surface: SurfaceModel, factory: ComponentFactory) {
        // Row/Column share the same property shape (children/justify/align).
        let props = try? node.typedProperties(RowProperties.self)
        let align = ignoresLayoutProps ? defaultAlign : (props?.align ?? defaultAlign)
        let justify = ignoresLayoutProps ? nil : props?.justify
        a2ui_applyAlignment(stack, align: align, vertical: vertical)
        a2ui_populateDistributed(
            stack: stack, children: node.children, justify: justify,
            vertical: vertical, surface: surface, factory: factory
        )
        let dc = DataContext(surface: surface, path: node.dataContextPath)
        a2ui_applyAccessibility(node.accessibility, dataContext: dc)
    }
}

#endif
