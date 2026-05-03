import SwiftUI

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
                if viewModel?.isCalendarAccessGranted == true {
                    viewModel?.loadAvailableCalendars()
                }
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
                    SecureField("API キーを入力", text: $vm.googleAiApiKey)
                }
            } header: {
                Text("Google AI API キー")
            } footer: {
                Text("Google AI Studio（aistudio.google.com）で取得できます。")
                    .font(.caption)
            }

            // カレンダーセクション
            Section {
                if vm.isCalendarAccessGranted {
                    // カレンダー選択
                    ForEach(vm.availableCalendars) { calendar in
                        HStack(spacing: 8) {
                            Image(
                                systemName: vm.config.targetCalendarIds.contains(calendar.id)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                vm.config.targetCalendarIds.contains(calendar.id)
                                    ? .blue : .secondary
                            )
                            if let hex = calendar.colorHex, let color = Color(hex: hex) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 10, height: 10)
                            }
                            VStack(alignment: .leading) {
                                Text(calendar.title)
                                Text(calendar.sourceTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { vm.toggleCalendar(calendar.id) }
                    }
                } else {
                    // カレンダーアクセス許可ボタン
                    Button {
                        Task { await vm.requestCalendarAccess() }
                    } label: {
                        if vm.isRequestingCalendarAccess {
                            HStack {
                                ProgressView()
                                Text("許可をリクエスト中...")
                            }
                        } else {
                            Label("カレンダーへのアクセスを許可", systemImage: "calendar.badge.plus")
                        }
                    }
                    .disabled(vm.isRequestingCalendarAccess)
                }
            } header: {
                Text("カレンダー")
            } footer: {
                if vm.isCalendarAccessGranted {
                    Text("取得対象のカレンダーにチェックを入れてください（未選択時は全カレンダーを取得します）。")
                        .font(.caption)
                } else {
                    Text("""
                        WondayWall は壁紙生成の文脈作成のために、カレンダーの予定タイトル・日時・場所・メモを読み取ります。\
                        予定の作成・編集・削除は行いません。
                        """)
                    .font(.caption)
                }
            }

            // RSS ソースセクション
            Section {
                ForEach(vm.config.rssSources, id: \.self) { source in
                    HStack(spacing: 8) {
                        FaviconImage(urlString: source)
                        Text(source)
                            .font(.caption)
                            .lineLimit(1)
                    }
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
                    TextField(
                        "",
                        text: $vm.newRssURL,
                        prompt: Text("https://example.com/feed.rss").foregroundStyle(.secondary)
                    )
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
