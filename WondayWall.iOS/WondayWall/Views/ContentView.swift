import SwiftUI

// タブビュー — Home / Data / History / Settings の4タブ構成
struct ContentView: View {
    private enum StartupAlertMode {
        case alreadyGenerating
        case confirmStart
    }

    @State private var selectedTab = 0
    // フォアグラウンド中の生成成功 Toast 表示フラグ
    @State private var showSuccessToast = false
    @State private var startupAlertMode: StartupAlertMode?
    @State private var showStartupAlert = false
    @State private var hasCompletedInitialSetup = false
    @State private var hasLoadedInitialSetupState = false
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !hasLoadedInitialSetupState {
                ProgressView()
            } else if isInitialSetupComplete {
                mainTabs
            } else {
                InitialSetupView {
                    completeInitialSetup()
                }
            }
        }
        .task {
            guard !hasLoadedInitialSetupState else { return }
            hasCompletedInitialSetup = environment.configService.config.hasCompletedInitialSetup
            hasLoadedInitialSetupState = true
            await environment.refreshWidgetStateNow()
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
    }

    private var isInitialSetupComplete: Bool {
        hasCompletedInitialSetup
    }

    private var mainTabs: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("ホーム", systemImage: "house.fill")
                    }
                    .tag(0)
                DataView()
                    .tabItem {
                        Label("データ", systemImage: "calendar.badge.clock")
                    }
                    .tag(1)
                HistoryView()
                    .tabItem {
                        Label("履歴", systemImage: "clock.arrow.circlepath")
                    }
                    .tag(2)
                SettingsView()
                    .tabItem {
                        Label("設定", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openHistoryNotification)
            ) { _ in
                // 通知タップ時は必ずホームタブへ遷移する
                selectedTab = 0
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .generationSucceededInForeground)
            ) { _ in
                // フォアグラウンド中のみ Toast を表示する
                guard scenePhase == .active else { return }
                withAnimation {
                    showSuccessToast = true
                }
            }

            // 生成成功 Toast（上部に重ねて表示）
            if showSuccessToast {
                ToastView(message: "壁紙を生成しました。タップして確認") {
                    withAnimation { showSuccessToast = false }
                    // ホームタブの先頭へ遷移する
                    selectedTab = 0
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { showSuccessToast = false }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSuccessToast)
        .task {
            await evaluateStartupGeneration()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            Task {
                await environment.refreshWidgetStateNow()
                await evaluateStartupGeneration()
            }
        }
        .alert(startupAlertTitle, isPresented: $showStartupAlert) {
            switch startupAlertMode {
            case .alreadyGenerating:
                Button("閉じる") { }
            case .confirmStart:
                Button("あとで", role: .cancel) {
                    environment.backgroundTaskService.scheduleNextBackgroundTask()
                }
                Button("今すぐ生成") {
                    Task {
                        await runStartupManualGeneration()
                    }
                }
            case .none:
                Button("閉じる") { }
            }
        } message: {
            Text(startupAlertMessage)
        }
    }

    private func completeInitialSetup() {
        hasCompletedInitialSetup = true
        selectedTab = 0
        environment.refreshWidgetState()
    }

    private var startupAlertTitle: String {
        switch startupAlertMode {
        case .alreadyGenerating:
            return "壁紙を生成しています"
        case .confirmStart:
            return "起動時の壁紙生成"
        case .none:
            return ""
        }
    }

    private var startupAlertMessage: String {
        switch startupAlertMode {
        case .alreadyGenerating:
            if let progress = environment.generationProgress {
                return "壁紙を生成中です。完了までお待ちください。（進捗: \(progress)%）"
            }
            return "壁紙を生成中です。完了までお待ちください。"
        case .confirmStart:
            return "前回のスケジュール枠がまだ未実行です。今すぐ生成を行いますか？"
        case .none:
            return ""
        }
    }

    private func runStartupManualGeneration() async {
        _ = await environment.coordinator.runManual()
        environment.backgroundTaskService.scheduleNextBackgroundTask()
    }

    private func evaluateStartupGeneration() async {
        guard isInitialSetupComplete else { return }
        guard environment.pendingWidgetGenerationSlotStartedAt == nil else { return }
        guard environment.configService.config.autoGenerationEnabled else { return }
        guard environment.configService.hasMinimumConfigurationForStartupGeneration() else { return }

        if environment.isGenerating {
            await MainActor.run {
                startupAlertMode = .alreadyGenerating
                showStartupAlert = true
            }
            return
        }

        guard await environment.coordinator.isScheduledGenerationNeeded() else {
            environment.backgroundTaskService.scheduleNextBackgroundTask()
            return
        }

        await MainActor.run {
            startupAlertMode = .confirmStart
            showStartupAlert = true
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.scheme == "wondaywall",
              url.host == "widget",
              url.path == "/generate-confirmation",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let slotValue = components.queryItems?.first(where: { $0.name == "slotStartedAt" })?.value,
              let slotStartedAt = ISO8601DateFormatter().date(from: slotValue)
        else { return }

        selectedTab = 0
        startupAlertMode = nil
        showStartupAlert = false
        environment.requestWidgetGenerationConfirmation(slotStartedAt: slotStartedAt)
    }
}

// アプリ内 Toast バナー表示コンポーネント
private struct ToastView: View {
    let message: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppEnvironment())
}
