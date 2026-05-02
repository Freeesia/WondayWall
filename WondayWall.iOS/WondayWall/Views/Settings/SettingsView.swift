import SwiftUI
import AuthenticationServices

// 設定画面 — API キー・カレンダー・RSS・生成設定・通知
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    SettingsContentView(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("設定")
        }
        .task {
            if viewModel == nil {
                viewModel = SettingsViewModel(environment: environment)
                await viewModel?.loadAvailableCalendars()
            }
        }
    }
}

// 設定画面のコンテンツ本体
private struct SettingsContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Bindable var vm: SettingsViewModel

    var body: some View {
        Form {
            // Google AI API キーセクション
            Section {
                HStack {
                    SecureField("API キーを入力", text: $vm.config.googleAiApiKey)
                }
            } header: {
                Text("Google AI API キー")
            } footer: {
                Text("Google AI Studio（aistudio.google.com）で取得できます。")
                    .font(.caption)
            }

            // Google Calendar セクション
            Section {
                if !vm.availableCalendars.isEmpty {
                    // カレンダー選択
                    ForEach(vm.availableCalendars) { calendar in
                        HStack {
                            Image(
                                systemName: vm.config.targetCalendarIds.contains(calendar.id)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                vm.config.targetCalendarIds.contains(calendar.id)
                                    ? .blue : .secondary
                            )
                            VStack(alignment: .leading) {
                                Text(calendar.summary)
                                if calendar.isPrimary {
                                    Text("プライマリ")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { vm.toggleCalendar(calendar.id) }
                    }

                    // 接続解除ボタン
                    Button(role: .destructive) {
                        vm.disconnectCalendar()
                    } label: {
                        Label("カレンダー連携を解除", systemImage: "link.badge.minus")
                    }
                } else {
                    // カレンダー接続ボタン
                    Button {
                        Task { @MainActor in
                            guard
                                let anchor = UIApplication.shared.connectedScenes
                                    .compactMap({ $0 as? UIWindowScene })
                                    .first?
                                    .windows
                                    .first(where: \.isKeyWindow)
                            else { return }
                            vm.isConnectingCalendar = true
                            defer { vm.isConnectingCalendar = false }
                            do {
                                try await environment.contextService
                                    .authorizeCalendarInteractive(presentingAnchor: anchor)
                                await vm.loadAvailableCalendars()
                            } catch {
                                vm.errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        if vm.isLoadingCalendars || vm.isConnectingCalendar {
                            HStack {
                                ProgressView()
                                Text("接続中...")
                            }
                        } else {
                            Label("Google Calendar と連携", systemImage: "calendar.badge.plus")
                        }
                    }
                }
            } header: {
                Text("Google カレンダー")
            } footer: {
                Text("取得対象のカレンダーにチェックを入れてください。")
                    .font(.caption)
            }

            // RSS ソースセクション
            Section {
                ForEach(vm.config.rssSources, id: \.self) { source in
                    Text(source)
                        .font(.caption)
                        .lineLimit(1)
                }
                .onDelete { vm.removeRssSource(at: $0) }

                Button {
                    vm.showAddRssSheet = true
                } label: {
                    Label("RSS ソースを追加", systemImage: "plus.circle")
                }
            } header: {
                Text("RSS ソース")
            } footer: {
                Text("ニュースを取得する RSS フィードの URL を登録します。")
                    .font(.caption)
            }

            // ユーザープロンプトセクション
            Section {
                TextField(
                    "追加の指示を入力（例：写実的なスタイルで生成してください）",
                    text: $vm.config.userPrompt,
                    axis: .vertical
                )
                .lineLimit(3...6)
            } header: {
                Text("ユーザープロンプト（任意）")
            }

            // 自動生成設定セクション
            Section {
                Toggle("自動生成を有効にする", isOn: Binding(
                    get: { vm.config.autoGenerationEnabled },
                    set: {
                        vm.config.autoGenerationEnabled = $0
                        vm.onAutoGenerationChanged()
                    }
                ))

                if vm.config.autoGenerationEnabled {
                    Picker("生成頻度", selection: Binding(
                        get: { vm.config.runsPerDay },
                        set: {
                            vm.config.runsPerDay = $0
                            vm.onAutoGenerationChanged()
                        }
                    )) {
                        ForEach(ScheduleHelper.supportedRunsPerDay, id: \.self) { count in
                            Text("\(count)回/日").tag(count)
                        }
                    }

                    Toggle("変化がなければスキップ", isOn: $vm.config.skipIfNoChanges)
                    Toggle("Wi-Fi 接続時のみ生成", isOn: $vm.config.wifiOnlyGeneration)
                    Toggle("低電力モード時はスキップ", isOn: $vm.config.skipOnLowPowerMode)
                }
            } header: {
                Text("自動生成")
            } footer: {
                if vm.config.autoGenerationEnabled {
                    Text(
                        "バックグラウンドでスケジュールに従って壁紙を生成します。"
                            + "iOS のバックグラウンド実行制限により、指定時刻に実行されないことがあります。"
                    )
                    .font(.caption)
                }
            }

            // 保存・通知セクション
            Section {
                Toggle("生成画像を自動で写真に保存", isOn: $vm.config.saveToPhotosEnabled)

                Toggle("生成完了を通知する", isOn: Binding(
                    get: { vm.config.notificationsEnabled },
                    set: {
                        vm.config.notificationsEnabled = $0
                        if $0 {
                            Task {
                                await environment.notificationService.requestPermission()
                            }
                        }
                    }
                ))
            } header: {
                Text("保存・通知")
            }
        }
        .sheet(isPresented: $vm.showAddRssSheet) {
            addRssSheet
        }
        .alert("エラー", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // RSS 追加シート
    @ViewBuilder
    private var addRssSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/feed.rss", text: $vm.newRssURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("RSS フィード URL")
                }
            }
            .navigationTitle("RSS ソースを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        vm.newRssURL = ""
                        vm.showAddRssSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        vm.addRssSource()
                    }
                    .disabled(vm.newRssURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
