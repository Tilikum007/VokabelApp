import SwiftUI

public struct ContentView: View {
    @ObservedObject var viewModel: TrainerViewModel
    @State private var showsSettings = false

    public init(viewModel: TrainerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            NordicPalette.snow.ignoresSafeArea()
            ScrollView {
                if showsSettings {
                    SettingsScreen(viewModel: viewModel) {
                        showsSettings = false
                    }
                    .padding(24)
                    .frame(maxWidth: 760)
                } else {
                    TrainingScreen(viewModel: viewModel) {
                        showsSettings = true
                    }
                    .padding(24)
                    .frame(maxWidth: 760)
                }
            }
        }
        .platformContentFrame()
        .task { await viewModel.load() }
    }
}

private struct TrainingScreen: View {
    @ObservedObject var viewModel: TrainerViewModel
    let showSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            TopBar(
                title: "Norsk",
                subtitle: "Vokabeltraining"
            ) {
                Button(action: showSettings) {
                    IconActionLabel(title: "Einstellungen", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }

            SessionControlsView(viewModel: viewModel)
            TrainingView(viewModel: viewModel)
            Spacer(minLength: 0)
        }
    }
}

private struct SettingsScreen: View {
    @ObservedObject var viewModel: TrainerViewModel
    let goBack: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            TopBar(
                title: "Einstellungen",
                subtitle: "Sync und Trainingsfilter"
            ) {
                Button(action: goBack) {
                    IconActionLabel(title: "Zurueck", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
            }

            LoginView(viewModel: viewModel, auth: viewModel.auth)
            SyncStatusView(store: viewModel.store)
            SettingsView(viewModel: viewModel)
            Spacer(minLength: 0)
        }
    }
}

private struct TopBar<Action: View>: View {
    let title: String
    let subtitle: String
    let action: Action

    init(title: String, subtitle: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.subtitle = subtitle
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .foregroundStyle(NordicPalette.ink)
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(NordicPalette.stone)
            }
            Spacer(minLength: 12)
            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            } else {
                HStack {
                    driveButtons
                }
            }

            Text(auth.statusMessage)
                .font(.footnote)
                .foregroundStyle(NordicPalette.stone)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(NordicPalette.card)
        .cardStroke()
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
                DriveActionLabel(title: "Anmelden", systemImage: "person.badge.key", isCompact: isCompact)
            }
            .buttonStyle(.plain)
            .disabled(auth.isSigningIn || viewModel.store.isSyncing)
        }

        Button {
            Task { await viewModel.syncNow() }
        } label: {
            DriveActionLabel(title: "Laden", systemImage: "icloud.and.arrow.down", isCompact: isCompact)
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn || viewModel.store.isSyncing)

        Button {
            Task { await viewModel.uploadNow() }
        } label: {
            DriveActionLabel(title: "Sichern", systemImage: "icloud.and.arrow.up", isCompact: isCompact)
        }
        .buttonStyle(.plain)
        .disabled(auth.isSigningIn || viewModel.store.isSyncing)

        if auth.isSignedIn {
            Button(role: .destructive) {
                auth.signOut()
            } label: {
                DriveActionLabel(title: "Abmelden", systemImage: "rectangle.portrait.and.arrow.right", isCompact: isCompact, isDestructive: true)
            }
            .buttonStyle(.plain)
            .disabled(auth.isSigningIn || viewModel.store.isSyncing)
        }
    }
}

private struct DriveActionLabel: View {
    let title: String
    let systemImage: String
    let isCompact: Bool
    var isDestructive = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(isDestructive ? NordicPalette.flagRed : NordicPalette.flagBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: isCompact ? .infinity : nil)
            .background(NordicPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isDestructive ? NordicPalette.flagRed : NordicPalette.flagBlue, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct IconActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(NordicPalette.flagBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(NordicPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NordicPalette.flagBlue, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SessionControlsView: View {
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            MenuSelectField(title: "Woerter", value: "\(viewModel.sessionSize) Woerter") {
                ForEach(viewModel.sessionSizeOptions, id: \.self) { size in
                    Button("\(size) Woerter") {
                        viewModel.sessionSize = size
                    }
                }
            }

            Button {
                viewModel.startSession()
            } label: {
                Label("Training starten", systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NordicPalette.flagBlue)
            .frame(maxWidth: .infinity)
        }
        .sectionCard()
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Einstellungen", systemImage: "slider.horizontal.3")

            VStack(spacing: 14) {
                OptionGroup(title: "Lernende") {
                    ForEach(Learner.allCases) { learner in
                        OptionChip(
                            title: learner.rawValue,
                            isSelected: viewModel.learner == learner
                        ) {
                            viewModel.learner = learner
                        }
                    }
                }

                VStack(spacing: 10) {
                    OptionGroup(title: "Richtung") {
                        ForEach(DirectionMode.allCases) { mode in
                            OptionChip(
                                title: mode.shortTitle,
                                isSelected: viewModel.directionMode == mode
                            ) {
                                viewModel.directionMode = mode
                            }
                        }
                    }

                    OptionGroup(title: "Antwort") {
                        ForEach(AnswerMode.allCases) { mode in
                            OptionChip(
                                title: mode.rawValue,
                                isSelected: viewModel.answerMode == mode
                            ) {
                                viewModel.answerMode = mode
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    MenuSelectField(title: "Level", value: levelTitle) {
                        Button("Alle Level") {
                            viewModel.filter.level = nil
                        }
                        ForEach(0...5, id: \.self) { level in
                            Button("Level \(level)") {
                                viewModel.filter.level = level
                            }
                        }
                    }

                    MenuSelectField(title: "Herkunft", value: viewModel.filter.source ?? "Alle Herkuenfte") {
                        Button("Alle Herkuenfte") {
                            viewModel.filter.source = nil
                        }
                        ForEach(viewModel.sources, id: \.self) { source in
                            Button(source) {
                                viewModel.filter.source = source
                            }
                        }
                    }

                    MenuSelectField(title: "Lektion", value: viewModel.filter.lesson ?? "Alle Lektionen") {
                        Button("Alle Lektionen") {
                            viewModel.filter.lesson = nil
                        }
                        ForEach(viewModel.lessons, id: \.self) { lesson in
                            Button(lesson) {
                                viewModel.filter.lesson = lesson
                            }
                        }
                    }
                }
            }
        }
        .sectionCard()
    }

    private var levelTitle: String {
        if let level = viewModel.filter.level {
            "Level \(level)"
        } else {
            "Alle Level"
        }
    }
}

private struct OptionGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NordicPalette.stone)
            HStack(spacing: 8) {
                content
            }
        }
    }
}

private struct OptionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : NordicPalette.flagBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(isSelected ? NordicPalette.flagBlue : NordicPalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NordicPalette.flagBlue, lineWidth: 1.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MenuSelectField<Content: View>: View {
    let title: String
    let value: String
    let content: Content

    init(title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NordicPalette.stone)
            Menu {
                content
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(NordicPalette.flagBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicPalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NordicPalette.flagBlue, lineWidth: 1.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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
                                    ChoiceOptionLabel(option: option)
                                }
                                .buttonStyle(.plain)
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
                        .tint(NordicPalette.flagRed)
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
                    progressSegment(value: viewModel.correctCount, total: viewModel.sessionTotal, width: proxy.size.width, color: NordicPalette.flagBlue)
                    progressSegment(value: viewModel.wrongCount, total: viewModel.sessionTotal, width: proxy.size.width, color: NordicPalette.flagRed)
                    progressSegment(value: viewModel.remaining, total: viewModel.sessionTotal, width: proxy.size.width, color: NordicPalette.stone.opacity(0.42))
                }
                .frame(width: proxy.size.width, height: 8)
                .background(NordicPalette.stone.opacity(0.16))
                .clipShape(Capsule())
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                ProgressPill(title: "Richtig", value: viewModel.correctCount, color: NordicPalette.flagBlue)
                ProgressPill(title: "Falsch", value: viewModel.wrongCount, color: NordicPalette.flagRed)
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

private struct ChoiceOptionLabel: View {
    let option: String

    var body: some View {
        Text(option)
            .font(.body.weight(.semibold))
            .foregroundStyle(NordicPalette.flagBlue)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(NordicPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NordicPalette.flagBlue, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            NordicPalette.flagBlue
        case .almost:
            NordicPalette.gold
        case .wrong:
            NordicPalette.flagRed
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
            NordicPalette.flagBlue
        case .failure:
            NordicPalette.flagRed
        }
    }
}

private enum NordicPalette {
    static let snow = Color(red: 0.985, green: 0.988, blue: 0.992)
    static let card = Color.white
    static let ink = Color(red: 0.03, green: 0.06, blue: 0.10)
    static let stone = Color(red: 0.24, green: 0.29, blue: 0.34)
    static let flagBlue = Color(red: 0.00, green: 0.13, blue: 0.36)
    static let flagRed = Color(red: 0.73, green: 0.02, blue: 0.10)
    static let border = Color(red: 0.72, green: 0.77, blue: 0.84)
    static let gold = Color(red: 0.48, green: 0.30, blue: 0.02)
}

private extension View {
    func sectionCard() -> some View {
        self
            .padding(18)
            .background(NordicPalette.card)
            .cardStroke()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func cardStroke() -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NordicPalette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    func platformContentFrame() -> some View {
        #if os(macOS)
        self.frame(minWidth: 980, idealWidth: 1120, minHeight: 780, idealHeight: 860)
        #else
        self
        #endif
    }
}
