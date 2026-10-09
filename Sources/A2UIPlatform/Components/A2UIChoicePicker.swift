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

/// Spec v0.9 `ChoicePicker` — single- or multi-select over a set of options.
///
/// Baseline: a vertical list of tappable option rows; selection writes the value
/// list back to the bound path. The list binding is resolved once (there is no
/// `subscribeStringList` helper yet — reactive list reads are a later refinement).
final class A2UIChoicePicker: PlatformView, A2UIPlatformComponent {

    // Spec: VStack(alignment:.leading, spacing:4) { label?, options, error? }
    private let column = a2ui_makeStack(vertical: true, spacing: 4)
    private let titleLabel = A2UILabelView.makeFieldLabel()
    private let rowsStack = a2ui_makeStack(vertical: true, spacing: 4)
    private let errorLabel = A2UILabelView.makeError()
    private var dataContext: DataContext?
    private var valueBindingPath: String?
    private var checks: [CheckRule]?
    private var multiSelect = false
    private var chips = false
    private var options: [(label: String, value: String)] = []
    private var selected: Set<String> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }

    private func setupLayout() {
        a2ui_applyAlignment(column, align: .start, vertical: true) // leading
        column.addArrangedSubview(titleLabel)
        column.addArrangedSubview(rowsStack)
        column.addArrangedSubview(errorLabel)
        errorLabel.isHidden = true
        a2ui_pinEdges(of: column)
    }

    func configure(node: ComponentNode, surface: SurfaceModel, factory: ComponentFactory) {
        guard let props = try? node.typedProperties(ChoicePickerProperties.self) else { return }
        let ctx = DataContext(surface: surface, path: node.dataContextPath)
        dataContext = ctx
        valueBindingPath = a2ui_bindingPath(props.value)
        checks = props.checks
        multiSelect = props.variant == .multipleSelection
        chips = (props.displayStyle ?? .checkbox) == .chips
        a2ui_applyAccessibility(node.accessibility, dataContext: ctx)

        if let label = props.label {
            titleLabel.isHidden = false
            titleLabel.text = ctx.resolve(label)
        } else {
            titleLabel.isHidden = true
        }
        options = props.options.map { (ctx.resolve($0.label), $0.value) }
        selected = Set(props.value.map { ctx.resolve($0) } ?? [])
        rebuildRows()
        updateValidation()
    }

    private func updateValidation() {
        let message = dataContext?.firstFailingCheckMessage(checks)
        errorLabel.text = message ?? ""
        errorLabel.isHidden = (message == nil)
    }

    /// Test hook + row tap entry point.
    func toggle(_ value: String) {
        if multiSelect {
            if selected.contains(value) { selected.remove(value) } else { selected.insert(value) }
        } else {
            selected = [value]
        }
        writeBack()
        rebuildRows()
        updateValidation()
    }

    var selectedValues: Set<String> { selected }

    private func writeBack() {
        guard let path = valueBindingPath else { return }
        try? dataContext?.set(path, value: .array(selected.sorted().map { .string($0) }))
    }

    private func rebuildRows() {
        for v in rowsStack.arrangedSubviews { rowsStack.removeArrangedSubview(v); v.removeFromSuperview() }
        for option in options {
            let row = A2UIChoiceRow(
                label: option.label,
                isSelected: selected.contains(option.value),
                chip: chips,
                multiSelect: multiSelect
            ) { [weak self] in self?.toggle(option.value) }
            rowsStack.addArrangedSubview(row)
        }
    }
}

/// A single tappable option row. Chips render as a capsule; otherwise the row shows a
/// native checkbox (multi-select) or radio (single-select) SF Symbol before the label.
private final class A2UIChoiceRow: PlatformView {
    private let action: () -> Void

    init(label: String, isSelected: Bool, chip: Bool, multiSelect: Bool, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        #if canImport(UIKit) && !os(watchOS)
        let field = UILabel()
        field.text = label
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        #elseif canImport(AppKit)
        let field = NSTextField(labelWithString: label)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        #endif

        if chip {
            #if canImport(UIKit) && !os(watchOS)
            field.textColor = isSelected ? .white : .label
            #elseif canImport(AppKit)
            field.textColor = isSelected ? .white : .labelColor
            #endif
            a2ui_pinEdges(of: field, inset: 8)
            // Capsule: filled tint when selected, outlined otherwise.
            a2ui_setCornerRadius(14)
            if isSelected {
                a2ui_setBackground(A2UIPlatformStyle.tint)
            } else {
                a2ui_setBackground(.clear)
                setBorder()
            }
        } else {
            let symbol = multiSelect
                ? (isSelected ? "checkmark.square.fill" : "square")
                : (isSelected ? "largecircle.fill.circle" : "circle")
            let icon = Self.makeIcon(symbol, selected: isSelected)
            let row = a2ui_makeStack(vertical: false, spacing: 8)
            #if canImport(UIKit) && !os(watchOS)
            row.alignment = .center
            #elseif canImport(AppKit)
            row.alignment = .centerY
            #endif
            row.addArrangedSubview(icon)
            row.addArrangedSubview(field)
            a2ui_pinEdges(of: row, inset: 4)
        }
    }

    #if canImport(UIKit) && !os(watchOS)
    private static func makeIcon(_ symbol: String, selected: Bool) -> UIImageView {
        let view = UIImageView(image: UIImage(systemName: symbol))
        view.tintColor = selected ? A2UIPlatformStyle.tint : A2UIPlatformStyle.choiceUnselectedColor
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.preferredSymbolConfiguration = A2UIPlatformStyle.choiceIconSize
            .map { UIImage.SymbolConfiguration(pointSize: $0) }
            ?? UIImage.SymbolConfiguration(textStyle: .title3)
        return view
    }
    #elseif canImport(AppKit)
    private static func makeIcon(_ symbol: String, selected: Bool) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        if let size = A2UIPlatformStyle.choiceIconSize {
            view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        }
        view.contentTintColor = selected ? A2UIPlatformStyle.tint : A2UIPlatformStyle.choiceUnselectedColor
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
    #endif

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func setBorder() {
        #if canImport(UIKit) && !os(watchOS)
        layer.borderWidth = 1; layer.borderColor = A2UIPlatformStyle.tint.cgColor
        #elseif canImport(AppKit)
        wantsLayer = true; layer?.borderWidth = 1; layer?.borderColor = A2UIPlatformStyle.tint.cgColor
        #endif
    }

    @objc private func tapped() { action() }
}

#endif
