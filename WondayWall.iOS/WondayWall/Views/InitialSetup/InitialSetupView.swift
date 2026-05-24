import SwiftUI
import UIKit

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
                                displayScale: displayScale
                            )
                        } else if vm.isCompletionStep {
                            vm.completeSetup(onCompleted: onCompleted)
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
        case .context:
            contextStep
        case .automaticGeneration:
            automaticGenerationStep
        case .generation:
            generationStep
        case .wallpaperInstructions:
            wallpaperInstructionsStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            if let icon = appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            Text("WondayWall へようこそ")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Text("カレンダーの予定やニュースをもとに、\nAI があなた専用の壁紙を自動生成します。\n\n数ステップでセットアップを完了しましょう。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                setupLink("プライバシーポリシー", url: "https://ww.studiofreesia.com/PrivacyPolicy")
                setupLink("生成画像の利用について", url: "https://ww.studiofreesia.com/GeneratedImageUsage")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
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

    private var contextStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ユーザープロンプト")
                    .font(.headline)
                Text("生成する壁紙のスタイルや制約を指示してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("テンプレート")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(promptTemplates, id: \.self) { template in
                    promptTemplateButton(template)
                }
            }

            TextField(
                "",
                text: $vm.userPrompt,
                prompt: Text(verbatim: "例: 水彩画風、青系統で統一して")
                    .foregroundColor(Color(UIColor.placeholderText)),
                axis: .vertical
            )
            .lineLimit(3...6)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text("RSS ニュースソース")
                    .font(.headline)
                Text("ニュースを参考にした壁紙を生成したい場合はニュースサイト URL を追加してください。RSS URL の直接入力もできます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            TextField(
                "",
                text: $vm.rssURL,
                prompt: Text(verbatim: "https://example.com")
                    .foregroundColor(Color(UIColor.placeholderText))
            )
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func promptTemplateButton(_ template: String) -> some View {
        if vm.userPrompt == template {
            Button {
                vm.togglePromptTemplate(template)
            } label: {
                promptTemplateLabel(template)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                vm.togglePromptTemplate(template)
            } label: {
                promptTemplateLabel(template)
            }
            .buttonStyle(.bordered)
        }
    }

    private func promptTemplateLabel(_ template: String) -> some View {
        Text(template)
            .font(.caption)
            .frame(maxWidth: .infinity)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    private var automaticGenerationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("自動生成を有効にする", isOn: $vm.automaticGenerationEnabled)

            if vm.automaticGenerationEnabled {
                Picker("生成頻度", selection: $vm.schedule) {
                    ForEach(ScheduleHelper.supportedSchedules, id: \.self) { schedule in
                        Text(ScheduleHelper.displayText(for: schedule)).tag(schedule)
                    }
                }
                .pickerStyle(.menu)

                Toggle("変化がなければスキップ", isOn: $vm.skipIfNoChanges)
                Toggle("Wi-Fi 接続時のみ生成", isOn: $vm.wifiOnlyGeneration)
                Toggle("Flex ティアを強制使用", isOn: $vm.forceFlexTier)
            }

            Text("""
                バックグラウンドでスケジュールに従って壁紙を生成します。iOS のバックグラウンド実行制限により、指定時刻に実行されないことがあります。低電力モード中は自動生成をスキップします。
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("生成完了を通知する", isOn: $vm.notificationsEnabled)
        }
    }

    private var generationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("写真ライブラリへのアクセスを確認済みです。", systemImage: "photo.badge.plus")
            Label("生成中にアプリを閉じても、継続タスクの通知で進捗を表示します。", systemImage: "clock.badge.checkmark")
            Label("生成に成功すると WondayWall アルバムに保存され、壁紙設定方法を表示します。", systemImage: "checkmark.circle")
            Label("失敗した場合はこの画面に留まり、設定を直して再試行できます。", systemImage: "arrow.clockwise")
        }
    }

    private var wallpaperInstructionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("WondayWall アルバムに最初の壁紙を保存しました。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(vm.wallpaperInstructions)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("ホーム画面では最新の生成結果を確認できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
            return "WondayWall のセットアップを始めます。"
        case .apiKey:
            return "壁紙生成に必要な Google AI API キーを設定します。"
        case .calendar:
            return "予定を壁紙生成の文脈に使うか選びます。"
        case .context:
            return "壁紙のスタイル指示とニュースソースを設定します。"
        case .automaticGeneration:
            return "バックグラウンドでの自動生成と通知を設定します。"
        case .generation:
            return "設定を保存して、最初の壁紙候補を生成します。"
        case .wallpaperInstructions:
            return "保存した画像を壁紙に設定する手順を確認します。"
        }
    }

    private var promptTemplates: [String] {
        [
            "水彩画風で生成してください",
            "写実的な風景で生成してください",
            "ミニマルなデザインで生成してください",
            "イラスト・アニメ調で生成してください",
            "油絵風で生成してください",
        ]
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

#Preview {
    InitialSetupView(onCompleted: {})
        .environmentObject(AppEnvironment())
}
