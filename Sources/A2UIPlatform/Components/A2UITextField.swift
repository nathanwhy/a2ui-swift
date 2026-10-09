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
    /// Plain view holding `textView` + the placeholder as siblings. The placeholder
    /// must NOT be a subview of the UITextView: it is a UIScrollView, so constraints
    /// to its edges resolve against the scrollable content area (not the visible
    /// width) and a long placeholder would never wrap.
    private let longTextContainer = UIView()
    private let placeholderLabel = UILabel()
    #elseif canImport(AppKit)
    private let field = NSTextField()
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let placeholderLabel = NSTextField(wrappingLabelWithString: "")
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

    /// Fills the available width but never grows past `textFieldMaxWidth`: the
    /// preferred width is the cap, and a low compression resistance lets the
    /// field shrink to whatever the parent offers.
    override var intrinsicContentSize: CGSize {
        CGSize(width: A2UIPlatformStyle.textFieldMaxWidth, height: PlatformView.noIntrinsicMetric)
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
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = a2ui_makeStack(vertical: true, spacing: 4)
        stack.addArrangedSubview(field)
        #if canImport(UIKit) && !os(watchOS)
        stack.addArrangedSubview(longTextContainer)
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
        longTextContainer.isHidden = true
        textView.isScrollEnabled = false // grows with content
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = A2UIPlatformStyle.cornerRadius
        textView.layer.borderWidth = A2UIPlatformStyle.dividerThickness
        textView.layer.borderColor = A2UIPlatformStyle.separator.cgColor
        textView.delegate = self
        longTextContainer.a2ui_pinEdges(of: textView)
        longTextContainer.heightAnchor.constraint(
            greaterThanOrEqualToConstant: A2UIPlatformStyle.longTextMinHeight).isActive = true

        // UITextView has no native placeholder — overlay a label at the text origin,
        // pinned to the text view's frame (see `longTextContainer`) so it wraps.
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        longTextContainer.addSubview(placeholderLabel)
        let inset = textView.textContainerInset
        let padding = textView.textContainer.lineFragmentPadding
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: inset.top),
            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor, constant: inset.left + padding),
            placeholderLabel.trailingAnchor.constraint(
                equalTo: textView.trailingAnchor, constant: -(inset.right + padding)),
            // Grow the field to fit a multi-line placeholder.
            longTextContainer.bottomAnchor.constraint(
                greaterThanOrEqualTo: placeholderLabel.bottomAnchor, constant: inset.bottom),
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
            // Pinned on both sides so a long placeholder wraps.
            placeholderLabel.trailingAnchor.constraint(
                equalTo: textView.trailingAnchor, constant: -(textView.textContainerInset.width + padding)),
            // Grow the scroll view to fit a multi-line placeholder.
            scrollView.heightAnchor.constraint(
                greaterThanOrEqualTo: placeholderLabel.heightAnchor,
                constant: textView.textContainerInset.height * 2),
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
        longTextContainer.isHidden = !isLongText
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
