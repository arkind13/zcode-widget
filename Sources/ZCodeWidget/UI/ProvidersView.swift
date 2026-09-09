import SwiftUI
import AppKit

// MARK: - Route (manual master-detail stack; no NavigationStack for panel stability)

private enum ProvidersRoute: Equatable {
    case list
    case provider(String)   // provider id being edited
    case model(String, String) // provider id, model id
}

struct ProvidersView: View {
    @StateObject private var store = ProviderConfigStore()
    @State private var route: ProvidersRoute = .list
    @State private var editing: ProviderConfig?
    @State private var isNewProvider = false
    @State private var editingModel: ProviderModelConfig?
    @State private var isNewModel = false
    @State private var toastMessage: String?
    @State private var errorAlert: String?
    @State private var pendingSaveWhileRunning = false
    @State private var deleteTarget: ProviderConfig?

    var body: some View {
        Group {
            switch route {
            case .list:
                providerList
            case .provider(let id):
                if let provider = editing, provider.id == id {
                    ProviderEditorView(
                        provider: Binding(
                            get: { editing ?? provider },
                            set: { editing = $0 }
                        ),
                        isNew: isNewProvider,
                        onBack: { route = .list; editing = nil },
                        onSave: { handleSave($0) },
                        onEditModel: { model, isNew in
                            editingModel = model
                            isNewModel = isNew
                            route = .model(id, model.id)
                        },
                        onDelete: { handleDeleteRequest($0) }
                    )
                    .id(id)
                } else {
                    providerList
                }
            case .model(let providerId, let modelId):
                if let model = editingModel, model.id == modelId {
                    ModelEditorView(
                        model: Binding(
                            get: { editingModel ?? model },
                            set: { editingModel = $0 }
                        ),
                        isNew: isNewModel,
                        existingIds: editing?.models.map(\.id) ?? [],
                        onCancel: {
                            editingModel = nil
                            route = .provider(providerId)
                        },
                        onSave: {
                            if let m = editingModel {
                                applyModelEdit(m, to: providerId)
                            }
                            route = .provider(providerId)
                        }
                    )
                    .id(modelId)
                } else {
                    providerList
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
        .alert("Save failed", isPresented: Binding(
            get: { errorAlert != nil && !pendingSaveWhileRunning },
            set: { if !$0 { errorAlert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
        .alert("ZCode IDE is running", isPresented: $pendingSaveWhileRunning) {
            Button("Save Anyway") { performSave() }
            Button("Cancel", role: .cancel) { errorAlert = nil }
        } message: {
            Text("ZCode may overwrite config.json when it quits. For reliable edits, quit ZCode first — otherwise your change can be lost. A backup is always created.")
        }
        .alert("Delete provider?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Remove “\(deleteTarget?.name ?? "")” from the provider registry? This cannot be undone in the widget (a backup file is created).")
        }
        .onAppear { if store.providers.isEmpty { store.load() } }
    }

    // MARK: - List

    private var providerList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    store.load()
                    toastMessage = "Reloaded"
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reload from config.json")

                if ProviderConfigStore.isZCodeRunning() {
                    Label("ZCode running — quit before editing", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    editing = ProviderConfigStore.newProviderTemplate()
                    isNewProvider = true
                    route = .provider(editing!.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add custom provider")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let err = store.loadError {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.providers) { provider in
                            ProviderRow(provider: provider) {
                                editing = provider
                                isNewProvider = false
                                route = .provider(provider.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleSave(_ provider: ProviderConfig) {
        editing = provider
        errorAlert = nil
        if ProviderConfigStore.isZCodeRunning() {
            pendingSaveWhileRunning = true
        } else {
            performSave()
        }
    }

    private func performSave() {
        guard let provider = editing else { return }
        do {
            try store.save(provider, isNew: isNewProvider)
            toastMessage = "Saved — restart ZCode to apply"
            route = .list
            editing = nil
        } catch {
            errorAlert = error.localizedDescription
        }
    }

    private func handleDeleteRequest(_ provider: ProviderConfig) {
        deleteTarget = provider
    }

    private func performDelete() {
        guard let target = deleteTarget else { return }
        do {
            try store.deleteProvider(id: target.id)
            toastMessage = "Deleted “\(target.name)”"
            route = .list
            editing = nil
        } catch {
            errorAlert = error.localizedDescription
        }
        deleteTarget = nil
    }

    private func applyModelEdit(_ model: ProviderModelConfig, to providerId: String) {
        guard var provider = editing, provider.id == providerId else { return }
        if let idx = provider.models.firstIndex(where: { $0.id == model.id }) {
            provider.models[idx] = model
        } else {
            provider.models.append(model)
            provider.models.sort { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        }
        editing = provider
        editingModel = nil
    }
}

// MARK: - Provider row

private struct ProviderRow: View {
    let provider: ProviderConfig
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            rowContent
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Edit \(provider.name)")
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.kind == "anthropic" ? "a.square.fill" : "o.square.fill")
                .font(.system(size: 16))
                .foregroundStyle(provider.kind == "anthropic" ? .blue : .purple)
                .help("kind: \(provider.kind)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(provider.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    if provider.isBuiltin {
                        Text("builtin")
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .quaternaryLabelColor))
                            .cornerRadius(3)
                            .foregroundStyle(.secondary)
                    }
                    if !provider.enabled {
                        Text("disabled")
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                            .foregroundStyle(.orange)
                    }
                }
                Text(provider.baseURL.isEmpty ? provider.models.map(\.id).joined(separator: ", ") : provider.baseURL)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(provider.models.count) model\(provider.models.count == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                if provider.systemDisabledReason != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .help("system disabled: \(provider.systemDisabledReason ?? "")")
                }
            }
        }
    }
}

// MARK: - Provider editor

private struct ProviderEditorView: View {
    @Binding var provider: ProviderConfig
    let isNew: Bool
    let onBack: () -> Void
    let onSave: (ProviderConfig) -> Void
    let onEditModel: (ProviderModelConfig, Bool) -> Void
    let onDelete: (ProviderConfig) -> Void

    @State private var revealKey = false

    private static let claudeUA = "claude-cli/2.0.14 (external, cli)"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Back")

                Text(isNew ? "New Provider" : provider.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if provider.isBuiltin {
                    Text("builtin")
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color(nsColor: .quaternaryLabelColor))
                        .cornerRadius(3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        sectionTitle("Basics")
                        fieldRow("Name", TextField("agentrouter", text: $provider.name))
                        fieldRow("Protocol", Picker("", selection: $provider.kind) {
                            Text("anthropic").tag("anthropic")
                            Text("openai-compatible").tag("openai-compatible")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden())
                        fieldRow("Base URL", TextField("https://agentrouter.org", text: $provider.baseURL))
                        HStack(spacing: 6) {
                            if revealKey {
                                TextField("API key", text: $provider.apiKey)
                            } else {
                                SecureField("API key", text: $provider.apiKey)
                            }
                            Button {
                                revealKey.toggle()
                            } label: {
                                Image(systemName: revealKey ? "eye.slash" : "eye")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(revealKey ? "Hide key" : "Show key")
                        }
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        Toggle("Key required", isOn: $provider.apiKeyRequired)
                            .font(.system(size: 11))
                        Toggle("Enabled", isOn: $provider.enabled)
                            .font(.system(size: 11))
                    }

                    // Headers
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Custom Headers")
                        if provider.headers.isEmpty {
                            Text("None")
                                .font(.system(size: 10))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        }
                        ForEach($provider.headers) { $header in
                            HStack(spacing: 6) {
                                TextField("Header", text: $header.key)
                                    .font(.system(size: 11, design: .monospaced))
                                TextField("Value", text: $header.value)
                                    .font(.system(size: 11, design: .monospaced))
                                Button {
                                    provider.headers.removeAll { $0.id == header.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 6) {
                            Button {
                                provider.headers.append(
                                    ProviderConfig.HeaderPair(key: "User-Agent", value: Self.claudeUA)
                                )
                            } label: {
                                Label("Add Claude Code UA", systemImage: "plus.circle")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.link)
                            .help("Adds the User-Agent header that client-allowlist gateways (agentrouter, etc.) require")

                            Button {
                                provider.headers.append(ProviderConfig.HeaderPair(key: "", value: ""))
                            } label: {
                                Label("Empty", systemImage: "plus")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.link)
                        }
                    }

                    // Fix button
                    if provider.kind == "openai-compatible" || !hasClaudeUA {
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                applyEmptyResponseFix()
                            } label: {
                                Label("Apply empty-response fix", systemImage: "wrench.and.screwdriver")
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            Text("Sets protocol to anthropic and adds the Claude Code User-Agent — the confirmed fix for gateways that silently return empty streams (empty_model_response).")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Models
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("Models (\(provider.models.count))")
                        if provider.models.isEmpty {
                            Text("No models — add one so ZCode can select it.")
                                .font(.system(size: 10))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        }
                        ForEach(provider.models) { model in
                            Button {
                                onEditModel(model, false)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(model.id)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            if !model.name.isEmpty {
                                                Text(model.name).font(.system(size: 9)).foregroundStyle(.secondary)
                                            }
                                            if model.reasoningEnabled {
                                                Text("reasoning:\(model.defaultVariant.isEmpty ? "on" : model.defaultVariant)")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.blue)
                                            }
                                            Text("\(model.contextLimit / 1000)k ctx")
                                                .font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            onEditModel(ProviderConfigStore.newModelTemplate(), true)
                        } label: {
                            Label("Add model", systemImage: "plus.circle")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.link)
                    }

                    // Danger zone
                    if !provider.isBuiltin {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionTitle("Danger Zone")
                            Button(role: .destructive) {
                                onDelete(provider)
                            } label: {
                                Label("Delete provider", systemImage: "trash")
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider()

            // Save bar
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Text("Discard")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)

                Button {
                    onSave(provider)
                } label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(provider.name.trimmingCharacters(in: .whitespaces).isEmpty || provider.id.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var hasClaudeUA: Bool {
        provider.headers.contains { $0.key == "User-Agent" && !$0.value.isEmpty }
    }

    private func applyEmptyResponseFix() {
        provider.kind = "anthropic"
        if let idx = provider.headers.firstIndex(where: { $0.key == "User-Agent" }) {
            provider.headers[idx].value = Self.claudeUA
        } else {
            provider.headers.append(ProviderConfig.HeaderPair(key: "User-Agent", value: Self.claudeUA))
        }
    }

    private func sectionTitle(_ s: String) -> Text {
        Text(s.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }

    @ViewBuilder
    private func fieldRow(_ label: String, _ field: some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            field
                .font(.system(size: 12))
        }
    }
}

// MARK: - Model editor

private struct ModelEditorView: View {
    @Binding var model: ProviderModelConfig
    let isNew: Bool
    let existingIds: [String]
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var variantsText: String = ""
    @State private var contextText: String = ""
    @State private var outputText: String = ""
    @State private var idValidation: String?

    private static let modalityOptions = ["text", "image", "video", "audio"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(isNew ? "New Model" : "Model: \(model.id)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        Text("BASICS").sectionLabel()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Model ID (sent to gateway)").fieldLabel()
                            TextField("glm-5.3", text: $model.id)
                                .font(.system(size: 12, design: .monospaced))
                                .disabled(!isNew)
                                .onChange(of: model.id) { _ in validateId() }
                            if let err = idValidation {
                                Text(err).font(.system(size: 9)).foregroundStyle(.red)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Display name (optional)").fieldLabel()
                            TextField("GLM-5.3", text: $model.name)
                        }
                    }

                    Group {
                        Text("LIMITS").sectionLabel()
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Context").fieldLabel()
                                TextField("1000000", text: $contextText)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Max output (blank = unset)").fieldLabel()
                                TextField("128000", text: $outputText)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }

                    Group {
                        Text("REASONING").sectionLabel()
                        Toggle("Reasoning enabled", isOn: $model.reasoningEnabled)
                            .font(.system(size: 11))
                        if model.reasoningEnabled {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Variants (comma-separated)").fieldLabel()
                                TextField("low, high, max", text: $variantsText)
                                    .font(.system(size: 12, design: .monospaced))
                                if !model.defaultVariant.isEmpty || !currentVariants.isEmpty {
                                    Picker("Default", selection: $model.defaultVariant) {
                                        ForEach(currentVariants, id: \.self) { v in
                                            Text(v).tag(v)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                    }

                    Group {
                        Text("MODALITIES").sectionLabel()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Input").fieldLabel()
                            modalityChips(selection: $model.inputModalities)
                            Text("Output").fieldLabel()
                            modalityChips(selection: $model.outputModalities)
                        }
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider()

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Discard")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)

                Button(action: saveModel) {
                    Text("Save Model")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .onAppear {
            variantsText = model.reasoningVariants.joined(separator: ", ")
            contextText = model.contextLimit > 0 ? String(model.contextLimit) : ""
            outputText = model.outputLimit > 0 ? String(model.outputLimit) : ""
        }
    }

    private var currentVariants: [String] {
        variantsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        !model.id.trimmingCharacters(in: .whitespaces).isEmpty && idValidation == nil
    }

    private func validateId() {
        let trimmed = model.id.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            idValidation = "Model ID is required"
        } else if isNew && existingIds.contains(trimmed) {
            idValidation = "A model with this ID already exists"
        } else {
            idValidation = nil
        }
    }

    private func saveModel() {
        model.reasoningVariants = currentVariants
        if currentVariants.contains(model.defaultVariant) {
            // keep
        } else {
            model.defaultVariant = currentVariants.first ?? ""
        }
        model.contextLimit = Int(contextText.trimmingCharacters(in: .whitespaces)) ?? 0
        model.outputLimit = Int(outputText.trimmingCharacters(in: .whitespaces)) ?? 0
        onSave() // commits the model into the editing provider and routes back
    }

    private func modalityChips(selection: Binding<[String]>) -> some View {
        HStack(spacing: 6) {
            ForEach(Self.modalityOptions, id: \.self) { option in
                let isOn = selection.wrappedValue.contains(option)
                Button {
                    if isOn {
                        selection.wrappedValue.removeAll { $0 == option }
                    } else {
                        selection.wrappedValue.append(option)
                    }
                } label: {
                    Text(option)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isOn ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Small helpers

private extension Text {
    func sectionLabel() -> some View {
        font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
    }
    func fieldLabel() -> some View {
        font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}
