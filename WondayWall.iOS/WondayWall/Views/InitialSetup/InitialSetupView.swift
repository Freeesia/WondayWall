import SwiftUI

// 初回セットアップ画面
struct InitialSetupView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.displayScale) private var displayScale
    @State private var viewModel: InitialSetupViewModel?
    let onCompleted: @MainActor () -> Void

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                Group {
                    if let viewModel {
                        InitialSetupContentView(
                            vm: viewModel,
                            screenSize: geometry.size,
                            displayScale: displayScale,
                            onCompleted: onCompleted
                        )
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle("初回セットアップ")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            if viewModel == nil {
                let vm = InitialSetupViewModel(environment: environment)
                vm.loadInitialData()
                viewModel = vm
            }
        }
    }
}

private struct InitialSetupContentView: View {
    @Bindable var vm: InitialSetupViewModel
    let screenSize: CGSize
    let displayScale: CGFloat
    let onCompleted: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    stepIndicator
                    header
                    stepContent

                    if let statusText = vm.state.statusText {
                        Label(statusText, systemImage: "hourglass")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let infoMessage = vm.infoMessage {
                        Label(infoMessage, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = vm.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Divider()
            HStack {
                Button("戻る") {
                    vm.goBack()
                }
                .disabled(vm.isFirstStep || vm.isBusy)

                Spacer()

                Button {
                    Task {
                        if vm.isGenerationStep {
                            await vm.runInitialGeneration(
                                screenSize: screenSize,
                                displayScale: displayScale,
                                onCompleted: onCompleted
                            )
                        } else {
                            await vm.advance()
                        }
                    }
                } label: {
                    HStack {
                        if vm.isBusy {
                            ProgressView()
                        }
                        Text(vm.primaryButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isGenerationStep ? !vm.canRunInitialGeneration : vm.isBusy)
            }
            .padding(16)
            .background(.bar)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(InitialSetupStep.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= vm.currentStep.rawValue ? Color.accentColor : Color(.systemGray4))
                    .frame(height: 5)
                    .accessibilityLabel(step.title)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(vm.currentStep.title, systemImage: vm.currentStep.systemImage)
                .font(.title2.bold())
            Text(description(for: vm.currentStep))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch vm.currentStep {
        case .welcome:
            welcomeStep
        case .apiKey:
            apiKeyStep
        case .calendar:
            calendarStep
        case .rss:
            rssStep
        case .automaticGeneration:
            automaticGenerationStep
        case .generation:
            generationStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("予定・ニュース・追加指示をもとに、iPhone 向けの壁紙候補を生成します。", systemImage: "photo")
            Label("iOS では壁紙を直接変更できないため、生成後に写真アプリから手動で設定します。", systemImage: "hand.tap")
            Label("生成画像には予定やニュース由来の情報が反映される場合があります。共有時は内容を確認してください。", systemImage: "person.crop.circle.badge.exclamationmark")

            VStack(alignment: .leading, spacing: 8) {
                setupLink("プライバシーポリシー", url: "https://ww.studiofreesia.com/PrivacyPolicy")
                setupLink("生成画像の利用について", url: "https://ww.studiofreesia.com/GeneratedImageUsage")
            }
            .padding(.top, 4)
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Google AI API キー", text: $vm.googleAiApiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            setupLink("Google AI Studio で API キーを取得する", url: "https://aistudio.google.com/apikey")
        }
    }

    private var calendarStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.canUseCalendar {
                if vm.availableCalendars.isEmpty {
                    ContentUnavailableView(
                        "カレンダーがありません",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("このステップはスキップできます。")
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(vm.availableCalendars) { calendar in
                            calendarRow(calendar)
                            if calendar.id != vm.availableCalendars.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Button {
                    Task { await vm.requestCalendarAccess() }
                } label: {
                    Label(
                        vm.isCalendarDenied ? "設定アプリでアクセスを許可" : "カレンダーアクセスを許可",
                        systemImage: vm.isCalendarDenied ? "gear" : "calendar.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isBusy)
            }

            Text("カレンダーは任意です。接続しない場合も初回セットアップを完了できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var rssStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "https://example.com",
                text: $vm.rssURL
            )
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("空欄のまま進めるとニュースは使いません。ニュースサイト URL を入力した場合は RSS フィードを自動検出します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var automaticGenerationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("自動生成を有効にする", isOn: $vm.automaticGenerationEnabled)
            Toggle("生成完了を通知する", isOn: $vm.notificationsEnabled)

            Text("""
                1日1回、壁紙候補の自動生成を試みます。iOS の制御により、実行時刻は前後したり、実行されない場合があります。壁紙への設定は手動で行ってください。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var generationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("初回生成の前に写真ライブラリへのアクセス権を確認します。", systemImage: "photo.badge.plus")
            Label("生成に成功すると WondayWall アルバムに保存され、通常画面へ移動します。", systemImage: "checkmark.circle")
            Label("失敗した場合はこの画面に留まり、設定を直して再試行できます。", systemImage: "arrow.clockwise")
        }
    }

    private func calendarRow(_ calendar: CalendarSourceItem) -> some View {
        Button {
            vm.toggleCalendar(calendar.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: vm.selectedCalendarIds.contains(calendar.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(vm.selectedCalendarIds.contains(calendar.id) ? Color.accentColor : Color.secondary)
                if let hex = calendar.colorHex, let color = Color(hex: hex) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .foregroundStyle(.primary)
                    Text(calendar.sourceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func setupLink(_ title: String, url: String) -> some View {
        Group {
            if let linkURL = URL(string: url) {
                Link(destination: linkURL) {
                    Label(title, systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private func description(for step: InitialSetupStep) -> String {
        switch step {
        case .welcome:
            return "WondayWall の基本と iOS 版の制約を確認します。"
        case .apiKey:
            return "壁紙生成に必要な Google AI API キーを設定します。"
        case .calendar:
            return "予定を壁紙生成の文脈に使うか選びます。"
        case .rss:
            return "気になるニュースサイトや RSS フィードを 1 件登録できます。"
        case .automaticGeneration:
            return "バックグラウンドでの自動生成と通知を設定します。"
        case .generation:
            return "設定を保存して、最初の壁紙候補を生成します。"
        }
    }
}

#Preview {
    InitialSetupView(onCompleted: {})
        .environmentObject(AppEnvironment())
}
