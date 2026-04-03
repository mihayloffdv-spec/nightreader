# NightReader Theme System — Design Tokens

3 полных темы с разной эстетикой: шрифты, цвета, язык UI, характер.
Каждая тема — отдельная "личность" приложения, не просто перекраска.

Source: Google Stitch prototype (2026-04-03)
Screens: `/tmp/stitch-screens/` (local reference)

---

## Theme 1: Deep Forest ("Moss & Ember")

**Характер:** Природа, тёплый лес ночью, органические формы. Sanctuary.

### Цвета
| Token | Hex | Описание |
|-------|-----|----------|
| `background` | `#0B120B` | Глубокий тёмно-зелёный (мох) |
| `backgroundElevated` | `#141E14` | Карточки, поля ввода |
| `backgroundSheet` | `#111A11` | Bottom sheets |
| `textPrimary` | `#E8E0D4` | Основной текст (тёплый белый) |
| `textSecondary` | `#9A938A` | Метаданные, подписи |
| `accent` | `#CC704B` | Терракотовый (кнопки, акценты, highlights) |
| `accentMuted` | `#8B5A3A` | Приглушённый терракот (hover, pressed) |
| `surface` | `#4D5B4D` | Разделители, бордеры, subtle elements |
| `surfaceLight` | `#8B9D83` | Третичный (иконки, чипы) |
| `highlightBg` | `#CC704B` opacity 0.25 | Хайлайт на тексте |

### Шрифты
| Token | Шрифт | Использование |
|-------|-------|---------------|
| `headlineFont` | Plus Jakarta Sans Bold | Названия книг, заголовки экранов |
| `bodyFont` | Noto Serif Regular | Текст чтения |
| `bodyFontAlt` | Source Serif Regular | Альтернативный шрифт чтения (в настройках) |
| `labelFont` | Plus Jakarta Sans Medium | Кнопки, лейблы, навигация |
| `captionFont` | Plus Jakarta Sans Regular | Метаданные, подписи |

### Язык UI
| Элемент | Текст |
|---------|-------|
| Splash | "NightReader" |
| Library title | "Private Collection" |
| Reading view label | (нет, чистый текст) |
| Notebook title | "Notebook" |
| Notebook filters | All · Reactions · Actions |
| Chapter Review title | "Ready to reflect on Chapter N?" |
| Chapter Review CTA | "Save & Continue" |
| Post-Reading title | "The Hidden Life of Trees" (название книги) |
| Settings title | "Reading Interface" |
| Settings subtitle | "Fine-tune your nocturnal sanctuary for the perfect focus." |
| Settings sections | Typeface · Font Scale · Atmospheric Glow · Wind-down Mode |
| Tab bar | (no tabs, bottom navigation minimal) |

### Компоненты
| Компонент | Стиль |
|-----------|-------|
| Карточки хайлайтов | Тёмный фон `backgroundElevated`, левый бордер `accent`, скругление 12px |
| Кнопка primary | `accent` фон, тёмный текст, скругление 24px (pill) |
| Поля ввода | `backgroundElevated`, скругление 12px, placeholder `textSecondary` |
| Навигация | Минимальная нижняя полоса, иконки `surface`, активная `accent` |
| Хайлайт-точки (Notebook) | Круглые `accent` рядом с карточками |
| Цитаты | Курсив Noto Serif, `textSecondary`, кавычки-ёлочки |

---

## Theme 2: Classic Midnight ("Золотая классика")

**Характер:** Старая библиотека, церемония, золотые буквы на чёрном. The Scribe.

### Цвета
| Token | Hex | Описание |
|-------|-----|----------|
| `background` | `#121212` | Чистый чёрный |
| `backgroundElevated` | `#1E1E1E` | Карточки, поля |
| `backgroundSheet` | `#181818` | Bottom sheets |
| `textPrimary` | `#F0E6D2` | Тёплый кремовый |
| `textSecondary` | `#8A7E6C` | Метаданные |
| `accent` | `#FFBF00` | Золотой (яркий) |
| `accentMuted` | `#907335` | Тёмное золото |
| `surface` | `#2A2520` | Разделители |
| `surfaceLight` | `#00DCFF` | Третичный (редко, для контраста) |
| `highlightBg` | `#FFBF00` opacity 0.2 | Хайлайт на тексте |

### Шрифты
| Token | Шрифт | Использование |
|-------|-------|---------------|
| `headlineFont` | Noto Serif Bold | Названия книг, заголовки — серифный, классический |
| `bodyFont` | Literata Regular | Текст чтения |
| `bodyFontAlt` | Noto Serif Regular | Альтернативный |
| `labelFont` | Inter Medium | Кнопки, лейблы, навигация |
| `captionFont` | Inter Regular | Метаданные |

### Язык UI
| Элемент | Текст |
|---------|-------|
| App name | "The Scribe" / "NightReader" |
| Library title | "The Midnight Library" |
| Library subtitle | "Between life and death there is a library..." |
| Notebook title | "NightReader" (в хедере) |
| Chapter Review title | "What was the one idea that stayed with you?" |
| Chapter Review CTA | "Record Thought" |
| Post-Reading title | "The Final Entry" |
| Post-Reading subtitle | "REFLECTION" |
| Post-Reading CTA | "Seal Entry" |
| Post-Reading skip | "Skip Ceremony" |
| Settings sections | Typography · Background · Wind-down Mode |
| Tab bar | Library · Notebook · Settings |

### Компоненты
| Компонент | Стиль |
|-----------|-------|
| Карточки хайлайтов | Тёмный фон, золотая левая граница, цитаты в кавычках |
| Кнопка primary | `accent` фон (#FFBF00), чёрный текст, скругление 8px (строже) |
| Post-Reading карточки | Белые/светлые карточки на тёмном фоне, скругление 16px |
| Навигация | Tab bar внизу: Library · Notebook · Settings (золотой active) |
| Цитаты | Курсив, золотой цвет, крупнее обычного текста |
| Progress | "42%" жёлтым на обложке книги |

---

## Theme 3: Minimalist Slate ("The Scribe / Архивариус")

**Характер:** Минимализм, negative space, тихий архив. Evening Reflection.

### Цвета
| Token | Hex | Описание |
|-------|-----|----------|
| `background` | `#1A1C1E` | Тёмный сланец (теплее чёрного) |
| `backgroundElevated` | `#242628` | Карточки |
| `backgroundSheet` | `#1F2123` | Bottom sheets |
| `textPrimary` | `#E8E4DC` | Светлый кремовый |
| `textSecondary` | `#7A756E` | Метаданные |
| `accent` | `#D4AF37` | Мягкое золото (теплее, менее яркое чем Classic) |
| `accentMuted` | `#877645` | Бронзовый |
| `surface` | `#2E3034` | Разделители |
| `surfaceLight` | `#97B0FF` | Третичный (мягкий голубой, редко) |
| `highlightBg` | `#D4AF37` opacity 0.2 | Хайлайт на тексте |

### Шрифты
| Token | Шрифт | Использование |
|-------|-------|---------------|
| `headlineFont` | Manrope Bold | Геометрический sans-serif, современный |
| `bodyFont` | Charter Regular | Текст чтения (разборчивый, humanist serif) |
| `bodyFontAlt` | Spectral / EB Garamond | Альтернативные шрифты чтения |
| `labelFont` | Manrope Medium | Кнопки, лейблы |
| `captionFont` | Manrope Regular | Метаданные |

### Язык UI
| Элемент | Текст |
|---------|-------|
| App name | "The Scribe" |
| Library title | "Your Library" |
| Library subtitle | (текущая книга крупно, "Currently Reading") |
| Library section | "Recent Additions" |
| Notebook title | "NightReader" |
| Chapter Review question | "How did the concept of **negative space** shift your perception?" |
| Chapter Review CTA | "Continue Reflection" |
| Post-Reading title | "Evening Reflection" |
| Post-Reading subtitle | "READING RITUAL · 12:42 AM" |
| Post-Reading CTA | "Complete Ritual" |
| Post-Reading note | "Your observations will be stored in the Archives." |
| Settings title | "Reading Preferences" |
| Settings sections | Typeface · Size · Warmth · Wind-down Mode |
| Tab bar | Library · Journal · Search · Archives |

### Компоненты
| Компонент | Стиль |
|-----------|-------|
| Карточки хайлайтов | Минимальные, много negative space, золотой маркер |
| Кнопка primary | `accent` фон, тёмный текст, pill shape с бордером |
| Поля ввода | Огромные, с иконкой карандаша, placeholder курсивом |
| Навигация | Tab bar: Library · Journal · Search · Archives |
| AI feedback | Маленький золотой маркер ✦, компактный текст |
| Progress | Линейный прогресс-бар, мягкий |

---

## Общие дизайн-токены (все темы)

### Spacing
| Token | Значение |
|-------|----------|
| `spacingXS` | 4pt |
| `spacingSM` | 8pt |
| `spacingMD` | 16pt |
| `spacingLG` | 24pt |
| `spacingXL` | 32pt |
| `spacingXXL` | 48pt |

### Corner Radius
| Token | Значение |
|-------|----------|
| `radiusSM` | 8pt |
| `radiusMD` | 12pt |
| `radiusLG` | 16pt |
| `radiusPill` | 24pt |

### Touch Targets
- Minimum: 44pt (Apple HIG)
- Buttons: 48pt height
- Tab bar icons: 44pt tap area

### Typography Scale
| Token | Size | Line Height |
|-------|------|-------------|
| `largeTitle` | 34pt | 41pt |
| `title1` | 28pt | 34pt |
| `title2` | 22pt | 28pt |
| `title3` | 20pt | 25pt |
| `headline` | 17pt | 22pt (semibold) |
| `body` | 17pt | 22pt |
| `callout` | 16pt | 21pt |
| `subheadline` | 15pt | 20pt |
| `footnote` | 13pt | 18pt |
| `caption` | 12pt | 16pt |

### Animations
| Transition | Duration | Curve |
|------------|----------|-------|
| Sheet appear | 0.3s | spring(response: 0.35) |
| Highlight fade-in | 0.3s | easeInOut |
| Page transition | 0.25s | easeInOut |
| Tab switch | 0.2s | easeInOut |
| Button press | 0.15s | easeOut |

---

## Архитектурные изменения для Theme System

### Текущая модель Theme (3 цвета):
```swift
struct Theme {
    let bgColorHex: String      // background
    let textColorHex: String    // textPrimary
    let tintColorHex: String    // accent
}
```

### Новая модель Theme (полная):
```swift
struct Theme {
    // Identity
    let id: String
    let name: String
    let displayName: String          // "The Scribe", "Private Collection"
    
    // Colors (10 tokens)
    let backgroundHex: String
    let backgroundElevatedHex: String
    let backgroundSheetHex: String
    let textPrimaryHex: String
    let textSecondaryHex: String
    let accentHex: String
    let accentMutedHex: String
    let surfaceHex: String
    let surfaceLightHex: String
    let highlightOpacity: Double
    
    // Typography (5 tokens)
    let headlineFont: String         // "PlusJakartaSans-Bold"
    let bodyFont: String             // "NotoSerif-Regular"
    let bodyFontAlt: String          // "SourceSerif4-Regular"
    let labelFont: String            // "PlusJakartaSans-Medium"
    let captionFont: String          // "PlusJakartaSans-Regular"
    
    // UI Language
    let libraryTitle: String         // "Private Collection"
    let notebookTitle: String        // "Notebook"
    let chapterReviewCTA: String     // "Save & Continue"
    let postReadingTitle: String     // "Ready to reflect?"
    let postReadingCTA: String       // "Complete"
    let postReadingSkip: String      // "Skip"
    let settingsTitle: String        // "Reading Interface"
    let tabLabels: [String]          // ["Library", "Notebook", "Settings"]
    
    // Style
    let buttonRadius: Double         // 24 (pill) vs 8 (square)
    let cardBorderAccent: Bool       // left border on highlight cards
}
```

### Миграция
- Существующие 6 тем (midnight, sepia, forest, ocean, sunset, paper) → заменяются на 3 новых
- Поля `bgColorHex`, `textColorHex`, `tintColorHex` → маппятся на `backgroundHex`, `textPrimaryHex`, `accentHex`
- Новые поля получают дефолтные значения при миграции
- `UserDefaults` ключ `defaultThemeId` остаётся, значения меняются

### Шрифты — Бандл
Все кастомные шрифты нужно добавить в Xcode bundle:
- **Plus Jakarta Sans** (Bold, Medium, Regular)
- **Noto Serif** (Bold, Regular, Italic)
- **Source Serif 4** (Regular, Italic)
- **Literata** (Regular, Italic)
- **Manrope** (Bold, Medium, Regular)
- **Charter** (Regular, Italic)
- **Spectral** (Regular, Italic)
- **EB Garamond** (Regular, Italic)
- **Inter** (Medium, Regular)

Итого: 9 семейств, ~20 файлов .ttf/.otf

Info.plist → `UIAppFonts` массив с именами файлов.
