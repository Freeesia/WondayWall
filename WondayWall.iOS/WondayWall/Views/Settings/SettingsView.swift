import SwiftUI
import BackgroundTasks

// 設定画面 — API キー・カレンダー・RSS・生成設定・通知
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var viewModel: SettingsViewModel?
    @State private var showAbout = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Google AI Studio で API キーを取得できます。")
                        .font(.caption)
                    if let apiKeyURL = URL(string: "https://aistudio.google.com/apikey") {
                        Link("API キーを取得する", destination: apiKeyURL)
                            .font(.caption)
                    }
                }
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
                        Task { 
                            if !vm.isCalendarAccessDenied {
                                await vm.requestCalendarAccess()
                            } else {
                                // 拒否済みの場合は設定アプリを開く
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    await UIApplication.shared.open(url)
                                }
                            }
                         }
                    } label: {
                        if vm.isRequestingCalendarAccess {
                            HStack {
                                ProgressView()
                                Text("許可をリクエスト中...")
                            }
                        } else if vm.isCalendarAccessDenied {
                            Label("設定アプリでアクセスを許可", systemImage: "gear")
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
                    Text("取得対象のカレンダーにチェックを入れてください（未選択時はカレンダーを利用しません）。")
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
                        get: { vm.config.schedule },
                        set: {
                            vm.config.schedule = $0
                            vm.onAutoGenerationChanged()
                        }
                    )) {
                        ForEach(ScheduleHelper.supportedSchedules, id: \.self) { schedule in
                            Text(ScheduleHelper.displayText(for: schedule)).tag(schedule)
                        }
                    }

                    Toggle("変化がなければスキップ", isOn: $vm.config.skipIfNoChanges)
                    Toggle("Wi-Fi 接続時のみ生成", isOn: $vm.config.wifiOnlyGeneration)
                    Toggle("Flex ティアを強制使用", isOn: $vm.config.forceFlexTier)
                }
            } header: {
                Text("自動生成")
            } footer: {
                if vm.config.autoGenerationEnabled {
                    Text(
                        "バックグラウンドでスケジュールに従って壁紙を生成します。"
                            + "iOS のバックグラウンド実行制限により、指定時刻に実行されないことがあります。"
                            + "低電力モード中は自動生成をスキップします。"
                    )
                    .font(.caption)
                }
            }

            // 保存・通知セクション
            Section {
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
                Stepper(
                    "アルバム最大保存枚数: \(vm.config.albumMaxCount)枚",
                    value: Binding(
                        get: { vm.config.albumMaxCount },
                        set: { vm.config.albumMaxCount = $0 }
                    ),
                    in: 1...50
                )
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
                        prompt: Text(verbatim: "https://example.com/feed.rss")
                            .foregroundColor(Color(UIColor.placeholderText))
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

// アプリ情報シート — Win版の About タブに相当
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showDebugSheet = false

    // アプリのバージョンを Info.plist から取得する
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // アプリアイコンと名前
                    VStack(spacing: 8) {
                        if let icon = appIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        Text("WondayWall")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("by Freeesia (StudioFreesia)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)

                    // リンク一覧
                    VStack(spacing: 0) {
                        aboutLinkRow(
                            icon: "globe",
                            title: "公式サイト",
                            url: "https://ww.studiofreesia.com/"
                        )
                        Divider().padding(.leading, 52)
                        aboutLinkRow(
                            icon: "lock.shield",
                            title: "プライバシーポリシー",
                            url: "https://ww.studiofreesia.com/PrivacyPolicy"
                        )
                        Divider().padding(.leading, 52)
                        aboutLinkRow(
                            icon: "doc.text",
                            title: "利用規約",
                            url: "https://ww.studiofreesia.com/Terms_of_Use"
                        )
                        Divider().padding(.leading, 52)
                        aboutLinkRow(
                            icon: "photo.on.rectangle",
                            title: "生成画像の利用について",
                            url: "https://ww.studiofreesia.com/GeneratedImageUsage"
                        )
                        Divider().padding(.leading, 52)
                        aboutLinkRow(
                            icon: "megaphone",
                            title: "リリースノート",
                            url: "https://github.com/Freeesia/WondayWall/releases"
                        )
                        Divider().padding(.leading, 52)
                        aboutLinkRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            title: "GitHub",
                            url: "https://github.com/Freeesia/WondayWall"
                        )
                    }
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    #if DEBUG
                    VStack(spacing: 0) {
                        Button {
                            showDebugSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "ladybug")
                                    .frame(width: 28)
                                    .foregroundStyle(Color.accentColor)
                                Text("デバッグ情報")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    #endif
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("アプリについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            #if DEBUG
            .sheet(isPresented: $showDebugSheet) {
                DebugInfoSheetView()
            }
            #endif
        }
    }

    @ViewBuilder
    private func aboutLinkRow(icon: String, title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 28)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // アプリアイコンを Info.plist から取得する
    private var appIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let lastIcon = iconFiles.last
        else { return nil }
        return UIImage(named: lastIcon)
    }
}

#if DEBUG
// デバッグ情報シート
// BGTaskScheduler に登録されている pending request と設定状態を確認できる
private struct DebugInfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    @State private var isLoading = false
    @State private var pendingRequests: [BGTaskRequest] = []
    @State private var loadedAt: Date?

    private var currentServiceName: String {
        environment.googleAiService is DummyGoogleAiService ? "Dummy" : "Live"
    }

    private var nextLaunchServiceName: String {
        environment.configService.debugConfig.useDummyGoogleAiService ? "Dummy" : "Live"
    }

    private var useDummyServiceBinding: Binding<Bool> {
        Binding(
            get: { environment.configService.debugConfig.useDummyGoogleAiService },
            set: { environment.configService.debugConfig.useDummyGoogleAiService = $0 }
        )
    }

    private var promptDelayBinding: Binding<Int> {
        Binding(
            get: { environment.configService.debugConfig.dummyPromptDelaySeconds },
            set: { environment.configService.debugConfig.dummyPromptDelaySeconds = $0 }
        )
    }

    private var imageDelayBinding: Binding<Int> {
        Binding(
            get: { environment.configService.debugConfig.dummyImageDelaySeconds },
            set: { environment.configService.debugConfig.dummyImageDelaySeconds = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("デバッグ設定") {
                    Toggle("Google AI をダミー実装に切り替える", isOn: useDummyServiceBinding)
                    Text("ON のときは Gemini API を呼ばず、擬似処理を実行します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("切り替えは次回アプリ起動時に反映されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(
                        "プロンプト生成遅延: \(environment.configService.debugConfig.dummyPromptDelaySeconds) 秒",
                        value: promptDelayBinding,
                        in: 1...3600,
                        step: 10
                    )
                    Stepper(
                        "画像生成遅延: \(environment.configService.debugConfig.dummyImageDelaySeconds) 秒",
                        value: imageDelayBinding,
                        in: 1...3600,
                        step: 10
                    )
                    Text("遅延設定は即時反映されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("アプリ状態") {
                    LabeledContent("自動生成") {
                        Text(environment.configService.config.autoGenerationEnabled ? "ON" : "OFF")
                    }
                    LabeledContent("生成中") {
                        Text(environment.isGenerating ? "YES" : "NO")
                    }
                    LabeledContent("Google AI 実装") {
                        Text(currentServiceName)
                    }
                    LabeledContent("次回起動時の実装") {
                        Text(nextLaunchServiceName)
                    }
                    LabeledContent("起動時生成条件") {
                        Text(
                            environment.configService.hasMinimumConfigurationForStartupGeneration()
                                ? "満たす" : "未設定"
                        )
                    }
                    LabeledContent("最終取得") {
                        Text(loadedAt.map(Self.formatter.string(from:)) ?? "未取得")
                    }
                }

                Section("登録済みバックグラウンドタスク") {
                    if pendingRequests.isEmpty {
                        Text(isLoading ? "読み込み中..." : "登録なし")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(pendingRequests.enumerated()), id: \.offset) { _, request in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(request.identifier)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(taskKind(for: request))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let begin = request.earliestBeginDate {
                                    Text("earliestBeginDate: \(Self.formatter.string(from: begin))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let processing = request as? BGProcessingTaskRequest {
                                    Text("network: \(processing.requiresNetworkConnectivity ? "required" : "optional"), power: \(processing.requiresExternalPower ? "required" : "optional")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("デバッグ情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("更新") {
                        Task { await reload() }
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                await reload()
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        pendingRequests = await fetchPendingRequests()
        loadedAt = Date()
    }

    private func fetchPendingRequests() async -> [BGTaskRequest] {
        await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func taskKind(for request: BGTaskRequest) -> String {
        if request is BGProcessingTaskRequest {
            return "BGProcessingTaskRequest"
        }
        if #available(iOS 17.4, *), request is BGContinuedProcessingTaskRequest {
            return "BGContinuedProcessingTaskRequest"
        }
        return "BGTaskRequest"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()
}
#endif
