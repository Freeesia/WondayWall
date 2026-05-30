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
            appIconView

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

    private var appIconView: some View {
        ZStack {
            if let image = currentAppIconImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(18)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var currentAppIconImage: UIImage? {
        if let url = Bundle.main.url(forResource: "WondayWallAppIconDisplay", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return UIImage(named: currentAppIconAssetName)
    }

    private var currentAppIconAssetName: String {
        Bundle.main.object(forInfoDictionaryKey: "WondayWallAppIconAssetName") as? String ?? "AppIcon"
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
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
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

            Label(
                "次へ進むと、初回生成の前に写真ライブラリと通知のアクセス権を確認します。",
                systemImage: "photo.badge.plus"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var generationStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("準備ができました。生成してみましょう！")
                    .font(.title3.bold())
                Text("次の内容をもとに最初の壁紙を作成します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            generationPreviewSection(
                title: "使用する予定",
                systemImage: "calendar",
                emptyText: "今回は予定を使いません",
                isEmpty: vm.generationPreviewEvents.isEmpty
            ) {
                ForEach(Array(vm.generationPreviewEvents.prefix(3))) { event in
                    eventPreviewRow(event)
                }
            }

            generationPreviewSection(
                title: "使用するニュース",
                systemImage: "newspaper",
                emptyText: "今回はニュースを使いません",
                isEmpty: vm.generationPreviewNews.isEmpty
            ) {
                ForEach(Array(vm.generationPreviewNews.prefix(3))) { item in
                    newsPreviewRow(item)
                }
            }
        }
    }

    private func generationPreviewSection<Content: View>(
        title: String,
        systemImage: String,
        emptyText: String,
        isEmpty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            if isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    content()
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func eventPreviewRow(_ event: CalendarEventItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title)
                .font(.subheadline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(event.startTime, style: .date)
                if event.isAllDay {
                    Text("終日")
                } else {
                    Text(event.startTime, style: .time)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func newsPreviewRow(_ item: NewsTopicItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            FaviconImage(urlString: item.url)
                .padding(.top, 2)
            Text(item.title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wallpaperInstructionsStep: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = vm.generatedWallpaperImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 520, maxHeight: 520)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(.systemGray5), Color(.systemGray3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("WondayWall アルバムに保存しました", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text(vm.wallpaperInstructions)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 520, maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private var promptTemplates: [String] {
        [
            "水彩画風で生成してください",
            "写実的な風景で生成してください",
            "ミニマルなデザインで生成してください",
            "イラスト・アニメ調で生成してください",
            "油絵風で生成してください",
        ]
    }
}

#Preview {
    InitialSetupView(onCompleted: {})
        .environmentObject(AppEnvironment())
}
