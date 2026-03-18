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

## Future Ideas
- iPad rotation / split-screen support
- Horizontal page-turn mode
- PDF annotation sync with Reader Mode highlights
- Custom user-created themes
- Export highlights as Markdown with chapter headings
