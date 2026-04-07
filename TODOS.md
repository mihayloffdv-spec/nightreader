# NightReader — TODOS

All phases from the Reader Mode Evolution plan have been implemented.

## Completed
- Phase 1-4: Core Reader Mode features (refactor, themes, cross-page join, reading time, font controls)
- Phase 5: Text Selection & Copy in Reader Mode (UILabel → UITextView with selection support)
- Phase 6: Chapter Detection & Per-Chapter Progress (PDF outline + auto-detected headings, chapter name in toolbar)

## AI Features Plan (from CEO Review 2026-03-18)

### Phase 7A: AI Text Actions — NEXT
- AI Explain ("Объясни проще") — select text → Claude explains in simple terms
- AI Translate — select text → Claude translates to target language
- Foundation: ClaudeAPIService, KeychainManager, AIActionSheet (bottom sheet)
- API key stored in Keychain, Haiku for Explain/Translate, Sonnet for complex tasks

### Phase 7B: AI Q&A Chat
- Chat interface in toolbar, book context sent to Claude
- Depends on: Phase 7A (ClaudeAPIService)

### Phase 7C: TTS — Read Aloud
- AVSpeechSynthesizer with play/pause/stop controls
- Independent of other AI phases

### Phase 7D: Semantic Search
- Natural language search ("Где автор говорит о...")
- Requires text embeddings + local index
- Depends on: Phase 7A

### Phase 7E: AI Learning
- Chapter Quiz (3-5 questions after each chapter)
- Reading Insights (personal digest after finishing book)
- Depends on: Phase 7A + 7B

### Deferred AI Features
- AI Summary per chapter — "Перескажи главу" button, sends chapter text to Claude. Partially covered by Q&A. Depends on Phase 7A. Effort: S (CC: ~15 min). Priority: P3.
- Smart Vocabulary / Glossary — AI analyzes chapter, extracts key terms with definitions. Extension of Q&A. Depends on Phase 7A + 7B. Effort: M (CC: ~1 hour). Priority: P3.

## Annotation System (from CEO Review 2026-04-03)

### MVP (v1): Highlights + Notebook + Export
- Highlight text via custom context menu item
- Bottom sheet annotation (reaction 🎭 / action ⚡)
- Notebook view (all highlights, filters, edit/delete)
- Export to Obsidian-compatible .md via Share Sheet
- Storage: JSON files in Application Support (annotations/{bookId}.json)
- **Expansion**: Continue from last thought (show last highlight on book open)
- **Expansion**: Highlight heatmap (dots in page slider)
- **Expansion**: Reading session recap (card on session close)
- **Expansion**: Action reminders in library (badges on book cards)

### v2: AI-Powered Deep Reading
- Chapter Review: AI generates 3-5 questions after each chapter (Claude Haiku)
- AI feedback on user answers + chapter summary
- Smart Highlights: AI-подсветка ключевых предложений (thesis / definition / contrarian)
- Author formatting detection (reduce AI highlight density)
- Post-Reading Review: guided flow (core idea / why read / main shift)
- Action review: committed vs ideas filter
- **Expansion**: AI "Best of" curation (top-5 starred highlights in export)
- Updated .md export with all new sections

### v3: Obsidian Integration + Intelligence
- Direct write to Obsidian vault folder (folder picker + iCloud)
- Cross-book connections (similar highlights)
- AI summarization of all book annotations
- Spaced repetition: periodic push reminders with questions
- Obsidian URI scheme integration

### Deferred Expansions
- Quick-annotate gestures — double-tap highlight for fast annotation without bottom sheet. Needs PDFKit gesture conflict research. Effort: M (CC: ~30 min). Priority: P2. Depends on: MVP annotations.
- Argument map — AI builds chapter argument structure (thesis → evidence → conclusion). Complex UI + AI experiment. Effort: L (CC: ~2-3 hours). Priority: P3. Depends on: v2 (chapter review, smart highlights).
- AI prompt tuning based on save/dismiss ratios — track which highlight types users Save vs Dismiss, adjust prompt density/type weighting over time. Like a recommendation engine learning from ratings. Effort: M (CC: ~1 hour). Priority: P3. Depends on: v2 Smart Highlights with enough usage data. From eng review 2026-04-06.
- Inline pencil marks (Phase 2) — render AI highlights as thin left-border lines directly on text in Reader Mode. Requires fuzzy text-to-position matching in ReaderTextView, custom NSLayoutManager drawing, PDF mode rendering. Effort: L (CC: ~2-3 hours). Priority: P2. Depends on: v2 Smart Highlights (Phase 1 list-based). From eng review 2026-04-06 (Codex outside voice recommended phasing).

## Architecture Debt (from eng review 2026-04-07)
- Stable chapter identity — SmartHighlight uses chapterIndex (sequential int) + chapterTitle (string), but chapter detection can reindex if PDF outline or auto-detection heuristics change. Before v3 cross-book connections, stabilize chapter identity (e.g., hash of first N chars of chapter text as stable ID). Effort: S (CC: ~15 min). Priority: P2. Depends on: v3 planning. From Codex outside voice.

## Future Ideas
- iPad rotation / split-screen support
- Horizontal page-turn mode
- PDF annotation sync with Reader Mode highlights
- Custom user-created themes
