import SwiftData
import SwiftUI

struct PlacementTestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dictionaryRepository) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings

    @Query private var progress: [FlashcardProgress]

    @State private var questions: [PlacementQuestion] = []
    @State private var currentIndex = 0
    @State private var answers: [PlacementAnswer] = []
    @State private var selectedChoice: String?
    @State private var isLoading = true
    @State private var result: PlacementResult?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let result {
                    resultView(result)
                } else if currentIndex < questions.count {
                    questionView(questions[currentIndex])
                }
            }
            .navigationTitle(String(localized: "Level Test"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task {
            await loadQuestions()
        }
    }

    @ViewBuilder
    private func questionView(_ q: PlacementQuestion) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    ProgressView(
                        value: Double(currentIndex),
                        total: Double(max(1, questions.count))
                    )
                    HStack {
                        Text("\(currentIndex + 1) / \(questions.count)")
                        Spacer()
                        Text(tierLabel(q.tier))
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        LanguageTag(language: .tajik)
                        if let pos = q.candidate.pos {
                            Text(pos.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text(q.candidate.headword)
                        .font(.system(size: 32, weight: .bold))
                    Text(String(localized: "Choose the matching meaning"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 10) {
                    ForEach(q.choices, id: \.self) { choice in
                        Button {
                            pick(choice: choice, for: q)
                        } label: {
                            HStack {
                                Text(choice)
                                    .font(.body.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                choiceBg(choice: choice, correct: q.candidate.preview),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedChoice != nil)
                    }
                }

                Button(role: .destructive) {
                    skipUnknown(for: q)
                } label: {
                    Text(String(localized: "I don't know"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(selectedChoice != nil)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func resultView(_ res: PlacementResult) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Text(res.cefrLevel.rawValue)
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.accentColor, in: Circle())

            VStack(spacing: 6) {
                Text(res.cefrLevel.title)
                    .font(.title.bold())
                Text("\(res.correctCount) / \(res.totalCount) \(String(localized: "correct"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f%%", res.textRecognitionPercent))
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                    Text(String(localized: "Text recognized"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 4) {
                    Text("~\(res.estimatedKnownWords)")
                        .font(.title2.bold())
                        .foregroundStyle(Color.accentColor)
                    Text(String(localized: "Known words"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(String(localized: "Your Smart Mix will now prioritize vocabulary tailored to your level."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "Start Learning at My Level"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task { await loadQuestions() }
                } label: {
                    Text(String(localized: "Retake Test"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    private func tierLabel(_ tier: Int) -> String {
        switch tier {
        case 1: return String(localized: "Core")
        case 2: return String(localized: "Everyday")
        case 3: return String(localized: "Intermediate")
        default: return String(localized: "Advanced")
        }
    }

    private func choiceBg(choice: String, correct: String) -> Color {
        guard let selectedChoice else { return Color.secondary.opacity(0.12) }
        if choice == correct { return Color.green.opacity(0.22) }
        if choice == selectedChoice { return Color.red.opacity(0.22) }
        return Color.secondary.opacity(0.08)
    }

    private func loadQuestions() async {
        isLoading = true
        currentIndex = 0
        answers = []
        selectedChoice = nil
        result = nil
        let pool = (try? await repository.placementPool(mode: settings.mode)) ?? []
        questions = WordGameEngine.buildPlacementQuestions(pool: pool)
        isLoading = false
    }

    private func pick(choice: String, for question: PlacementQuestion) {
        selectedChoice = choice
        let isCorrect = choice == question.candidate.preview
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            recordAndAdvance(question: question, isCorrect: isCorrect)
        }
    }

    private func skipUnknown(for question: PlacementQuestion) {
        recordAndAdvance(question: question, isCorrect: false)
    }

    private func recordAndAdvance(question: PlacementQuestion, isCorrect: Bool) {
        answers.append(PlacementAnswer(question: question, isCorrect: isCorrect))
        selectedChoice = nil
        if currentIndex + 1 < questions.count {
            currentIndex += 1
        } else {
            finishTest()
        }
    }

    private func finishTest() {
        let evaluated = WordGameEngine.evaluatePlacement(answers: answers)
        settings.applyPlacement(evaluated)

        let now = Date.now
        let future = now.addingTimeInterval(180 * WordGameEngine.daySeconds)
        let byId = Dictionary(uniqueKeysWithValues: progress.map { ($0.entryId, $0) })

        for ans in answers {
            let card = ans.question.candidate
            if ans.isCorrect {
                if let existing = byId[card.entryId] {
                    existing.isKnownSkipped = true
                    existing.masteryStage = 4
                    existing.stabilityDays = 180
                    existing.lastReviewedAt = now
                    existing.nextReviewAt = future
                } else {
                    modelContext.insert(FlashcardProgress(
                        entryId: card.entryId,
                        lang: card.language.rawValue,
                        headword: card.headword,
                        preview: card.preview,
                        repetitions: 1,
                        intervalDays: 180,
                        easeFactor: 2.5,
                        nextReviewAt: future,
                        masteryStage: 4,
                        stabilityDays: 180,
                        lapses: 0,
                        lastReviewedAt: now,
                        isKnownSkipped: true
                    ))
                }
            } else {
                // Queue missed words from the placement test right away for practice (even on retake)
                if let existing = byId[card.entryId] {
                    existing.isKnownSkipped = false
                    existing.masteryStage = 0
                    existing.stabilityDays = 0.25
                    existing.lapses += 1
                    existing.lastReviewedAt = existing.lastReviewedAt ?? now
                    existing.nextReviewAt = now
                } else {
                    modelContext.insert(FlashcardProgress(
                        entryId: card.entryId,
                        lang: card.language.rawValue,
                        headword: card.headword,
                        preview: card.preview,
                        repetitions: 0,
                        intervalDays: 0,
                        easeFactor: 2.5,
                        nextReviewAt: now,
                        masteryStage: 0,
                        stabilityDays: 0.25,
                        lapses: 1,
                        lastReviewedAt: now,
                        isKnownSkipped: false
                    ))
                }
            }
        }
        try? modelContext.save()
        result = evaluated
    }
}
