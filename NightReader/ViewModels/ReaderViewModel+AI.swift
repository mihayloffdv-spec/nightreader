import Foundation
@preconcurrency import PDFKit

// MARK: - AI Features (explain, translate, chat, smart highlights, chapter review)

extension ReaderViewModel {

    // MARK: - AI Actions (explain / translate)

    func requestExplain(text: String) {
        requestAIAction(.explain, text: text)
    }

    func requestTranslate(text: String) {
        requestAIAction(.translate, text: text)
    }

    func retryAIAction() {
        requestAIAction(aiActionType, text: aiSelectedText)
    }

    func dismissAISheet() {
        aiTask?.cancel()
        aiTask = nil
        showAISheet = false
        aiResponseState = .idle
    }

    internal func requestAIAction(_ action: AIActionType, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard trimmed.count <= Self.maxAITextLength else {
            aiActionType = action
            aiSelectedText = String(trimmed.prefix(200))
            aiResponseState = .error("Выберите фрагмент короче \(Self.maxAITextLength) символов.")
            showAISheet = true
            return
        }

        guard KeychainManager.hasAPIKey else {
            showAPIKeySettings = true
            return
        }

        aiActionType = action
        aiSelectedText = trimmed
        aiResponseState = .loading
        showAISheet = true

        aiTask?.cancel()
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.aiTask = nil }
            do {
                let response: String
                switch action {
                case .explain:
                    response = try await ClaudeAPIService.explain(text: trimmed)
                case .translate:
                    response = try await ClaudeAPIService.translate(text: trimmed)
                }
                guard !Task.isCancelled else { return }
                self.aiResponseState = .success(response)
            } catch {
                guard !Task.isCancelled else { return }
                self.aiResponseState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Chat

    func sendChatMessage() {
        let text = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, KeychainManager.hasAPIKey else { return }
        chatInputText = ""
        chatMessages.append(ChatMessage(role: "user", content: text))

        chatTask?.cancel()
        chatTask = Task { [weak self] in
            guard let self else { return }
            let chapters = await MainActor.run { self.chapters }
            let chapter = await MainActor.run { self.currentChapter }
            let doc = await MainActor.run { self.originalDocument ?? self.document }
            let chapterText = Self.extractChapterText(for: chapter ?? chapters.first ?? Chapter(id: 0, title: "", pageIndex: 0, level: 0, source: .autoDetected), in: doc, chapters: chapters)

            do {
                let history = await MainActor.run { self.chatMessages }
                let response = try await ClaudeAPIService.askQuestion(
                    question: text,
                    bookTitle: await MainActor.run { self.book.title },
                    chapterText: chapterText,
                    history: history
                )
                await MainActor.run {
                    self.chatMessages.append(ChatMessage(role: "assistant", content: response))
                }
            } catch {
                // Don't show error bubble if this task was cancelled (user sent a new message)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.chatMessages.append(ChatMessage(role: "assistant", content: "Ошибка: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Chapter Review

    func triggerChapterReview() {
        guard let chapter = currentChapter,
              !reviewedChapters.contains(chapter.id),
              KeychainManager.hasAPIKey else { return }

        if annotationStore?.chapterReview(forChapter: chapter.id) != nil {
            reviewedChapters.insert(chapter.id)
            return
        }

        isGeneratingQuestions = true
        Task { [weak self] in
            guard let self else { return }
            let chapters = await MainActor.run { self.chapters }
            let doc = await MainActor.run { self.originalDocument ?? self.document }
            let chapterText = Self.extractChapterText(for: chapter, in: doc, chapters: chapters)

            do {
                let result = try await ClaudeAPIService.generateChapterQuestions(
                    chapterText: chapterText,
                    bookTitle: await MainActor.run { self.book.title },
                    chapterTitle: chapter.title
                )
                guard !result.questions.isEmpty else {
                    await MainActor.run { self.isGeneratingQuestions = false }
                    return
                }
                let review = ChapterReview(
                    chapterIndex: chapter.id,
                    chapterTitle: chapter.title,
                    questions: result.questions
                )
                await MainActor.run {
                    self.annotationStore?.addChapterReview(review)
                    self.currentChapterReview = review
                    self.reviewedChapters.insert(chapter.id)
                    self.isGeneratingQuestions = false
                    self.showChapterReview = true
                }
            } catch {
                await MainActor.run { self.isGeneratingQuestions = false }
            }
        }
    }

    // MARK: - Smart Highlights

    // MARK: - Argument Map

    func generateArgumentMap() {
        guard let chapter = currentChapter,
              KeychainManager.hasAPIKey else { return }

        // Check if already generated
        if let existing = annotationStore?.argumentMap(forChapter: chapter.id) {
            currentArgumentMap = existing
            showArgumentMap = true
            return
        }

        isGeneratingArgumentMap = true
        Task { [weak self] in
            guard let self else { return }
            let chapters = await MainActor.run { self.chapters }
            let doc = await MainActor.run { self.originalDocument ?? self.document }
            let chapterText = Self.extractChapterText(for: chapter, in: doc, chapters: chapters)

            do {
                let result = try await ClaudeAPIService.analyzeArguments(
                    text: chapterText,
                    bookTitle: await MainActor.run { self.book.title },
                    chapterTitle: chapter.title
                )
                guard !result.thesis.isEmpty else {
                    await MainActor.run { self.isGeneratingArgumentMap = false }
                    return
                }
                let map = ArgumentMap(
                    chapterIndex: chapter.id,
                    chapterTitle: chapter.title,
                    thesis: result.thesis,
                    evidence: result.evidence,
                    conclusion: result.conclusion
                )
                await MainActor.run {
                    self.annotationStore?.addArgumentMap(map)
                    self.currentArgumentMap = map
                    self.isGeneratingArgumentMap = false
                    self.showArgumentMap = true
                }
            } catch {
                await MainActor.run { self.isGeneratingArgumentMap = false }
            }
        }
    }

    func toggleSmartHighlights() {
        smartHighlightsEnabled.toggle()
        AppSettings.shared.smartHighlightsEnabled = smartHighlightsEnabled
        if !smartHighlightsEnabled {
            analysisTask?.cancel()
            analysisTask = nil
            isAnalyzingChapter = false
        } else if let chapter = currentChapter {
            triggerSmartHighlightAnalysis(for: chapter)
        }
    }

    func reanalyzeCurrentChapter() {
        guard let chapter = currentChapter else { return }
        lastAnalyzedChapterIndex = nil
        triggerSmartHighlightAnalysis(for: chapter, replaceExisting: true)
    }

    internal func triggerSmartHighlightAnalysis(for chapter: Chapter, replaceExisting: Bool = false) {
        guard smartHighlightsEnabled,
              KeychainManager.hasAPIKey,
              replaceExisting || chapter.id != lastAnalyzedChapterIndex else { return }

        if !replaceExisting, annotationStore?.isChapterAnalyzed(chapter.id) == true {
            lastAnalyzedChapterIndex = chapter.id
            return
        }

        analysisDebounceTask?.cancel()
        analysisDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.startAnalysis(for: chapter, replaceExisting: replaceExisting)
        }
    }

    internal func startAnalysis(for chapter: Chapter, replaceExisting: Bool) {
        analysisTask?.cancel()
        isAnalyzingChapter = true

        let bookId = book.id.uuidString
        let bookTitle = book.title
        let density = AppSettings.shared.smartHighlightDensity
        let typeWeights = annotationStore?.smartHighlightTypeWeights

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let doc = await MainActor.run { self.originalDocument ?? self.document }
                let chapters = await MainActor.run { self.chapters }
                let chapterText = Self.extractChapterText(for: chapter, in: doc, chapters: chapters)

                guard !Task.isCancelled, !chapterText.isEmpty else {
                    await MainActor.run { self.isAnalyzingChapter = false }
                    return
                }

                let results = try await ClaudeAPIService.analyzeChapter(
                    text: chapterText,
                    bookTitle: bookTitle,
                    chapterTitle: chapter.title,
                    density: density,
                    typeWeights: typeWeights
                )

                guard !Task.isCancelled else { return }

                let smartHighlights = Self.buildSmartHighlights(
                    from: results, bookId: bookId, chapter: chapter,
                    doc: doc, chapters: chapters
                )

                await MainActor.run {
                    guard let store = self.annotationStore, !Task.isCancelled else { return }
                    if replaceExisting {
                        store.clearSmartHighlightsForChapter(chapter.id)
                    }
                    store.addSmartHighlights(smartHighlights)
                    self.lastAnalyzedChapterIndex = chapter.id
                    self.isAnalyzingChapter = false
                    if !smartHighlights.isEmpty {
                        NotificationCenter.default.post(name: .smartHighlightsReady, object: nil)
                    }
                }
            } catch {
                #if DEBUG
                print("[SmartHighlights] Analysis failed: \(error)")
                #endif
                await MainActor.run { self.isAnalyzingChapter = false }
            }
        }
    }

    internal func offerChapterReview(for chapter: Chapter) {
        guard smartHighlightsEnabled,
              KeychainManager.hasAPIKey,
              !reviewedChapters.contains(chapter.id),
              annotationStore?.chapterReview(forChapter: chapter.id) == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.triggerChapterReview()
        }
    }

    // MARK: - Static helpers (thread-safe)

    nonisolated static func extractChapterText(
        for chapter: Chapter, in doc: PDFDocument?, chapters: [Chapter]
    ) -> String {
        guard let doc else { return "" }
        let startPage = chapter.pageIndex
        let endPage: Int
        if let nextChapter = chapters.first(where: { $0.id > chapter.id }) {
            endPage = nextChapter.pageIndex
        } else {
            endPage = doc.pageCount
        }
        var texts: [String] = []
        for pageIndex in startPage..<endPage {
            guard let page = doc.page(at: pageIndex),
                  let text = page.string else { continue }
            texts.append(text)
        }
        return texts.joined(separator: "\n\n")
    }

    nonisolated static func buildSmartHighlights(
        from results: [SmartHighlightResult],
        bookId: String,
        chapter: Chapter,
        doc: PDFDocument?,
        chapters: [Chapter]
    ) -> [SmartHighlight] {
        results.map { result in
            SmartHighlight(
                bookId: bookId,
                chapterIndex: chapter.id,
                chapterTitle: chapter.title,
                chapterHash: chapter.contentHash,
                text: result.text,
                type: result.highlightType,
                rationale: result.rationale,
                page: findPageForSentenceStatic(result.text, in: chapter, doc: doc, chapters: chapters)
            )
        }
    }

    nonisolated static func findPageForSentenceStatic(
        _ sentence: String, in chapter: Chapter, doc: PDFDocument?, chapters: [Chapter]
    ) -> Int {
        guard let doc else { return chapter.pageIndex }
        let normalized = sentence.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        let startPage = chapter.pageIndex
        let endPage: Int
        if let nextChapter = chapters.first(where: { $0.id > chapter.id }) {
            endPage = nextChapter.pageIndex
        } else {
            endPage = doc.pageCount
        }
        for pageIndex in startPage..<endPage {
            guard let pageText = doc.page(at: pageIndex)?.string else { continue }
            let pageNormalized = pageText.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
            if pageNormalized.contains(normalized) {
                return pageIndex
            }
        }
        return chapter.pageIndex
    }
}
