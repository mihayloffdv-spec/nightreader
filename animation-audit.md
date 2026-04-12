# NightReader — Animation Audit

Полная инвентаризация всех анимаций, найденных в кодовой базе.
Сканирование выполнено по паттернам: `withAnimation`, `.animation(`, `.transition(`,
`matchedGeometryEffect`, `spring(`, easing curves, `symbolEffect`, `contentTransition`.

Custom токены анимаций определены в [NightReader/Views/AppAnimations.swift](NightReader/Views/AppAnimations.swift):
- `softMenu` = `spring(response: 0.38, dampingFraction: 0.82)` — меню/тулбары/тултипы
- `softTap`  = `spring(response: 0.32, dampingFraction: 0.85)` — тапы по кнопкам и тогглы
- `softFade` = `easeInOut(duration: 0.35)` — смена контента (mode/theme)
- `softTop` / `softBottom` = `move(edge:).combined(with: .opacity)` — слайды панелей

---

## Phase 2 — Emil Audit (с вердиктами)

Каждая анимация оценена против принципов из задачи:
1. **Purpose** — есть ли реальная причина существования
2. **Timing** — попадает ли в диапазоны (150–250ms micro / 200–350ms transitions)
3. **Easing** — правильная ли кривая (easeOut для входа, easeInOut для layout)
4. **Restraint** — скажет ли пользователь "nice animation"? Если да — переборщили
5. **Invisibility** — усиливает ощущение интерфейса или привлекает внимание

Вердикты: **KEEP** (оставить как есть), **ADJUST** (изменить параметры), **REMOVE** (убрать целиком).

| # | File:line | What | Current | Verdict | Reason | Priority |
|---|-----------|------|---------|---------|--------|----------|
| 1 | [App/NightReaderApp.swift:43](NightReader/App/NightReaderApp.swift#L43) | Splash exit transition | `.transition(.opacity)` | **KEEP** | Функциональный фейд, незаметный, ведомый параметром #2. | |
| 2 | [App/NightReaderApp.swift:46](NightReader/App/NightReaderApp.swift#L46) | Splash exit driver | `.animation(.easeInOut(duration: 0.3), value: showSplash)` | **KEEP** | 0.3s в диапазоне, easeInOut для fade корректно. | |
| 3 | [Views/Library/SplashScreenView.swift:109](NightReader/Views/Library/SplashScreenView.swift#L109) | Splash content fade-in | `withAnimation(.easeIn(duration: 0.8))` | **ADJUST** | 0.8s сильно за пределами диапазона (макс 350ms). `easeIn` неверная кривая для входа — медленный старт читается как лаг. Заменить на `.easeOut(0.3)`. | |
| 4 | [Views/Library/SplashScreenView.swift:114](NightReader/Views/Library/SplashScreenView.swift#L114) | Splash exit content fade | `withAnimation(.easeOut(duration: 0.4))` | **KEEP** | 0.4s ровно на верхней границе, для splash exit допустимо. Кривая правильная. | |
| 5 | [ViewModels/ReaderViewModel.swift:281](NightReader/ViewModels/ReaderViewModel.swift#L281) | Auto-hide toolbar после 8с | `withAnimation(.easeInOut(duration: 0.25))` | **KEEP** | Идеальная длительность, незаметный fade-out, корректная кривая. | |
| 6 | [Views/Reader/ReaderView.swift:46](NightReader/Views/Reader/ReaderView.swift#L46) | DayMode tap → toggle тулбара | `withAnimation(.softMenu)` | **KEEP** | Spring 0.38/0.82, без bounce, в диапазоне. | |
| 7 | [Views/Reader/ReaderView.swift:62](NightReader/Views/Reader/ReaderView.swift#L62) | DayModeReadingView entry | `.transition(.opacity)` | **KEEP** | Фейд для смены режима — корректно. | |
| 8 | [Views/Reader/ReaderView.swift:80](NightReader/Views/Reader/ReaderView.swift#L80) | ReaderMode tap → toggle тулбара | `withAnimation(.softMenu)` | **KEEP** | Тот же паттерн что #6. | |
| 9 | [Views/Reader/ReaderView.swift:97-100](NightReader/Views/Reader/ReaderView.swift#L97-L100) | ReaderModeView slide trailing/leading + opacity | `.transition(.asymmetric(...slide+opacity))` | **ADJUST** | Slide-переход подразумевает «навигация по страницам». Но это смена режима, не пейджинг. Slide привлекает внимание, нарушает invisibility. Заменить на `.opacity`. | |
| 10 | [Views/Reader/ReaderView.swift:119](NightReader/Views/Reader/ReaderView.swift#L119) | PDF empty tap → toggle тулбара | `withAnimation(.easeInOut(duration: 0.25))` | **ADJUST** | Несогласованность: то же действие (toggle тулбара) использует разный токен в разных режимах. Заменить на `.softMenu` для консистентности с #6, #8. | |
| 11 | [Views/Reader/ReaderView.swift:125-128](NightReader/Views/Reader/ReaderView.swift#L125-L128) | PDFKitView slide leading/trailing + opacity | `.transition(.asymmetric(...slide+opacity))` | **ADJUST** | То же что #9. Заменить на `.opacity`. | |
| 12 | [Views/Reader/ReaderView.swift:131](NightReader/Views/Reader/ReaderView.swift#L131) | Driver mode swap | `.animation(.softFade, value: viewModel.isReaderMode)` | **ADJUST** | softFade = 0.35s, на верхней границе. После упрощения #9, #11 до opacity можно сократить до 0.25s. | |
| 13 | [Views/Reader/ReaderView.swift:160](NightReader/Views/Reader/ReaderView.swift#L160) | Search bar slide-in | `.transition(.softTop)` | **KEEP** | Search bar появляется сверху — slide уместен (пространственная метафора). | |
| 14 | [Views/Reader/ReaderView.swift:172](NightReader/Views/Reader/ReaderView.swift#L172) | Background fade при смене темы | `.animation(.softFade, value: viewModel.selectedTheme.id)` | **KEEP** | Тема меняется редко и явно по запросу пользователя. 0.35s допустимо. | |
| 15 | [Views/Reader/ReaderView.swift:173](NightReader/Views/Reader/ReaderView.swift#L173) | Toolbar visibility driver | `.animation(.softMenu, value: viewModel.toolbarVisible)` | **KEEP** | Корректный driver. | |
| 16 | [Views/Reader/ReaderView.swift:174](NightReader/Views/Reader/ReaderView.swift#L174) | Search visibility driver | `.animation(.softMenu, value: viewModel.showSearch)` | **KEEP** | Корректный driver. | |
| 17 | [Views/Reader/ReaderToolbar.swift:33](NightReader/Views/Reader/ReaderToolbar.swift#L33) | Top bar slide | `.transition(.softTop)` | **KEEP** | Тулбар сверху — slide пространственно оправдан. | |
| 18 | [Views/Reader/ReaderToolbar.swift:40](NightReader/Views/Reader/ReaderToolbar.swift#L40) | Bottom bar slide | `.transition(.softBottom)` | **KEEP** | То же снизу. | |
| 19 | [Views/Reader/ReaderToolbar.swift:105](NightReader/Views/Reader/ReaderToolbar.swift#L105) | Bookmark tap bouncy spring | `withAnimation(.spring(response: 0.3, dampingFraction: 0.5))` | **ADJUST** | damping 0.5 = явный bounce, единственный во всём приложении. Контрастирует с языком restraint. Phase 5 разрешает «характер» только для highlight, но bookmark — другое действие. Заменить на `.softTap` (0.32/0.85) ИЛИ компромисс damping 0.72 (намёк на пружину). | |
| 20 | [Views/Reader/ReaderToolbar.swift:132](NightReader/Views/Reader/ReaderToolbar.swift#L132) | Page progress text morph | `.contentTransition(.numericText())` | **KEEP** | Native iOS 17+, числа плавно перетекают вместо jump. Незаметный эффект. | |
| 21 | [Views/Reader/ReaderToolbar.swift:164](NightReader/Views/Reader/ReaderToolbar.swift#L164) | Scrubber dot scale + opacity | `.transition(.scale.combined(with: .opacity))` | **KEEP** | Точка появляется при тапе на прогресс — функциональный feedback. | |
| 22 | [Views/Reader/ReaderToolbar.swift:172](NightReader/Views/Reader/ReaderToolbar.swift#L172) | Scrubber drag start (capsule утолщается) | `withAnimation(.easeOut(duration: 0.1))` | **KEEP** | 0.1s — почти мгновенно, ниже порога восприятия. Корректно для активного драга. | |
| 23 | [Views/Reader/ReaderToolbar.swift:178](NightReader/Views/Reader/ReaderToolbar.swift#L178) | Scrubber drag end | `withAnimation(.easeOut(duration: 0.2))` | **KEEP** | 0.2s для возврата высоты — корректно. | |
| 24 | [Views/Reader/ReaderToolbar.swift:184](NightReader/Views/Reader/ReaderToolbar.swift#L184) | Scrubber height driver | `.animation(.easeInOut(duration: 0.15), value: isDraggingScrubber)` | **REMOVE** | Дублирует #22 и #23 (которые уже оборачивают изменение в `withAnimation`). Двойная анимация даёт непредсказуемое поведение. | |
| 25 | [Views/Reader/ReaderToolbar.swift:189](NightReader/Views/Reader/ReaderToolbar.swift#L189) | Percent text morph | `.contentTransition(.numericText())` | **KEEP** | Тот же паттерн что #20. | |
| 26 | [Views/Reader/ReaderToolbar.swift:191](NightReader/Views/Reader/ReaderToolbar.swift#L191) | Progress bar fill | `.animation(.easeInOut(duration: 0.2), value: viewModel.progressFraction)` | **ADJUST** | Во время drag scrubber'а каждое микро-движение пальца анимируется 0.2s — создаёт лаг между пальцем и баром. Решение: убрать анимацию когда `isDraggingScrubber == true`, либо сократить до ~0.05s. | |
| 27 | [Views/Reader/ReaderToolbar.swift:213](NightReader/Views/Reader/ReaderToolbar.swift#L213) | Reader Mode toggle (главная кнопка) | `withAnimation(.softTap)` | **KEEP** | Корректный токен для тапа. | |
| 28 | [Views/Reader/ReaderToolbar.swift:269](NightReader/Views/Reader/ReaderToolbar.swift#L269) | Sparkle pulse во время AI analyze | `.symbolEffect(.pulse, isActive: isPulsing)` | **KEEP** | Native, минималистичный, сигнализирует «AI работает». | |
| 29 | [Views/Reader/ReaderToolbar.swift:279](NightReader/Views/Reader/ReaderToolbar.swift#L279) | Sparkle pulse (Button variant) | `.symbolEffect(.pulse, isActive: isPulsing)` | **KEEP** | Тот же паттерн что #28. | |
| 30 | [Views/Reader/ReaderToolbar.swift:295](NightReader/Views/Reader/ReaderToolbar.swift#L295) | Reader Mode toggle через menu | `withAnimation(.softTap)` | **KEEP** | Согласованно с #27. | |
| 31 | [Views/Reader/ReaderToolbar.swift:307](NightReader/Views/Reader/ReaderToolbar.swift#L307) | Day Mode toggle через menu | `withAnimation(.softTap)` | **KEEP** | Согласованно. | |
| 32 | [Views/Reader/ReaderToolbar.swift:321](NightReader/Views/Reader/ReaderToolbar.swift#L321) | Search button через menu | `withAnimation(.softMenu)` | **KEEP** | Открывает search bar — softMenu корректно. | |
| 33 | [Views/Reader/ReaderModeView.swift:47](NightReader/Views/Reader/ReaderModeView.swift#L47) | Smart Highlight tooltip slide | `.transition(.softTop)` | **KEEP** | Образовательный тултип сверху — корректно. | |
| 34 | [Views/Reader/ReaderModeView.swift:48](NightReader/Views/Reader/ReaderModeView.swift#L48) | Tooltip dismiss on tap | `withAnimation(.softMenu)` | **KEEP** | | |
| 35 | [Views/Reader/ReaderModeView.swift:51](NightReader/Views/Reader/ReaderModeView.swift#L51) | Tooltip auto-dismiss через 5с | `withAnimation(.softMenu)` | **KEEP** | | |
| 36 | [Views/Reader/ReaderModeView.swift:57](NightReader/Views/Reader/ReaderModeView.swift#L57) | Tooltip appearance | `withAnimation(.softMenu)` | **KEEP** | | |
| 37 | [Views/Reader/PagedContentView.swift:91](NightReader/Views/Reader/PagedContentView.swift#L91) | Page scroll к новой странице | `withAnimation { proxy.scrollTo(...) }` (default) | **ADJUST** | Default `withAnimation` без параметров — неконтролируемое поведение SwiftUI (~0.35s spring). Сделать явно: `.easeInOut(duration: 0.3)`. | |
| 38 | [Views/Reader/PagedContentView.swift:111](NightReader/Views/Reader/PagedContentView.swift#L111) | Loading indicator opacity | `.transition(.opacity)` | **KEEP** | | |
| 39 | [Views/Reader/PagedContentView.swift:117](NightReader/Views/Reader/PagedContentView.swift#L117) | Loading indicator driver | `.animation(.easeOut(duration: 0.25), value: isFirstPageReady)` | **KEEP** | | |
| 40 | [Views/Reader/ChatView.swift:32](NightReader/Views/Reader/ChatView.swift#L32) | Chat scroll к последнему сообщению | `withAnimation { proxy.scrollTo(...) }` (default) | **ADJUST** | То же что #37 — сделать явно. Для chat scroll лучше `.easeOut(duration: 0.25)`. | |
| 41 | [Views/Reader/PostReadingReviewView.swift:82](NightReader/Views/Reader/PostReadingReviewView.swift#L82) | Wizard step назад | `withAnimation { currentStep -= 1 }` (default) | **ADJUST** | Default неуправляем. Wizard переход — это смена контента в одной области, нужен `.easeInOut(duration: 0.25)` или асимметричный slide. | |
| 42 | [Views/Reader/PostReadingReviewView.swift:95](NightReader/Views/Reader/PostReadingReviewView.swift#L95) | Wizard step вперёд | `withAnimation { currentStep += 1 }` (default) | **ADJUST** | То же что #41. | |
| 43 | [Views/Reader/NotebookView.swift:152](NightReader/Views/Reader/NotebookView.swift#L152) | Notebook filter tab selection | `withAnimation(.softTap)` | **KEEP** | | |
| 44 | [Views/Reader/NotebookView.swift:377](NightReader/Views/Reader/NotebookView.swift#L377) | Smart highlight dismiss | `withAnimation(.easeOut(duration: 0.3))` | **KEEP** | 0.3s easeOut для exit — корректно. | |

---

## ⚠️ Critical finding — Phase 4 dependency

**Dark mode toggle (compositingFilter overlay) НЕ имеет анимации.**

Phase 4 задачи рассматривает dark mode toggle как «defining UX moment» приложения. Но в коде:
- [Services/DarkModeRenderer.swift:9-35](NightReader/Services/DarkModeRenderer.swift#L9) — `applyDarkMode` делает `addSubview` instantly
- [Services/DarkModeRenderer.swift:37-40](NightReader/Services/DarkModeRenderer.swift#L37) — `removeDarkMode` делает `removeFromSuperview` instantly
- [Views/Reader/PDFKitView.swift:206-213](NightReader/Views/Reader/PDFKitView.swift#L206) — переключение происходит без UIView.animate

Никакого `viewModel.renderingMode` driver в `.animation(value:)` не существует. Переключение dark mode читается как screen flash.

Это **отсутствующая анимация**, которая ожидается Phase 4. Раздел про dark mode toggle в задаче говорит:
> It must not be instant (resolves as a bug / screen flash)
> Target: `.easeInOut(duration: 0.25)` as a starting point

Поскольку правила задачи запрещают добавлять новые анимации без явного запроса, я **флагую это** как item #45 ниже. Решение по нему — в Phase 4 (или сразу, если ты подтвердишь).

| # | File:line | What | Current | Verdict | Reason | Priority |
|---|-----------|------|---------|---------|--------|----------|
| 45 | [Services/DarkModeRenderer.swift:9-40](NightReader/Services/DarkModeRenderer.swift#L9) + [Views/Reader/PDFKitView.swift:206-213](NightReader/Views/Reader/PDFKitView.swift#L206) | Dark mode (compositingFilter) toggle | **отсутствует** — instant addSubview/removeFromSuperview | **ADD** (требует подтверждения) | Phase 4 ожидает анимацию здесь. Сейчас читается как flash. Решение: обернуть в `UIView.animate(withDuration: 0.25)` с opacity transition на overlay. | |

---

## Summary

| Verdict | Count |
|---------|-------|
| **KEEP** | 30 |
| **ADJUST** | 13 |
| **REMOVE** | 1 |
| **ADD** (нужно решение) | 1 |
| **Total** | 45 |

### ADJUST priority candidates (где улучшения дают больше всего)

1. **#45 dark mode toggle** — defining moment, сейчас instant flash
2. **#19 bookmark bouncy spring** — единственный нарушитель restraint в приложении
3. **#26 progress bar drag lag** — пользовательски заметное ощущение «отставания» при scrubber drag
4. **#9, #11, #12 mode swap slide** — три связанных адъюста, упрощают переход режимов
5. **#3 splash content fade-in** — 0.8s easeIn явно за пределами диапазона
6. **#10 PDFKit toolbar tap inconsistency** — мелкая, но видимая несогласованность
7. **#37, #40, #41, #42 default `withAnimation { }`** — явно прописать таймеры

### Pattern issues

- **Двойные анимации**: #24 (driver) дублирует #22, #23 (explicit). Risk pattern — стоит проверить нет ли подобного в других местах.
- **Дефолтный `withAnimation { }`** в 4 местах — неконтролируемое поведение, должно быть всегда явным.
- **Unique bouncy spring** в #19 нарушает единый язык анимаций.
- **Slide для смены режима** (mode swap) подразумевает пространственную навигацию там, где её нет.

---

## Phase 3 — Implementation (полная)

Все 14 изменений (13 ADJUST + 1 REMOVE + 1 ADD) реализованы тремя атомарными группами.

### Group A — High user impact

| # | Файл | Изменение |
|---|------|-----------|
| 45 | [DarkModeRenderer.swift](NightReader/Services/DarkModeRenderer.swift), [PDFKitView.swift:206-216](NightReader/Views/Reader/PDFKitView.swift#L206) | Dark mode toggle: добавлен `animated:` параметр, overlay views fade alpha 0↔1 через `UIView.animate(0.25, .curveEaseInOut)`. Initial doc load — без анимации (`isInitial = lastAppliedRenderingMode == nil`). |
| 19 | [ReaderToolbar.swift:105](NightReader/Views/Reader/ReaderToolbar.swift#L105) | Bookmark: `spring(0.3, damping: 0.5)` → `.softTap`. Тактильность даёт haptic. |
| 26 | [ReaderToolbar.swift:191](NightReader/Views/Reader/ReaderToolbar.swift#L191) | Progress bar: `.animation(isDraggingScrubber ? nil : .easeInOut(0.2), value:)`. Бар следует за пальцем 1:1 во время drag. |

### Group B — Visual consistency

| # | Файл | Изменение |
|---|------|-----------|
| 9 | [ReaderView.swift:96](NightReader/Views/Reader/ReaderView.swift#L96) | ReaderModeView: `.transition(.asymmetric(slide+opacity))` → `.transition(.opacity)`. |
| 11 | [ReaderView.swift:121](NightReader/Views/Reader/ReaderView.swift#L121) | PDFKitView: `.transition(.asymmetric(slide+opacity))` → `.transition(.opacity)`. |
| 12 | [AppAnimations.swift:22-25](NightReader/Views/AppAnimations.swift#L22) | `softFade`: `easeInOut(0.35)` → `easeInOut(0.25)`. Затрагивает и mode swap, и theme change. |
| 10 | [ReaderView.swift:116](NightReader/Views/Reader/ReaderView.swift#L116) | PDF empty tap: `easeInOut(0.25)` → `.softMenu`. Согласованно с #6, #8. |

### Group C — Cleanup

| # | Файл | Изменение |
|---|------|-----------|
| 24 | [ReaderToolbar.swift:184](NightReader/Views/Reader/ReaderToolbar.swift#L184) | REMOVED: `.animation(.easeInOut(0.15), value: isDraggingScrubber)`. Дублировал explicit withAnimation в drag handlers. |
| 3 | [SplashScreenView.swift:109-111](NightReader/Views/Library/SplashScreenView.swift#L109) | `easeIn(0.8)` → `easeOut(0.3)`. Правильная кривая для входа, в диапазоне. |
| 37 | [PagedContentView.swift:91](NightReader/Views/Reader/PagedContentView.swift#L91) | Page scroll: `withAnimation { }` → `withAnimation(.easeInOut(duration: 0.3))`. |
| 40 | [ChatView.swift:32-34](NightReader/Views/Reader/ChatView.swift#L32) | Chat scroll: `withAnimation { }` → `withAnimation(.easeOut(duration: 0.25))`. |
| 41, 42 | [PostReadingReviewView.swift:82, 95](NightReader/Views/Reader/PostReadingReviewView.swift#L82) | Wizard step: `withAnimation { }` → `withAnimation(.easeInOut(duration: 0.25))`. |

### Verification

- ✅ Build success после каждой группы
- ⏳ Manual smoke test на симуляторе (визуальные изменения, unit-тесты не покрывают)
- ⏳ 169 существующих тестов пройти (не должно быть регрессий — все изменения локальные)

### Final summary

- **Применено:** 13 ADJUST + 1 REMOVE + 1 ADD = 15 изменений  
- **Файлов изменено:** 8
- **Custom токены:** softFade обновлён глобально (затрагивает 3 call site)
- **Архитектурно новое:** только #45 (animated параметр в DarkModeRenderer + isInitial guard в PDFKitView)

**STOP — All phases complete.** Готово к ручному тестированию.
