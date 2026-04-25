import SwiftUI

public struct ContentView: View {
    @ObservedObject var viewModel: TrainerViewModel

    public init(viewModel: TrainerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                NordicPalette.snow.ignoresSafeArea()
                VStack(spacing: 24) {
                    HeaderView()
                    LoginView(viewModel: viewModel, auth: viewModel.auth)
                    ControlsView(viewModel: viewModel)
                    QuestionView(viewModel: viewModel)
                    Spacer(minLength: 0)
                    SyncStatusView(store: viewModel.store)
                }
                .padding(24)
                .frame(maxWidth: 760)
            }
            .task { await viewModel.load() }
        }
    }
}

private struct LoginView: View {
    @ObservedObject var viewModel: TrainerViewModel
    @ObservedObject var auth: AuthCoordinator

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(
                    auth.isSignedIn ? auth.email : "Google Drive",
                    systemImage: auth.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle"
                )
                .foregroundStyle(NordicPalette.ink)

                Spacer()

                Toggle("Anmeldung merken", isOn: Binding(
                    get: { auth.rememberLogin },
                    set: { auth.updateRememberLogin($0) }
                ))
                .toggleStyle(.switch)
            }

            HStack {
                if !auth.isSignedIn {
                    Button {
                        Task { await viewModel.signInAndSync() }
                    } label: {
                        Label("Mit Google anmelden", systemImage: "person.badge.key")
                    }
                }

                Button {
                    Task { await viewModel.syncNow() }
                } label: {
                    Label("Von Drive laden", systemImage: "icloud.and.arrow.down")
                }

                Button {
                    Task { await viewModel.uploadNow() }
                } label: {
                    Label("Zu Drive sichern", systemImage: "icloud.and.arrow.up")
                }

                if auth.isSignedIn {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(auth.statusMessage)
                .font(.footnote)
                .foregroundStyle(NordicPalette.stone)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct ControlsView: View {
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        VStack(spacing: 14) {
            Picker("Lernende", selection: $viewModel.learner) {
                ForEach(Learner.allCases) { learner in
                    Text(learner.rawValue).tag(learner)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Picker("Richtung", selection: $viewModel.directionMode) {
                    ForEach(DirectionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Antwort", selection: $viewModel.answerMode) {
                    ForEach(AnswerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }
            .pickerStyle(.segmented)

            HStack {
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

private struct QuestionView: View {
    @ObservedObject var viewModel: TrainerViewModel

    var body: some View {
        VStack(spacing: 22) {
            if let question = viewModel.currentQuestion {
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

                Text("\(viewModel.remaining) offen")
                    .font(.footnote)
                    .foregroundStyle(NordicPalette.stone)
            } else {
                Text("Fertig")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(NordicPalette.ink)
            }

            if let feedback = viewModel.feedback {
                FeedbackView(feedback: feedback)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: viewModel.feedback?.id)
        .padding(28)
        .background(.white.opacity(0.72))
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
        HStack(spacing: 8) {
            Image(systemName: "icloud.and.arrow.down")
            Text(store.lastSyncMessage)
        }
        .font(.footnote)
        .foregroundStyle(NordicPalette.stone)
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
