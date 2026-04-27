import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct ContentView: View {
    @ObservedObject var viewModel: TrainerViewModel
    @State private var showsSettings = false
    @State private var showsWelcomePopup = false
    @State private var didPresentWelcome = false

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
        .overlay {
            if showsWelcomePopup {
                CharacterPopup(imageName: "wave", title: "Hei, god dag!")
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .platformContentFrame()
        .task {
            await viewModel.load()
            guard !didPresentWelcome else { return }
            didPresentWelcome = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showsWelcomePopup = true
            }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.22)) {
                showsWelcomePopup = false
            }
        }
    }
}

private struct TrainingScreen: View {
    @ObservedObject var viewModel: TrainerViewModel
    let showSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            TopBar(
                title: "Norsk",
                subtitle: "Vokabeltraining"
            ) {
                Button(action: showSettings) {
                    IconOnlyActionLabel(title: "Einstellungen", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einstellungen")
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
            TrainingTitleBar(
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let subtitle: String
    let action: Action

    init(title: String, subtitle: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.subtitle = subtitle
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                titleLine
                Spacer(minLength: 8)
                action
            }
            Text(subtitle)
                .font(.headline)
                .foregroundStyle(NordicPalette.stone)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleLine: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: horizontalSizeClass == .compact ? 48 : 40, weight: .semibold, design: .serif))
                .foregroundStyle(NordicPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            NorwegianFlag()
        }
    }
}

private struct TrainingTitleBar<Action: View>: View {
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

        Button {
            Task { await viewModel.checkVocabularyUpdates() }
        } label: {
            DriveActionLabel(title: "Vokabel-Update suchen", systemImage: "text.badge.plus", isCompact: isCompact)
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

private struct IconOnlyActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(NordicPalette.flagBlue)
            .frame(width: 48, height: 48)
            .background(NordicPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NordicPalette.flagBlue, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(title)
    }
}

private struct SessionControlsView: View {
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
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
        .padding(12)
        .background(NordicPalette.card)
        .cardStroke()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    MenuSelectField(
                        title: "Level",
                        value: viewModel.filter.level.map { "Level \($0)" } ?? (viewModel.levels.isEmpty ? "Keine Level" : "Alle Level"),
                        isEnabled: !viewModel.levels.isEmpty
                    ) {
                        Button("Alle Level") {
                            viewModel.filter.level = nil
                        }
                        ForEach(viewModel.levels, id: \.self) { level in
                            Button("Level \(level)") {
                                viewModel.filter.level = level
                            }
                        }
                    }

                    MenuSelectField(
                        title: "Herkunft",
                        value: viewModel.filter.source ?? (viewModel.sources.isEmpty ? "Keine Herkuenfte" : "Alle Herkuenfte"),
                        isEnabled: !viewModel.sources.isEmpty
                    ) {
                        Button("Alle Herkuenfte") {
                            viewModel.filter.source = nil
                        }
                        ForEach(viewModel.sources, id: \.self) { source in
                            Button(source) {
                                viewModel.filter.source = source
                            }
                        }
                    }

                    MenuSelectField(
                        title: "Lektion",
                        value: viewModel.filter.lesson ?? (viewModel.lessons.isEmpty ? "Keine Lektionen" : "Alle Lektionen"),
                        isEnabled: !viewModel.lessons.isEmpty
                    ) {
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
    let isEnabled: Bool
    let content: Content

    init(title: String, value: String, isEnabled: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.isEnabled = isEnabled
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
                .foregroundStyle(isEnabled ? NordicPalette.flagBlue : NordicPalette.stone)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NordicPalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isEnabled ? NordicPalette.flagBlue : NordicPalette.border, lineWidth: 1.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }
}

private struct TrainingView: View {
    @ObservedObject var viewModel: TrainerViewModel
    @State private var characterFeedback: FeedbackState?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Training", systemImage: "graduationcap")
            ProgressSummaryView(viewModel: viewModel)

            if let question = viewModel.currentQuestion {
                VStack(spacing: 16) {
                    Text(question.direction == .germanToNorwegian ? "Deutsch -> Norwegisch" : "Norwegisch -> Deutsch")
                        .font(.caption)
                        .foregroundStyle(NordicPalette.stone)

                    Text(question.prompt)
                        .font(.system(size: 34, weight: .medium, design: .serif))
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
                VStack(spacing: 10) {
                    Text(viewModel.sessionTotal == 0 ? "Keine Session" : "Fertig")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(NordicPalette.ink)
                    if let sessionMessage = viewModel.sessionMessage {
                        Text(sessionMessage)
                            .font(.callout)
                            .foregroundStyle(NordicPalette.stone)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if let feedback = viewModel.feedback {
                FeedbackView(feedback: feedback)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(height: 50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.feedback?.id)
        .overlay {
            if let feedback = characterFeedback {
                CharacterPopup(imageName: feedback.characterImageName, title: feedback.characterTitle)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.feedback?.id) { _, _ in
            guard let feedback = viewModel.feedback else { return }
            Task {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    characterFeedback = feedback
                }
                try? await Task.sleep(for: .seconds(1.15))
                withAnimation(.easeOut(duration: 0.18)) {
                    if characterFeedback?.id == feedback.id {
                        characterFeedback = nil
                    }
                }
            }
        }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
        .frame(minHeight: 54)
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

private struct NorwegianFlag: View {
    var body: some View {
        ZStack {
            NordicPalette.flagRed
            Rectangle()
                .fill(.white)
                .frame(width: 10)
                .offset(x: -8)
            Rectangle()
                .fill(.white)
                .frame(height: 10)
            Rectangle()
                .fill(NordicPalette.flagBlue)
                .frame(width: 5)
                .offset(x: -8)
            Rectangle()
                .fill(NordicPalette.flagBlue)
                .frame(height: 5)
        }
        .frame(width: 42, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(NordicPalette.border, lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .accessibilityLabel("Norwegische Flagge")
    }
}

private struct CharacterPopup: View {
    let imageName: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            BundledPNGImage(name: imageName)
                .frame(width: 150, height: 145)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(NordicPalette.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NordicPalette.flagBlue.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .allowsHitTesting(false)
    }
}

private struct BundledPNGImage: View {
    let name: String

    var body: some View {
        if let image = PlatformImage.loadBundledPNG(named: name) {
            image.swiftUIImage
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(NordicPalette.flagBlue.opacity(0.55))
        }
    }
}

private struct PlatformImage {
    #if os(iOS)
    let raw: UIImage

    var swiftUIImage: Image {
        Image(uiImage: raw)
    }
    #elseif os(macOS)
    let raw: NSImage

    var swiftUIImage: Image {
        Image(nsImage: raw)
    }
    #endif

    static func loadBundledPNG(named name: String) -> PlatformImage? {
        for bundle in Bundle.vokabelImageBundles {
            if let url = bundle.url(forResource: name, withExtension: "png"),
               let image = load(from: url) {
                return PlatformImage(raw: image)
            }
        }
        return nil
    }

    private static func load(from url: URL) -> RawImage? {
        #if os(iOS)
        UIImage(contentsOfFile: url.path)
        #elseif os(macOS)
        NSImage(contentsOf: url)
        #endif
    }

    #if os(iOS)
    private typealias RawImage = UIImage
    #elseif os(macOS)
    private typealias RawImage = NSImage
    #endif
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
            .padding(14)
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

private final class ContentViewBundleToken {}

private extension Bundle {
    static var vokabelCoreResources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: ContentViewBundleToken.self)
        #endif
    }

    static var vokabelImageBundles: [Bundle] {
        var bundles = [Bundle.vokabelCoreResources, .main]
        bundles.append(contentsOf: Bundle.allFrameworks)
        bundles.append(contentsOf: Bundle.allBundles)
        return bundles
    }
}
