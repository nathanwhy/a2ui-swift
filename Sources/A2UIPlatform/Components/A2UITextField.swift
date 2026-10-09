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

/// Spec v0.9 `TextField` — text input with two-way data binding.
/// Shared: value/label subscription + write-back. Per-platform: the control
/// (`UITextField` target-action vs `NSTextField` delegate). `variant: longText`
/// swaps the single-line field for a multi-line `UITextView` / `NSTextView`.
final class A2UITextField: PlatformView, A2UIPlatformComponent {

    private var subscriptions = DataSubscriptions()
    private var valueBindingPath: String?
    private var dataContext: DataContext?
    private var checks: [CheckRule]?
    private var regexp: String?
    private let errorLabel = A2UILabelView.makeError()

    #if canImport(UIKit) && !os(watchOS)
    private let field = UITextField()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    #elseif canImport(AppKit)
    private let field = NSTextField()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    #endif
    /// `variant: longText` — multi-line `textView` is shown instead of `field`.
    private var isLongText = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupField()
    }

    func configure(node: ComponentNode, surface: SurfaceModel, factory: ComponentFactory) {
        subscriptions.unsubscribeAll()
        guard let props = try? node.typedProperties(TextFieldProperties.self) else { return }
        let ctx = DataContext(surface: surface, path: node.dataContextPath)
        dataContext = ctx
        valueBindingPath = a2ui_bindingPath(props.value)
        checks = props.checks
        regexp = props.validationRegexp
        applyVariant(props.variant)
        a2ui_applyAccessibility(node.accessibility, dataContext: ctx)

        if let label = props.label {
            setPlaceholder(ctx.resolve(label))
            ctx.subscribeString(for: label) { [weak self] in self?.setPlaceholder($0) }
                .store(in: &subscriptions)
        }
        setText(ctx.resolve(props.value))
        ctx.subscribeString(for: props.value) { [weak self] in
            // Don't clobber the user mid-edit.
            guard let self, !self.isEditing else { return }
            self.setText($0)
            self.updateValidation()
        }.store(in: &subscriptions)
        updateValidation()
    }

    private func updateValidation() {
        guard let dataContext else { return }
        let message = a2ui_validationMessage(
            checks: checks, value: currentText, regexp: regexp, dataContext: dataContext)
        errorLabel.text = message ?? ""
        errorLabel.isHidden = (message == nil)
    }

    deinit { subscriptions.unsubscribeAll() }

    /// Test hook: simulate a user edit (set text + fire write-back).
    func simulateEditForTesting(_ text: String) {
        setText(text)
        writeBack()
    }

    private func writeBack() {
        guard let path = valueBindingPath else { return }
        try? dataContext?.set(path, value: .string(currentText))
        updateValidation()
    }

    // MARK: - Platform shell

    private func setupField() {
        let stack = a2ui_makeStack(vertical: true, spacing: 4)
        stack.addArrangedSubview(field)
        #if canImport(UIKit) && !os(watchOS)
        stack.addArrangedSubview(textView)
        #elseif canImport(AppKit)
        stack.addArrangedSubview(scrollView)
        #endif
        stack.addArrangedSubview(errorLabel)
        errorLabel.isHidden = true
        a2ui_pinEdges(of: stack)
        #if canImport(UIKit) && !os(watchOS)
        field.borderStyle = .roundedRect
        field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        setupTextView()
        #elseif canImport(AppKit)
        field.delegate = self
        setupTextView(in: stack)
        #endif
    }

    #if canImport(UIKit) && !os(watchOS)
    private func setupTextView() {
        textView.isHidden = true
        textView.isScrollEnabled = false // grows with content
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = A2UIPlatformStyle.cornerRadius
        textView.layer.borderWidth = A2UIPlatformStyle.dividerThickness
        textView.layer.borderColor = A2UIPlatformStyle.separator.cgColor
        textView.delegate = self
        textView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: A2UIPlatformStyle.longTextMinHeight).isActive = true

        // UITextView has no native placeholder — overlay a label at the text origin.
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(
                equalTo: textView.topAnchor, constant: textView.textContainerInset.top),
            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor,
                constant: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: textView.trailingAnchor,
                constant: -(textView.textContainerInset.right + textView.textContainer.lineFragmentPadding)),
        ])
    }
    #elseif canImport(AppKit)
    private func setupTextView(in stack: NSStackView) {
        scrollView.isHidden = true
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: A2UIPlatformStyle.longTextMinHeight),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        // NSTextView has no native placeholder — overlay a label at the text origin.
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        let padding = textView.textContainer?.lineFragmentPadding ?? 0
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(
                equalTo: textView.topAnchor, constant: textView.textContainerInset.height),
            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor, constant: textView.textContainerInset.width + padding),
        ])
    }
    #endif

    /// Applies the text-field variant (obscured = secure, number = numeric input,
    /// longText = multi-line text view). AppKit secure entry needs an
    /// NSSecureTextField swap (deferred).
    private func applyVariant(_ variant: TextFieldVariant?) {
        isLongText = (variant == .longText)
        #if canImport(UIKit) && !os(watchOS)
        field.isHidden = isLongText
        textView.isHidden = !isLongText
        switch variant {
        case .obscured: field.isSecureTextEntry = true
        case .number:   field.keyboardType = .decimalPad
        default:        field.isSecureTextEntry = false
        }
        #elseif canImport(AppKit)
        field.isHidden = isLongText
        scrollView.isHidden = !isLongText
        #endif
    }

    #if canImport(UIKit) && !os(watchOS)
    @objc private func editingChanged() { writeBack() }
    private var isEditing: Bool { isLongText ? textView.isFirstResponder : field.isEditing }
    private var currentText: String { (isLongText ? textView.text : field.text) ?? "" }
    private func setText(_ s: String) {
        if isLongText { textView.text = s; updatePlaceholderVisibility() } else { field.text = s }
    }
    private func setPlaceholder(_ s: String) {
        field.placeholder = s
        placeholderLabel.text = s
    }
    private func updatePlaceholderVisibility() { placeholderLabel.isHidden = !textView.text.isEmpty }
    #elseif canImport(AppKit)
    private var isEditing: Bool {
        isLongText ? textView.window?.firstResponder === textView : field.currentEditor() != nil
    }
    private var currentText: String { isLongText ? textView.string : field.stringValue }
    private func setText(_ s: String) {
        if isLongText { textView.string = s; updatePlaceholderVisibility() } else { field.stringValue = s }
    }
    private func setPlaceholder(_ s: String) {
        field.placeholderString = s
        placeholderLabel.stringValue = s
    }
    private func updatePlaceholderVisibility() { placeholderLabel.isHidden = !textView.string.isEmpty }
    #endif
}

#if canImport(UIKit) && !os(watchOS)
extension A2UITextField: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        writeBack()
    }
}
#endif

#if canImport(AppKit) && !(canImport(UIKit) && !os(watchOS))
extension A2UITextField: NSTextFieldDelegate, NSTextViewDelegate {
    func controlTextDidChange(_ obj: Notification) { writeBack() }
    func textDidChange(_ notification: Notification) {
        updatePlaceholderVisibility()
        writeBack()
    }
}
#endif

#endif
