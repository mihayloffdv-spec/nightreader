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
(All completed — see Completed section below)

## Completed
- Quick-annotate gestures — double-tap on selected text creates instant highlight. **Completed:** 2026-04-08.
- AI prompt tuning — save/dismiss ratio tracking per highlight type, auto-adjusts analysis prompt. **Completed:** 2026-04-08.
- Inline pencil marks — thin left-border lines on AI-highlighted paragraphs in Reader Mode. **Completed:** 2026-04-08.
- Argument map — AI analyzes chapter structure (thesis/evidence/conclusion), cached per chapter. **Completed:** 2026-04-08.
- Stable chapter identity — DJB2 hash of first 200 chars stored as chapterHash on Chapter, SmartHighlight. **Completed:** 2026-04-08.

## Future Ideas
- iPad rotation / split-screen support
- Horizontal page-turn mode
- PDF annotation sync with Reader Mode highlights
- Custom user-created themes
