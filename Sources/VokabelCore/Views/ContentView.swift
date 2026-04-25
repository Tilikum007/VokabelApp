import SwiftUI

public struct ContentView: View {
    @ObservedObject var viewModel: TrainerViewModel

    public init(viewModel: TrainerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            NordicPalette.snow.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    HeaderView()
                    LoginView(viewModel: viewModel, auth: viewModel.auth)
                    SyncStatusView(store: viewModel.store)
                    SettingsView(viewModel: viewModel)
                    TrainingView(viewModel: viewModel)
                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: 760)
            }
        }
        .platformContentFrame()
        .task { await viewModel.load() }
    }
}

private struct LoginView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var viewModel: TrainerViewModel
    @ObservedObject var auth: AuthCoordinator

    var body: some View {
        VStack(spacing: 12) {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    accountLabel
                    rememberToggle
                }
            } else {
                HStack {
                    accountLabel
                    Spacer()
                    rememberToggle
                }
            }

            if isCompact {
                VStack(spacing: 8) {
                    driveButtons
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                HStack {
                    driveButtons
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(auth.statusMessage)
                .font(.footnote)
                .foregroundStyle(NordicPalette.stone)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var accountLabel: some View {
        Label(
            auth.isSignedIn ? auth.email : "Google Drive",
            systemImage: auth.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle"
        )
        .foregroundStyle(NordicPalette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    private var rememberToggle: some View {
        Toggle("Anmeldung merken", isOn: Binding(
            get: { auth.rememberLogin },
            set: { auth.updateRememberLogin($0) }
        ))
        .toggleStyle(.switch)
        .lineLimit(1)
    }

    @ViewBuilder
    private var driveButtons: some View {
        if !auth.isSignedIn {
            Button {
                Task { await viewModel.signInAndSync() }
            } label: {
                Label("Anmelden", systemImage: "person.badge.key")
                    .frame(maxWidth: isCompact ? .infinity : nil)
            }
            .disabled(auth.isSigningIn || viewModel.store.isSyncing)
        }

        Button {
            Task { await viewModel.syncNow() }
        } label: {
            Label("Laden", systemImage: "icloud.and.arrow.down")
                .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .disabled(auth.isSigningIn || viewModel.store.isSyncing)

        Button {
            Task { await viewModel.uploadNow() }
        } label: {
            Label("Sichern", systemImage: "icloud.and.arrow.up")
                .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .disabled(auth.isSigningIn || viewModel.store.isSyncing)

        if auth.isSignedIn {
            Button(role: .destructive) {
                auth.signOut()
            } label: {
                Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: isCompact ? .infinity : nil)
            }
            .disabled(auth.isSigningIn || viewModel.store.isSyncing)
        }
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Norsk")
                .font(.system(size: 44, weight: .semibold, design: .serif))
                .foregroundStyle(NordicPalette.ink)
            Text("Vokabeltraining")
                .font(.headline)
                .foregroundStyle(NordicPalette.stone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Einstellungen", systemImage: "slider.horizontal.3")

            VStack(spacing: 14) {
                Picker("Lernende", selection: $viewModel.learner) {
                    ForEach(Learner.allCases) { learner in
                        Text(learner.rawValue).tag(learner)
                    }
                }
                .pickerStyle(.segmented)

                AdaptiveControlsStack(isCompact: isCompact) {
                    Picker("Richtung", selection: $viewModel.directionMode) {
                        ForEach(DirectionMode.allCases) { mode in
                            Text(isCompact ? mode.shortTitle : mode.rawValue).tag(mode)
                        }
                    }

                    Picker("Antwort", selection: $viewModel.answerMode) {
                        ForEach(AnswerMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }
                .pickerStyle(.segmented)

                AdaptiveControlsStack(isCompact: isCompact) {
                    Picker("Level", selection: Binding(
                        get: { viewModel.filter.level ?? -1 },
                        set: { viewModel.filter.level = $0 == -1 ? nil : $0 }
                    )) {
                        Text("Alle Level").tag(-1)
                        ForEach(0...5, id: \.self) { Text("Level \($0)").tag($0) }
                    }

                    Picker("Herkunft", selection: Binding(
                        get: { viewModel.filter.source ?? "" },
                        set: { viewModel.filter.source = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Alle Herkuenfte").tag("")
                        ForEach(viewModel.sources, id: \.self) { Text($0).tag($0) }
                    }

                    Picker("Lektion", selection: Binding(
                        get: { viewModel.filter.lesson ?? "" },
                        set: { viewModel.filter.lesson = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Alle Lektionen").tag("")
                        ForEach(viewModel.lessons, id: \.self) { Text($0).tag($0) }
                    }
                }

                AdaptiveControlsStack(isCompact: isCompact) {
                    Picker("Woerter", selection: $viewModel.sessionSize) {
                        ForEach(viewModel.sessionSizeOptions, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }

                    Button {
                        viewModel.startSession()
                    } label: {
                        Label("Training starten", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NordicPalette.fjord)
                }
            }
        }
        .sectionCard()
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
}

private struct TrainingView: View {
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Training", systemImage: "graduationcap")
            ProgressSummaryView(viewModel: viewModel)

            if let question = viewModel.currentQuestion {
                VStack(spacing: 22) {
                    Text(question.direction == .germanToNorwegian ? "Deutsch -> Norwegisch" : "Norwegisch -> Deutsch")
                        .font(.caption)
                        .foregroundStyle(NordicPalette.stone)

                    Text(question.prompt)
                        .font(.system(size: 38, weight: .medium, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(NordicPalette.ink)
                        .minimumScaleFactor(0.65)

                    if viewModel.answerMode == .choice {
                        VStack(spacing: 10) {
                            ForEach(question.options, id: \.self) { option in
                                Button {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                                        viewModel.choose(option)
                                    }
                                } label: {
                                    Text(option)
                                        .frame(maxWidth: .infinity)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.78)
                                }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                            }
                        }
                    } else {
                        TextField("Antwort", text: $viewModel.answerText)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .onSubmit { viewModel.submitTypedAnswer() }

                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                                viewModel.submitTypedAnswer()
                            }
                        } label: {
                            Label("Antwort pruefen", systemImage: "return")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NordicPalette.red)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Fertig")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(NordicPalette.ink)
                    .frame(maxWidth: .infinity)
            }

            if let feedback = viewModel.feedback {
                FeedbackView(feedback: feedback)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(height: 64)
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.feedback?.id)
        .sectionCard()
    }
}

private struct SectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(NordicPalette.ink)
    }
}

private struct ProgressSummaryView: View {
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    progressSegment(value: viewModel.correctCount, total: viewModel.sessionTotal, width: proxy.size.width, color: NordicPalette.fjord)
                    progressSegment(value: viewModel.wrongCount, total: viewModel.sessionTotal, width: proxy.size.width, color: NordicPalette.red)
                    progressSegment(value: viewModel.remaining, total: viewModel.sessionTotal, width: proxy.size.width, color: NordicPalette.stone.opacity(0.34))
                }
                .frame(width: proxy.size.width, height: 8)
                .background(NordicPalette.stone.opacity(0.16))
                .clipShape(Capsule())
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                ProgressPill(title: "Richtig", value: viewModel.correctCount, color: NordicPalette.fjord)
                ProgressPill(title: "Falsch", value: viewModel.wrongCount, color: NordicPalette.red)
                ProgressPill(title: "Offen", value: viewModel.remaining, color: NordicPalette.stone)
            }
        }
    }

    private func progressSegment(value: Int, total: Int, width: CGFloat, color: Color) -> some View {
        let segmentWidth = total > 0 ? width * CGFloat(max(value, 0)) / CGFloat(total) : 0
        return Rectangle()
            .fill(color)
            .frame(width: segmentWidth)
    }
}

private struct ProgressPill: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(NordicPalette.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AdaptiveControlsStack<Content: View>: View {
    let isCompact: Bool
    let content: Content

    init(isCompact: Bool, @ViewBuilder content: () -> Content) {
        self.isCompact = isCompact
        self.content = content()
    }

    var body: some View {
        if isCompact {
            VStack(spacing: 10) {
                content
            }
        } else {
            HStack {
                content
            }
        }
    }
}

private struct FeedbackView: View {
    let feedback: FeedbackState

    var body: some View {
        HStack(spacing: 12) {
            Text(feedback.emoji)
                .font(.title2)
                .scaleEffect(1.08)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.headline)
                Text("Loesung: \(feedback.expectedAnswer)")
                    .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
        .frame(minHeight: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var color: Color {
        switch feedback.grade {
        case .correct:
            NordicPalette.fjord
        case .almost:
            NordicPalette.gold
        case .wrong:
            NordicPalette.red
        }
    }
}

private struct SyncStatusView: View {
    @ObservedObject var store: VocabularyStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .symbolEffect(.pulse, isActive: store.isSyncing)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(store.lastSyncMessage)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = store.lastSyncDate {
                    Text(date, style: .time)
                        .font(.caption)
                        .foregroundStyle(NordicPalette.stone)
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(14)
        .frame(maxWidth: 760)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: store.lastSyncMessage)
    }

    private var title: String {
        switch store.lastSyncResult {
        case .idle:
            "Synchronisation"
        case .working:
            "Synchronisation laeuft"
        case .success:
            "Synchronisation erfolgreich"
        case .failure:
            "Synchronisation fehlgeschlagen"
        }
    }

    private var iconName: String {
        switch store.lastSyncResult {
        case .idle:
            "icloud"
        case .working:
            "arrow.triangle.2.circlepath.icloud"
        case .success:
            "checkmark.icloud"
        case .failure:
            "exclamationmark.icloud"
        }
    }

    private var color: Color {
        switch store.lastSyncResult {
        case .idle, .working:
            NordicPalette.stone
        case .success:
            NordicPalette.fjord
        case .failure:
            NordicPalette.red
        }
    }
}

private enum NordicPalette {
    static let snow = Color(red: 0.96, green: 0.97, blue: 0.96)
    static let ink = Color(red: 0.08, green: 0.13, blue: 0.17)
    static let stone = Color(red: 0.42, green: 0.47, blue: 0.50)
    static let fjord = Color(red: 0.05, green: 0.32, blue: 0.42)
    static let red = Color(red: 0.73, green: 0.08, blue: 0.13)
    static let gold = Color(red: 0.58, green: 0.39, blue: 0.08)
}

private extension View {
    func sectionCard() -> some View {
        self
            .padding(18)
            .background(.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    func platformContentFrame() -> some View {
        #if os(macOS)
        self.frame(width: 900, height: 760)
        #else
        self
        #endif
    }
}
