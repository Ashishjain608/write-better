# WriteBetter — Design Brief v1.0

**Author:** Agent R1 · **Status:** authoritative for Agents U (UI) and D (packaging/assets).
**Rule:** where this file and an agent's judgement disagree, this file wins. Where this file and
`CONTRACT.md` disagree, `CONTRACT.md` wins (deployment target macOS 14, zero dependencies).

Everything below is a decision, not a suggestion. Hex codes, point values and millisecond
durations are literal. If something you need is not specified here, it is a bug — pick the
nearest specified value rather than inventing a new one.

---

## 1. Research digest

### 1.1 macOS 26 "Liquid Glass" / Tahoe — what it actually specifies

- Apple describes Liquid Glass as "a new digital meta-material that dynamically bends and shapes light." The distinguishing property is **lensing** (bending/concentrating light) rather than the scattering blur of pre-26 materials. — https://ubos.tech/news/macos-tahoe-liquid-glass-ui-review-a-critical-look/
- Tahoe raised window corner radii from the ~4pt curve of Sequoia to roughly **12pt arcs** on windows, dialogs and panels; Apple's WWDC explanation is that the radius wraps **concentrically** around the glass toolbar elements, so a window's radius changes when you add a toolbar or sidebar. — https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/ and https://cloudship.co.uk/blog/macos-tahoe-liquid-glass/
- The full API surface, availability and rules: `.glassEffect()`, `.glassEffect(_ glass:in:isEnabled:)`, `.glassEffectID(_:in:)`, `.glassEffectUnion(id:namespace:)`, `.glassEffectTransition(_:)`, `GlassEffectContainer(spacing:)`, `.buttonStyle(.glass)` / `.glassProminent`; glass variants `Glass.regular` / `.clear` / `.identity`; modifiers `.tint(_:)` (semantic meaning only) and `.interactive()` (iOS only). Shapes include `.rect(cornerRadius: .containerConcentric)` which auto-matches the container's corner. **Minimum OS: macOS 26.0 / iOS 26.0, Xcode 26.** — https://www.conor.fyi/writing/liquid-glass-reference
- Hard rules from the same reference, which we adopt verbatim:
  - **Layer model:** content layer (no glass) → navigation layer (glass only) → overlay layer (vibrancy/fills).
  - **"Glass cannot sample other glass"** — never stack glass on glass; use one `GlassEffectContainer` when several glass elements must share a sampling region.
  - Do not put glass on content (lists, tables, media), do not use full-screen glass backgrounds, do not tint decoratively.
  - Accessibility is automatic: Reduce Transparency increases frosting, Increase Contrast adds stark borders, Reduce Motion dampens elastic effects. Apple's stated best practice: *"Let system handle accessibility automatically. Don't override unless absolutely necessary."*
  - Pitfall: the implementation is backed by `CABackdropLayer`; toggling `isHidden` mid-animation causes frame flashing.
- `.glassEffect()` is macOS 26-only; shipping apps that support 14/15 keep a **custom fallback** and branch at runtime. — https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo
- The most useful macOS-14 fallback finding (from a shipping app that faked glass on macOS 14): `.ultraThinMaterial` and `NSVisualEffectView` **blur the window backdrop, not in-app content**, so they cannot make an in-app "glass card". What actually sells the illusion is **the edge**: "A carefully crafted border that simulates how light catches the rim of a glass surface did more for the illusion than any amount of surface tweaking." Also: "A single shadow isn't enough" (layer several); use `.easeOut` rather than `.spring()` for hover; avoid `.drawingGroup()` because it breaks hit-testing; do not animate shadow geometry. — https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos
- Apple's own material vocabulary (ultraThin/thin/regular/thick, plus purpose-named materials for window / menu / popover / sidebar / titlebar / HUD) and the rule that macOS provides *vibrant* variants of all standard colors for use on materials. — https://developer.apple.com/design/human-interface-guidelines/materials and https://developer.apple.com/documentation/appkit/nsvisualeffectview

### 1.2 Best-in-class macOS floating palettes — concrete tokens

- **Raycast** (the closest peer product). Full extracted token set:
  - Surface ladder, dark-only: canvas `#07080a` → surface `#0d0d0d` → elevated `#101111` → card `#121212`.
  - Text ladder: ink `#f4f4f6`, body `#cdcdcd`, mute `#9c9c9d`, ash (disabled) `#6a6b6c`, stone `#434345`.
  - Borders: hairline `#242728` at 1px; soft `rgba(255,255,255,0.08)`; strong `rgba(255,255,255,0.16)`.
  - Radii scale: 4 / 6 / 8 / 10 / 16 / full. Spacing scale (8px base): 2 / 4 / 8 / 12 / 16 / 24 / 32.
  - **No drop shadows inside the UI** — depth comes from the surface-colour ladder + hairlines only. Shadows are reserved for the floating window itself.
  - Controls: primary button 36px tall, 8×16 padding, 8px radius, no shadow. Text input 36px tall, `#101111` fill, 1px `#242728` border, focused border → `rgba(255,255,255,0.16)`. Keycap glyph: 20px tall, 1×6 padding, 4px radius, gradient `#121212 → #0d0d0d`.
  - Type: Inter, positive letter-spacing 0.2–0.4px on body to keep dark UI airy.
  — https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/raycast/DESIGN.md and https://open-design.ai/plugins/design-system-raycast/
- **Raycast activation behaviour** (critical for us): interacting with the palette must **not activate the owning app**, so dismissing it returns the user to whatever app they were in. — https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette
- **Linear.** Near-black surfaces `#08090a` / `#0f1011`, paper-white type `#f7f8f8`, one accent used sparingly (`#5e6ad2`, `#8b5cf6`). Tight tracking `-0.022em`, weights in a low **400–510** band rather than bold, hairline borders at **0.5px**, radii of **6px and 12px**, compact 8–12px padding, almost no ornament. Its dark theme is "darkness as the native medium," with hierarchy from gradations of white opacity rather than colour. — https://designmd.cc/benchmarks/linear and https://opendesigner.io/design-systems/linear-app
- **Superhuman.** Everything reachable from one command palette (`⌘K`); the palette teaches its own shortcuts by displaying the key on the right of each row so you learn it once and never open the palette again. Design borrows from power tools (Sublime Text, command-line editors): "no clutter, just focus." — https://help.superhuman.com/hc/en-us/articles/45191759067411-Speed-Up-With-Shortcuts and https://nickgray.net/superhuman/
- **macOS 26 Spotlight** is the platform-native version of this pattern now: Quick Keys (short character sequences that expand to full actions, auto-generated from usage), inline action parameter fields so you never leave the palette, and clipboard history with a preview column on the left. — https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/ and https://macos-tahoe.com/blog/macos-tahoe-spotlight-quick-keys-complete-guide-2026/
- **Apple Writing Tools** — the closest first-party analogue to our panel. Selecting text surfaces a small Siri glyph; clicking opens a compact menu with Proofread / Rewrite / How does this sound? / Edit with Siri. Its proofread panel shows **per-change explanations with a one-click revert**, plus accept-all / reject-all in the nav bar, and **all changes are underlined with a glowing line**. Animated highlights on the selected text signal that the model is working. The redesign deliberately matches the Visual Intelligence pop-up for cross-feature consistency. — https://developer.apple.com/videos/play/wwdc2024/10168/, https://www.createwithswift.com/exploring-apple-intelligence-writing-tools/, https://www.tuaw.com/2026/07/20/apple-tests-faster-siri-writing-tools-for-mac
- **Grammarly for Mac** anchors its floating widget to text boxes and window corners so it is always findable, and lets the user slide the edge tab up/down when it collides with UI. Lesson: a floating surface must be repositionable and must remember where the user put it. — https://support.grammarly.com/hc/en-us/articles/4412816078349-Grammarly-for-Windows-and-Grammarly-for-Mac-user-guide
- **Warp** treats the accent colour as an explicit, single, swappable theme attribute used for tab indicator and block selection — one variable changes the whole personality without touching the core theme. We copy that structure (one `accent`, everything else neutral). — https://www.warp.dev/blog/how-we-designed-themes-for-the-terminal-a-peek-into-our-process and https://docs.warp.dev/terminal/appearance/custom-themes/
- **CleanShot X / Bartender / Things / Craft** — the shared trait of the premium menu-bar tier is restraint: the app "sits quietly in your menu bar, ready when you need it, without cluttering your dock or launching full-screen windows." — https://www.hackdesign.org/toolkit/cleanshot-x/
- **Arc / Dia** — Arc's premium feel comes from per-Space gradients and heavy theming; Dia (Chromium-based, AI-first URL bar) deliberately dropped all of it and reviewers found it visually indistinct. Lesson: an AI surface still needs a visual identity of its own, not just an input field. — https://blog.grusz.dev/arc-vs-dia-a-frontend-devs-take-on-two-browsers

### 1.3 Apple HIG — menu bar, settings, motion, typography

- **Menu bar extras:** a menu bar extra "exposes app-specific functionality using an icon that appears in the menu bar when your app is running, even when it's not the frontmost app." They live on the opposite side from app menus; the system hides them when space is short. Prefer an SF Symbol or an interface icon; **template images are preferred** because they auto-tint for light/dark without separate assets. Asset formats: a single SVG, a single PDF, or a 1×/2× PNG pair. — https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- Community HIG addendum for menu bar extras (sizing, hit area, template rendering): https://bjango.com/articles/designingmenubarextras/ and the practical `NSStatusItem` limits: https://multi.app/blog/pushing-the-limits-nsstatusitem
- **Settings windows:** use a single pane with no toolbar or tabs when grouping is unnecessary; when it is necessary, use the **dedicated settings toolbar style with centred tabs** — do not hand-roll a lookalike. General settings go first, advanced last. **Restore the last-displayed pane** on reopen. macOS users expect settings to apply immediately — **no Save button**. — https://zenn.dev/usagimaru/articles/b2a328775124ef?locale=en
- **Motion:** "prefer quick, precise animations… animations that combine brevity and precision tend to feel more lightweight and less intrusive." With Reduce Motion on, minimise or eliminate animation — but if the motion carries meaning (status change, hierarchy transition) **replace it with a non-motion animation (dissolve or highlight fade) rather than deleting it**. Replace sliding transitions with cross-fades; never autoplay. — https://developer.apple.com/design/human-interface-guidelines/motion and https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria/
- **Typography, macOS.** SF Pro is the system font. SF Pro **Text** for ≤19pt, SF Pro **Display** for ≥20pt (dynamic optical sizing interpolates between them at runtime). **macOS does not support Dynamic Type.** **10pt is the documented minimum size.** The built-in macOS text styles:

  | Style | Weight | Size | Line height | Emphasized |
  |---|---|---|---|---|
  | Large Title | Regular | 26 | 32 | Bold |
  | Title 1 | Regular | 22 | 26 | Bold |
  | Title 2 | Regular | 17 | 22 | Bold |
  | Title 3 | Regular | 15 | 20 | Semibold |
  | Headline | Bold | 13 | 16 | Heavy |
  | Body | Regular | 13 | 16 | Semibold |
  | Callout | Regular | 12 | 15 | Semibold |
  | Subheadline | Regular | 11 | 14 | Semibold |
  | Footnote | Regular | 10 | 13 | Semibold |
  | Caption 1 | Regular | 10 | 13 | Medium |
  | Caption 2 | Medium | 10 | 13 | Semibold |

  — https://apple-docs.everest.mt/docs/design/human-interface-guidelines/typography/
- SF Symbols use the same weight axis as SF Pro, so a symbol set to the same weight as adjacent text optically matches it — always pair weights. The system dynamically adjusts tracking per point size; Apple publishes tracking tables in the Design Resources. — https://developer.apple.com/videos/play/wwdc2020/10175/ and https://developer.apple.com/videos/play/wwdc2022/110381/
- **Accessibility environment values:** read `@Environment(\.accessibilityReduceTransparency)` and `@Environment(\.accessibilityReduceMotion)` and respect them; the documented technique is to raise opacity to 1.0 and drop low-opacity decoration when Reduce Transparency is on, and to gate `withAnimation()` when the animation involves movement. — https://github.com/cvs-health/ios-swiftui-accessibility-techniques/blob/main/iOSswiftUIa11yTechniques/Documentation/ReduceTransparency.md and https://mobilea11y.com/guides/swiftui/swiftui-settings/

### 1.4 AI streaming output — 2026 craft patterns

- **Token-by-token is the 2026 baseline.** First word must appear in **200–600 ms**; the user starts reading immediately and perceived latency collapses even though total time is unchanged. — https://thefrontkit.com/blogs/what-is-streaming-ui-in-ai-applications
- **Caret is the cheapest liveness signal.** "A blinking caret at the end of the streamed text is the cheapest possible 'alive' signal." Prior art: Cursor uses a thin vertical bar, Claude.ai a small filled square, ChatGPT a pulsing dot. — https://thepromptbench.com/ai-product-ux/streaming-ui-patterns-that-dont-break/
- **Skeletons beat spinners.** Show **3–5 shimmer lines at decreasing widths** to mimic natural line-length variation. Measured effect: skeleton screens cut perceived load time by ~**40%** versus a blank panel with a spinner, and near-eliminate the "is this broken?" click. — https://thefrontkit.com/blogs/what-is-streaming-ui-in-ai-applications
- Must-have streaming affordances: a persistent "streaming" indicator on the message, an always-available **Stop** that actually cancels the API call, and deferring structured rendering (code fences, tables) until the closing delimiter arrives. — https://www.aiuxplayground.com/pattern/streaming/ and https://www.setproduct.com/blog/ai-chat-interface-ui-design
- **Diffing prose:** compute a line-level diff first, then run a **word-level diff on each removed/added neighbour pair** and highlight only the intra-line changes — this is how GitHub's PR view and diff-match-patch work. For prose specifically, **side-by-side is better than stacked**. Diffs on typical documents compute in **under 50 ms**, but run them async so they never block the streaming UI. — https://github.com/git-cola/git-cola/pull/1542 and https://medium.com/illumination/building-a-visual-diff-system-for-ai-edits-like-git-blame-for-llm-changes-171899c36971
- The document-editor AI pattern library (accept/reject affordances, ghost text, hover-to-explain): https://aipatterns.substack.com/p/ai-patterns-for-document-editors
- 2026 AI-UI trend synthesis (streaming, provenance, reversibility, restraint over chrome): https://www.groovyweb.co/blog/ui-ux-design-trends-ai-apps-2026

### 1.5 SwiftUI / AppKit engineering constraints found in research

- **`NSPanel` recipe:** subclass `NSPanel` with `.nonactivatingPanel`, set `becomesKeyOnlyIfNeeded`, level `.floating`, host SwiftUI in `NSHostingView`, configure `collectionBehavior` for Spaces. `.nonactivatingPanel` means clicking does not activate your app, keeping the user's app frontmost. **Pitfall:** if you only `orderFront` and never `makeKey()`, `panel.close()` silently fails — you must call `makeKey()` when opening for programmatic close to work. — https://fazm.ai/blog/swiftui-floating-panel and https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices
- **`Text` streaming performance is a real, measured problem.** SwiftUI's `Text` does not wrap `NSTextView`; it renders via CoreGraphics + CoreText directly, and it lacks the decades of optimisation `NSTextView` has. Appending text to a `Text` in a `ScrollView` produces visible lag once **~50+ lines** are on screen, with high CPU on the main thread that worsens as lines accumulate. On macOS 15 specifically, trackpad scrolling in SwiftUI scroll views stutters with **~85% of execution time in `_hitTestForEvent`** (not present on macOS 14). — https://juniperphoton.substack.com/p/pro-to-swiftui-text-performance-issue and https://developer.apple.com/forums/thread/764264
- **`AXIsProcessTrustedWithOptions`:** passing `kAXTrustedCheckOptionPrompt: true` either shows the system dialog or sends the user to Settings → Privacy & Security → Accessibility. **The prompt never appears for a sandboxed app** (and `AXIsProcessTrusted` always returns false when sandboxed); the app must also be correctly signed. **The API keeps returning the stale value if the user changes the setting while the app is running** — you must poll. Multiple apps prompting at install time inundates the user, so time the request deliberately. — https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html and https://gertrude.app/blog/macos-request-accessibility-control
- **Spring presets** (iOS 17 / macOS 14+): `.smooth` = critically damped, no overshoot; `.snappy` = slightly underdamped, small overshoot; `.bouncy` = clearly underdamped with visible oscillation. Each has a `(duration:extraBounce:)` form. — https://nilcoalescing.com/blog/AnimationTimingInSwiftUI/ and https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-spring-animation
- **WCAG 2.2 AA:** normal text ≥ **4.5:1**; large text (≥18pt, or ≥14pt bold) ≥ **3:1**; non-text UI components (buttons, form field borders, focus rings, meaningful icons) ≥ **3:1**. Unchanged from 2.1. — https://www.w3.org/TR/WCAG22/ and https://webaim.org/resources/contrastchecker/

### 1.6 Brand facts for the three providers

- **Anthropic:** core palette dark `#141413`, light `#faf9f5`, mid grey `#b0aea5`, light grey `#e8e6dc`; accents `#d97757` (the terracotta), `#6a9bcc`, `#788c5d`. Also cited as `#D4A27F` / `#191919` / `#FFFFFF`. — https://www.brandcolorcode.com/anthropic and https://www.loftlyy.com/en/anthropic
- **OpenAI:** OpenAI Black `#0F0F0F`, Off White `#FAFAFA`, ChatGPT Green `#10A37F`. — https://colorarchive.org/brands/openai/
- **Google Gemini:** a gradient logo running cool blue → violet-red (variously described as orange → purple → blue). There is no single official flat hex; Google's own product blue is the safe anchor. — https://logos-world.net/google-gemini-logo/ and https://en.wikipedia.org/wiki/Google_Gemini

---

## 2. Identity

### 2.1 Personality — three words

> **Instant. Luminous. Precise.**

- **Instant** — the panel is on screen before you finish releasing the hotkey; first token inside 600 ms; every action has a key.
- **Luminous** — one violet-to-aqua light source in an otherwise near-black, chromeless UI. Light is the only decoration.
- **Precise** — hairlines, tabular numbers, no gradients on text, no rounded-friendly typefaces, nothing decorative that isn't carrying information.

Tone of voice: terse, lowercase-friendly, never chirpy. "Stopped." not "Oops, we stopped!". Errors state the fact then the fix, in that order, one line each.

**Anti-patterns, banned outright:** Comic Sans or any handwriting/rounded display face; the sky-blue→navy gradient in the current build; emoji anywhere in the UI; drop shadows on text; more than one accent hue on screen at once; skeuomorphic glass "shine" streaks; spinners as the primary loading state.

### 2.2 Logo mark — "Caret Ascend"

One mark, three renditions: **app icon** (tile + mark + spark), **in-app glyph** (mark + spark, no tile), **menu-bar template** (mark only, monochrome). Same geometry in all three so they read as one thing.

Concept: a text **caret** (`^` — the insertion point, and the "up/better" arrow) lifting off a **baseline bar** (the line of text), with a four-point **spark** at the upper right (the AI signal). Silhouette is a chevron over a bar, which survives 16pt rendering.

#### Canvas and coordinate convention

- Canvas **1024 × 1024**.
- **All coordinates below are in a top-left origin system, y increasing downward.** Core Graphics on macOS is bottom-left origin — either flip the CTM (`ctx.translateBy(x:0,y:1024); ctx.scaleBy(x:1,y:-1)`) or subtract each y from 1024. Do this once, at the top; do not mix.
- Fractions of the canvas are given in parentheses for scaling to other sizes.

#### Layer 1 — Tile (app icon only; omit for in-app glyph and menu bar)

| Property | Value |
|---|---|
| Shape | Rounded rectangle, **continuous** corner curve (`.continuous` / `CGPath(roundedRect:cornerWidth:cornerHeight:)` with `NSBezierPath` continuous approximation) |
| Frame | x **100**, y **100**, w **824**, h **824** (0.0977 inset on all sides) |
| Corner radius | **185** (0.2246 × 824 — the macOS Big Sur+ icon geometry) |
| Fill | Linear gradient, start **(152, 100)** → end **(872, 924)**: `#1B1F3D` @0.00 · `#0E1226` @0.42 · `#05060E` @1.00 |
| Bloom | Radial gradient centred **(512, 430)**, radius **470**: `#7C6BFF` @ alpha 0.42 → `#7C6BFF` @ alpha 0.00. Normal blend, drawn over the fill. |
| Rim highlight | Stroke the tile path inset by **2**, lineWidth **3**, linear gradient top→bottom: `#FFFFFF` alpha 0.30 @0.00 → `#FFFFFF` alpha 0.00 @0.45 |
| Outer edge | Stroke the tile path, lineWidth **1**, `#000000` alpha 0.35 |

#### Layer 2 — Caret

| Property | Value |
|---|---|
| Path | `move(296, 604)` → `line(512, 388)` → `line(728, 604)` (open polyline, 3 points) |
| lineWidth | **104** (0.1016) |
| lineCap / lineJoin | `.round` / `.round` |
| Stroke | Linear gradient from **(296, 388)** to **(728, 604)**: `#FFFFFF` @0.00 · `#EDEBFF` @0.55 · `#B9AEFF` @1.00 |
| Shadow | color `#7C6BFF` alpha **0.55**, blur **46**, offset (0, **+14**) — app icon only; omit in the in-app glyph, omit in the template |

#### Layer 3 — Baseline bar

| Property | Value |
|---|---|
| Shape | Capsule (rounded rect, radius = h/2) |
| Frame | x **330**, y **686**, w **364**, h **68** → radius **34** |
| Fill | Linear gradient, **(330, 720)** → **(694, 720)**: `#7C6BFF` @0.00 · `#37D3E8` @1.00 |

#### Layer 4 — Spark

| Property | Value |
|---|---|
| Centre | **(762, 350)** |
| Tips | N (762, 276) · E (836, 350) · S (762, 424) · W (688, 350) — outer radius **74** |
| Construction | Closed path of **four quadratic Béziers**, each running tip→tip with its **control point at the centre (762, 350)**. This yields the classic concave four-point twinkle. |
| Fill | `#FFFFFF` |
| Glow | `#37D3E8` alpha **0.60**, blur **30**, offset (0, 0) |

#### Rendition variants

- **App icon (1024, D owns):** Layers 1 + 2 + 3 + 4. Export the standard `AppIcon` set (16/32/64/128/256/512/1024 @1×,@2×). At 32pt and below, drop **Layer 4** and increase caret lineWidth to **118** so the form doesn't thin out.
- **In-app glyph (used in panel header, Settings, onboarding):** Layers 2 + 3 + 4 only, no tile, no caret shadow, transparent background, trimmed to the tight bounding box of those layers (approx x 244–836, y 276–754 → 592 × 478; render into a square by centring). Drawn at 18×18 in the panel header and 64×64 in onboarding/About.
- **Menu-bar template (18 × 18 @1×, 36 × 36 @2×):** Layers 2 + 3 only, **solid `#000000`**, `image.isTemplate = true`. Caret lineWidth **118**, bar height **78**. Trim to bounding box, then pad to leave ~**8%** clear on all sides of the 18pt square. Ship as a single PDF or an SVG per HIG (template images auto-tint for menu-bar light/dark and for the "menu open" highlight state).
- **DMG background (D owns):** tile gradient (Layer 1 fill + bloom) full-bleed at the DMG window size; the in-app glyph centred horizontally at **22%** of window width, with its centre at **18%** of window height; wordmark "WriteBetter" below in SF Pro Display Semibold. Drag arrow in `#7C6BFF` at 40% alpha. No other ornament.

#### Wordmark

"WriteBetter" — SF Pro Display **Semibold**, tracking **−0.02 em**, one word, capital W and capital B, never spaced, never all-caps, never coloured (always `textPrimary`). The mark may sit to its left at cap-height + 12% with a gap of 0.42 × cap-height.

---

## 3. Colour system

Two complete appearances. **Dark is the design's native medium** (Linear's principle) and is the default for the floating panel; light is a full, first-class translation, not an inversion.

All contrast ratios below were computed with the WCAG 2.x relative-luminance formula against the stated background. **Every value used for body text passes AA 4.5:1.**

### 3.1 Dark appearance

| Token | Hex | Alpha | Use | Contrast |
|---|---|---|---|---|
| `bgBase` | `#070910` | 1.0 | Deepest ground; behind glass; onboarding backdrop | — |
| `surface` | `#0E1118` | 1.0 | Panel body fill (under the material), Settings window body | — |
| `surfaceRaised` | `#161A24` | 1.0 | Cards, chips at rest, list rows | — |
| `surfaceSunken` | `#0B0E15` | 1.0 | Text fields, the source-text strip, code/mono wells | — |
| `surfaceHover` | `#1D2230` | 1.0 | Hover fill for chips/rows | — |
| `stroke` | `#FFFFFF` | 0.09 | Default hairline (flattens to `#24262D` on `surface`) | 1.25:1 vs surface — decorative only |
| `strokeStrong` | `#FFFFFF` | 0.18 | Focused fields, selected chips, dividers that must read (`#393C42`) | 1.71:1 |
| `strokeGlass` | `#FFFFFF` | 0.28→0.04 | The panel's top-edge rim gradient (see §5.4) | — |
| `textPrimary` | `#F2F4F8` | 1.0 | Result text, headings, button labels | **17.15:1** on surface · 15.80:1 on raised |
| `textSecondary` | `#A8B0BF` | 1.0 | Source text, body copy, descriptions | **8.66:1** on surface · 7.97:1 on raised |
| `textTertiary` | `#8A93A6` | 1.0 | Labels, counts, keycap hints, placeholders | **6.12:1** on surface · 5.64:1 on raised · 6.26:1 on sunken |
| `textDisabled` | `#6E7789` | 1.0 | Disabled control labels **only** — never for information | 4.19:1 (exempt: disabled UI) |
| `accent` | `#7C6BFF` | 1.0 | **Non-text**: icons, focus ring, strokes, glow, progress | 4.86:1 on surface · 4.48:1 on raised (passes 3:1 non-text) |
| `accentText` | `#9A8CFF` | 1.0 | Accent-coloured **text** and links | **6.81:1** on surface |
| `accentFill` | `#6E5BFF` | 1.0 | Primary button fill; label is `#FFFFFF` | **4.56:1** white-on-fill |
| `accentPressed` | `#5B45E0` | 1.0 | Primary button pressed | 6.23:1 white-on-fill |
| `accentMuted` | `#7C6BFF` | 0.16 | Tinted chip/badge backgrounds (flattens `#201F3D` on surface) | — |
| `accentGradientEnd` | `#37D3E8` | 1.0 | The second stop of the signature gradient | 10.47:1 on surface |
| `streaming` | `#37D3E8` | 1.0 | Streaming caret, streaming pill, live halo | **10.47:1** on surface · 9.65:1 on raised |
| `success` | `#3DDC97` | 1.0 | Key validated, copied, replaced | **10.69:1** on surface |
| `warning` | `#F5B841` | 1.0 | Rate-limited, key missing, permission not granted | **10.62:1** on surface |
| `danger` | `#FF8080` | 1.0 | Invalid key, server error, offline | **7.78:1** on surface · 7.17:1 on raised |
| `diffAddBg` | `#3DDC97` | 0.14 | Diff insertion background (flattens `#122B27` on sunken) | text on it: 13.62:1 |
| `diffDelBg` | `#FF8080` | 0.14 | Diff deletion background (flattens `#2D1E24` on sunken) | — |
| `scrim` | `#000000` | 0.45 | Behind onboarding sheets | — |

**Signature gradient** (`accentGradient`): `#7C6BFF` @0.00 → `#37D3E8` @1.00, `.linear`, `startPoint: .topLeading`, `endPoint: .bottomTrailing`. Used on: the baseline bar of the mark, the streaming halo, the onboarding hero, the primary CTA's 1pt inner rim (not its fill). **Never on text. Never as a full-panel background.**

### 3.2 Light appearance

| Token | Hex | Alpha | Contrast |
|---|---|---|---|
| `bgBase` | `#F0F1F5` | 1.0 | — |
| `surface` | `#FFFFFF` | 1.0 | — |
| `surfaceRaised` | `#FFFFFF` | 1.0 | (separated by shadow, not by fill) |
| `surfaceSunken` | `#F4F5F9` | 1.0 | — |
| `surfaceHover` | `#EDEFF4` | 1.0 | — |
| `stroke` | `#000000` | 0.10 | flattens `#E6E6E6` |
| `strokeStrong` | `#000000` | 0.18 | flattens `#D1D1D1` |
| `textPrimary` | `#14161C` | 1.0 | **18.08:1** on white · 16.60:1 on sunken |
| `textSecondary` | `#4E5666` | 1.0 | **7.38:1** on white · 6.77:1 on sunken |
| `textTertiary` | `#6D7587` | 1.0 | **4.62:1** on white |
| `textDisabled` | `#9AA1B0` | 1.0 | (disabled only) |
| `accent` | `#5B45E0` | 1.0 | 6.23:1 on white |
| `accentText` | `#5B45E0` | 1.0 | 6.23:1 |
| `accentFill` | `#5B45E0` | 1.0 | 6.23:1 white-on-fill |
| `accentPressed` | `#4A35C7` | 1.0 | 8.00:1 white-on-fill |
| `accentMuted` | `#5B45E0` | 0.10 | — |
| `accentGradientEnd` | `#1596AC` | 1.0 | — |
| `streaming` | `#0E7C8C` | 1.0 | ≥4.5:1 |
| `success` | `#0B7A56` | 1.0 | **5.34:1** on white · 4.90:1 on sunken |
| `warning` | `#8A5200` | 1.0 | **6.39:1** on white |
| `danger` | `#C62828` | 1.0 | **5.62:1** on white |
| `diffAddBg` | `#0B7A56` | 0.12 | — |
| `diffDelBg` | `#C62828` | 0.12 | — |
| `scrim` | `#000000` | 0.20 | — |

### 3.3 Per-provider accents

Provider colour appears **only** as: the 8pt status dot in the provider chip, the provider icon tint, the 2pt left rail on the provider row in Settings, and the key-field focus ring on that provider's row. It **never** fills a surface larger than 40 × 40 and it **never** overrides `accent` for the app's own controls.

| Provider | Dark | Contrast (dark surface) | Light | Contrast (white) | Basis |
|---|---|---|---|---|---|
| Anthropic | `#D97757` | **6.05:1** | `#A64A28` | **5.78:1** | Anthropic's published accent |
| OpenAI | `#10A37F` | **5.91:1** | `#0B7C60` | **5.16:1** | ChatGPT Green |
| Gemini | `#4C8DF6` | **5.80:1** | `#1B62D6` | **5.58:1** | Google product blue (Gemini has no flat official hex) |

Muted chip background for a provider = provider colour @ **0.16** alpha on dark, @ **0.10** on light.
Provider colour is exposed by Agent P as `AIProvider.accent`. **Agent U must read it from there and must not hardcode these hexes** — but P should use exactly these values. If P's values differ, P's values win at runtime and this table is the reference for P.

### 3.4 Colour rules

1. One accent hue on screen at a time. If a provider dot is visible, the app accent is still `#7C6BFF` — the two coexist because the provider dot is ≤ 8pt.
2. Never colour body text with anything but the `text*` ramp, except: links (`accentText`), error text (`danger`), success confirmations (`success`).
3. Semantic colour is always paired with a shape or glyph so it survives colour-blindness: `success` always with `checkmark.circle.fill`, `danger` always with `exclamationmark.triangle.fill`, `warning` always with `exclamationmark.circle.fill`.
4. Under Increase Contrast: promote `stroke` → `strokeStrong`, `textTertiary` → `textSecondary`, and give every button a 1pt visible border.

---

## 4. Type scale

Font: **SF Pro** via `.system(size:weight:)` — never a named font string, so optical sizing works. Monospace: **SF Mono** via `.system(size:weight:design: .monospaced)`. Nothing else. `Font.custom` is banned.

macOS has no Dynamic Type, so these are fixed points. Minimum is 10pt (Apple's documented floor).

| Role | Size | Weight | Design | Tracking | Line height | Colour | Where |
|---|---|---|---|---|---|---|---|
| `displayTitle` | 22 | Semibold | default | −0.30 | 28 | textPrimary | Onboarding hero, About |
| `title` | 17 | Semibold | default | −0.20 | 22 | textPrimary | Settings pane title, onboarding step title |
| `subtitle` | 13 | Regular | default | 0 | 18 | textSecondary | One-line description under a title |
| `sectionHeader` | 11 | Semibold | default | **+0.60** | 14 | textTertiary | Uppercased group labels ("ORIGINAL", "PROVIDERS") |
| **`result`** | **14** | **Regular** | default | **0** | **21** | textPrimary | **The improved text — the hero type of the app** |
| `source` | 12 | Regular | default | 0 | 17 | textSecondary | The captured original text |
| `body` | 13 | Regular | default | −0.05 | 18 | textSecondary | Settings body copy, explanations |
| `label` | 12 | Medium | default | 0 | 16 | textPrimary | Field labels, row titles, chip text |
| `button` | 12 | Semibold | default | +0.10 | 16 | per button | All button labels |
| `caption` | 11 | Regular | default | +0.10 | 14 | textTertiary | Counts, timestamps, helper text |
| `keycap` | 10 | Medium | **monospaced** | +0.20 | 12 | textTertiary | Keyboard hint glyphs |
| `mono` | 12 | Regular | **monospaced** | 0 | 16 | textPrimary | API key fields, model IDs |
| `badge` | 10 | Semibold | default | +0.40 | 12 | per semantic | Status pills ("STREAMING", "STOPPED") — uppercased |

Rules:
- Every numeric readout (`128 chars`, `+14 words`, `3 of 5`) uses **`.monospacedDigit()`** so it doesn't jitter while streaming.
- Uppercased styles (`sectionHeader`, `badge`) are uppercased in the view layer, not in the string constant.
- SF Symbols adjacent to text use `.font(.system(size: <text size>, weight: <text weight>))` so weights match optically (per WWDC20-10175). Never set a symbol's size independently of its label.
- `result` text sets `.lineSpacing(21 - 14 * 1.19 ≈ 4.3)` → use **`.lineSpacing(4)`** and `.textSelection(.enabled)`.
- Line-height column above is a target; in SwiftUI express it as `.lineSpacing(lineHeight − ceil(size × 1.19))`, clamped ≥ 0.
- Tracking via `.tracking(_:)`. Values are in points, per Apple's tracking-table convention.

---

## 5. Spacing, radii, elevation

### 5.1 Spacing scale (4pt base)

`2, 4, 6, 8, 12, 16, 20, 24, 32, 40`

Named: `xxs 2 · xs 4 · sm 6 · md 8 · lg 12 · xl 16 · xxl 20 · h1 24 · h2 32 · h3 40`

Standing rules:
- Panel outer horizontal inset: **16**. Panel top rail height **44**, bottom rail height **48**.
- Gap between stacked sections inside the panel: **12**.
- Card internal padding: **12** all round (14 for the result canvas).
- Gap between a label and its control: **6**. Between related controls in a row: **8**. Between unrelated groups: **20**.
- Settings pane content inset: **24** horizontal, **20** vertical. Row height **36** minimum; row with a subtitle **52**.
- Minimum hit target for any clickable: **28 × 28** (use `.contentShape(Rectangle())` to reach it when the glyph is smaller).

### 5.2 Radius scale

| Token | Value | Applied to |
|---|---|---|
| `panel` | **18** | The floating panel, onboarding sheet |
| `window` | **12** | Settings window content clipping (AppKit draws the actual window corner) |
| `card` | **12** | Result canvas, source strip, Settings group boxes, provider rows |
| `control` | **9** | Buttons, text fields, model pickers |
| `chip` | **8** | Quick-action chips, provider chip, status pills that aren't capsules |
| `keycap` | **5** | Keyboard hint glyphs |
| `pill` | capsule | Status badges, the "Copied" confirmation, the provider dot ring |

**All** rounded rectangles use `style: .continuous`. No exceptions.

**Concentric rule.** It applies only to an element that is *flush-nested* — inset by ≤ 8pt from its container's edge. For those: `innerRadius = outerRadius − inset`. Worked examples, all of which appear in this design:

| Container | R | Nested element | Inset | Required inner R |
|---|---|---|---|---|
| Panel | 18 | 1pt inner rim stroke | 1 | **17** |
| Panel | 18 | Header rail (clipped by panel shape) | 0 | **18** (inherits) |
| Panel | 18 | Footer rail (clipped by panel shape) | 0 | **18** (inherits) |
| Card | 12 | Inner fill / selection highlight | 1 | **11** |
| Card | 12 | Provider row left rail | 0 | **12** (inherits, leading corners only) |
| Control | 9 | Focus ring drawn outside at +2 | −2 | **11** |

Freestanding elements — cards inset 16 from the panel edge, chips inset 12 from the card edge — do **not** apply the formula; they use the fixed radius scale above. (Applying it literally at those insets yields radii of 2–6, which reads as a mistake.)

On macOS 26 only, prefer `.rect(cornerRadius: .containerConcentric)` for the flush-nested cases and let the system compute it.

### 5.3 Elevation scale

| Level | Definition | Where |
|---|---|---|
| `e0` | `surface` fill, no stroke, no shadow | Panel body, Settings body |
| `e1` | `surfaceRaised` fill + 1pt `stroke`, **no shadow** | Cards, chips, list rows. *(Raycast principle: depth from the surface ladder, not shadows.)* |
| `e2` | `surfaceRaised` fill + 1pt `strokeStrong` + shadow `#000` α0.35, blur 20, y +8 | Provider menu, model picker popover |
| `e3` | Two shadows: `#000` α0.55 blur **44** y **+18**, and `#000` α0.30 blur **10** y **+3**; plus 0.5pt outer stroke `#000` α0.60; plus the rim highlight (§5.4) | The floating panel, the onboarding sheet |
| `glow` | `accent` α0.30, blur 28, y 0 — additive, animated (§6) | Streaming state on the panel edge |

Light appearance shadows: multiply every alpha by **0.45** and reduce blur by 25%.

### 5.4 The glass recipe (macOS 14 fallback)

The research is unambiguous that the **edge**, not the fill, sells glass. Build the panel background as exactly these five layers, bottom to top:

1. `NSVisualEffectView` — material `.hudWindow`, `blendingMode = .behindWindow`, `state = .active`, `isEmphasized = true`. Wrapped in an `NSViewRepresentable`; **not** SwiftUI's `.ultraThinMaterial`, which does not sample behind a borderless panel reliably.
2. A tint fill: `surface` at **0.72** alpha (dark) / **0.82** alpha (light).
3. A top-down vignette: linear gradient `#FFFFFF` α0.05 @0.00 → α0.00 @0.30, then `#000000` α0.00 @0.60 → α0.14 @1.00.
4. **Rim highlight** (the important one): stroke the panel path at lineWidth **1**, with a linear gradient top→bottom: `#FFFFFF` α**0.28** @0.00 → α**0.10** @0.22 → α**0.04** @0.55 → α**0.02** @1.00.
5. **Outer edge**: stroke the panel path at lineWidth **0.5** with `#000000` α0.60, drawn just outside layer 4.

On macOS 26, replace layers 1–3 with `.glassEffect(.regular, in: .rect(cornerRadius: 18))` inside a single `GlassEffectContainer`, and keep layers 4 and 5 at half their alphas (the system already draws a rim). **Do not nest a second glass surface inside the panel** — everything inside is `e0`/`e1`.

---

## 6. Motion spec

Global: `@Environment(\.accessibilityReduceMotion) private var reduceMotion`. Every entry below states its fallback. Per Apple, motion that carries meaning is **replaced with a dissolve**, not deleted.

Define one helper the whole app uses:

- `Motion.instant` = `.easeOut(duration: 0.12)`
- `Motion.quick` = `.easeOut(duration: 0.16)`
- `Motion.standard` = `.easeInOut(duration: 0.22)`
- `Motion.enter` = `.spring(response: 0.28, dampingFraction: 0.86)`  (equivalently `.snappy(duration: 0.28)`)
- `Motion.celebrate` = `.spring(response: 0.26, dampingFraction: 0.62)` (equivalently `.bouncy(duration: 0.26)`)
- Under `reduceMotion`, every one of these collapses to `.easeInOut(duration: 0.12)` and any transform (scale/offset) is dropped, keeping only opacity.

| # | Trigger | Property | Duration | Easing | reduceMotion fallback |
|---|---|---|---|---|---|
| M1 | Panel presented | opacity 0→1 | **180 ms** | `.easeOut` | opacity only, **120 ms** `.easeOut` |
| M2 | Panel presented | scale 0.965→1.0, y +8→0 | **280 ms** | `Motion.enter` | **dropped** |
| M3 | Panel dismissed | opacity 1→0, scale 1→0.98 | **120 ms** | `.easeIn` | opacity only, 100 ms |
| M4 | Capturing → skeleton | 3 shimmer bars, widths 92% / 78% / 46% of canvas, height 10, radius 5, gap 10; travelling highlight gradient sweeps left→right | period **1400 ms** | `.linear.repeatForever(autoreverses: false)` | **static bars** at `#FFFFFF` α0.10, no sweep |
| M5 | First token arrives | skeleton → text cross-fade | **160 ms** | `.easeInOut` | same (cross-fade is already the reduced form) |
| M6 | Streaming | caret: 2 × 16 rounded bar, `streaming` colour, opacity 1↔0.15 | **900 ms** | `.easeInOut.repeatForever(autoreverses: true)` | **solid, no blink** |
| M7 | Streaming | panel rim (layer 4) accent component α 0.20↔0.45 | **1600 ms** | `.easeInOut.repeatForever(autoreverses: true)` | **static at 0.32** |
| M8 | Each flushed token batch | trailing run opacity 0→1 | **140 ms** | `.easeOut` | **no fade** — text appears instantly |
| M9 | Stream completes | caret opacity → 0; word-delta badge appears | **200 ms** / `Motion.enter` | `.easeOut` / spring | fade 120 ms, no spring |
| M10 | Stream completes | Copy button: 1× pulse, scale 1→1.04→1 | **320 ms** | `Motion.celebrate` | **dropped** (button just becomes enabled) |
| M11 | Quick-action chip hover | fill `surfaceRaised`→`surfaceHover`, stroke `stroke`→`strokeStrong` | **120 ms** | `.easeOut` — *not* a spring (per Klarity finding) | same |
| M12 | Any button press | scale 1→0.97 | **90 ms** | `.easeOut` | **dropped**; use fill darkening instead |
| M13 | Provider switch | chip label + dot colour | **160 ms** label (`.contentTransition(.opacity)`), **240 ms** colour | `.easeInOut` | same |
| M14 | Regenerate (`⌘R`) | old result opacity 1→0, then skeleton | **100 ms** out | `.easeInOut` | same |
| M15 | Copied / Replaced confirmation | checkmark scale 0.6→1.0 + opacity 0→1, hold **500 ms**, then M3 | **260 ms** | `Motion.celebrate` | opacity 120 ms, hold 500 ms, no scale |
| M16 | Error card appears | opacity 0→1, y −4→0 | **200 ms** | `Motion.enter` | opacity 140 ms, no offset |
| M17 | Focus ring | ring opacity 0→1, width 0→2 | **100 ms** | `.easeOut` | same |
| M18 | Counter changes (chars, word delta) | `.contentTransition(.numericText())` | **220 ms** | `.snappy` | `.contentTransition(.identity)` |
| M19 | Source strip expand/collapse | height, chevron rotate 0°→180° | **200 ms** | `Motion.standard` | height only, 120 ms, chevron swaps glyph instead of rotating |
| M20 | Menu-bar icon "working" | a 3pt dot at the icon's upper-right, opacity 0.30↔1.0 | **1100 ms** | `.easeInOut.repeatForever(autoreverses: true)` | **static dot at 1.0** |
| M21 | Settings tab change | cross-fade | **150 ms** | `.easeInOut` | same |
| M22 | Onboarding step advance | cross-fade + x offset 12→0 | **220 ms** | `Motion.enter` | cross-fade only, 140 ms |

**Never animate:** `shadow(radius:)`, blur radii, `NSVisualEffectView` material changes, or the layout of the whole result text block. Animate an overlay stroke's opacity instead of a shadow.
**Never use** `.drawingGroup()` on the panel — it breaks hit-testing.

---

## 7. Screen specs

### 7.1 The floating improvement panel

**Window.** `KeyablePanel: NSPanel`, styleMask `[.borderless]`, `isFloatingPanel = true`, `level = .floating`, `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = true` (AppKit draws it — see §11 for why the current SwiftUI shadow is clipped), `isMovableByWindowBackground = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`.

**Size.** Width **560** fixed. Height intrinsic, clamped **300 … 620**. Position: cursor point + (12, −height − 12), then clamped into `NSScreen.visibleFrame` with a 12pt margin (keep the existing clamping logic; only the offsets change). Remember the last user-dragged offset **per screen** and reuse it for the session (Grammarly lesson).

#### Wireframe — streaming state

```
┌────────────────────────────────────────────────────────────────────┐ ← panel r18, e3
│  ◤ WriteBetter                        ●Anthropic · Sonnet 4.5 ⌄  ✕ │ 44
├────────────────────────────────────────────────────────────────────┤
│ ORIGINAL                                            312 chars   ⌄  │ 18
│ ┌────────────────────────────────────────────────────────────────┐ │
│ │ this is a test text that needs improvement and should be made  │ │ card r12
│ │ better, i wrote it fast and it shows                           │ │ 2 lines
│ └────────────────────────────────────────────────────────────────┘ │
│                                                                    │ 12
│ IMPROVED                          ◈ STREAMING              +14 wds │ 18
│ ┌────────────────────────────────────────────────────────────────┐ │
│ │ This is a test passage that needs improvement and should be    │ │
│ │ made better. I wrote it quickly, and it shows.▌                │ │ ≥132, ≤300
│ │                                                                │ │ scrolls
│ └────────────────────────────────────────────────────────────────┘ │
│                                                                    │ 12
│ ⟨ ✨ Improve │ ✂ Shorten │ 🅰 Formal │ ✓ Fix grammar │ ⤢ Expand ⟩  │ 34
│                                                                    │ 10
│ ┌────────────────────────────────────────────────────────────────┐ │
│ │ ⌘K  Tell it what to change…                              ⌘↩ →  │ │ 38
│ └────────────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────────┤
│ esc stop   ⌘R redo   ⌘, settings          [ ■ Stop ]  [  Copy  ]   │ 48
└────────────────────────────────────────────────────────────────────┘
```

#### Component inventory

| # | Component | Spec |
|---|---|---|
| C1 | Header rail | h **44**, horizontal inset **16**. Whole rail is the drag region (`.contentShape(Rectangle())`). No visible divider — separation comes from the 12pt gap. |
| C2 | Brand glyph | In-app mark glyph, **18 × 18**, followed by "WriteBetter" in `label` style, `textPrimary` at 0.85. Gap **8**. |
| C3 | Provider chip | Button. Content: 8pt filled circle in `provider.accent`, gap 6, `displayName` in `label`, ` · `, short model name in `caption` `textTertiary`, gap 4, `chevron.down` 9pt. Padding 8×10, `surfaceRaised`, r**8**, 1pt `stroke`. Hover → `surfaceHover`. Click opens the provider menu (§8). Max width 220, model name truncates with `.tail`. |
| C4 | Close button | `xmark` 11pt semibold, `textTertiary`, in a 24 × 24 circle of `surfaceRaised`; hover → `surfaceHover` + `textPrimary`. `.help("Close (esc)")`. |
| C5 | Section header | `sectionHeader` style, uppercased. Row also carries right-aligned metadata in `caption` + `.monospacedDigit()`. |
| C6 | Source strip | Card r**12**, `surfaceSunken`, 1pt `stroke`, padding **12**. `source` type, **`.lineLimit(2)`** collapsed / `.lineLimit(nil)` expanded (max 8 lines then scrolls). Leading 2pt full-height rail in `textTertiary` α0.35 inside the card, flush left. Expand chevron in C5's right side, `chevron.down`/`chevron.up` 10pt. |
| C7 | Result canvas | Card r**12**, `surfaceSunken`, 1pt `stroke` (→ `danger` α0.45 in error state, → `streaming` α0.35 while streaming), padding **14**. Min height **132**, max **300**, then `ScrollView(.vertical)`. Content is a **single `Text`** in `result` style, `.textSelection(.enabled)`. |
| C8 | Streaming caret | 2 × 16 capsule, `streaming`, appended inline after the last glyph (use `Text` + a trailing `Image` is wrong — overlay it at the trailing baseline of the last line via `.overlay(alignment: .bottomTrailing)` on a zero-width trailing `Text(" ")`). Simplest correct approach: append `"\u{200B}"` and overlay the caret aligned to the text's `.lastTextBaseline`. |
| C9 | Streaming badge | Pill: 6pt `streaming` dot + "STREAMING" in `badge` style. Capsule, `streaming` α0.14 fill, 8×4 padding. |
| C10 | Quick-action rail | `ScrollView(.horizontal, showsIndicators: false)` over `HStack(spacing: 8)` of `QuickAction.allCases`. **Rendered generically — never hardcode names or count.** Chip: icon (11pt) + title (`button` style), padding 8×12, h **34**, `surfaceRaised`, r**8**, 1pt `stroke`. Hover per M11. Selected (= the action that produced the current result): fill `accentMuted`, stroke `accent` α0.55, label `accentText`. Fade-out mask 16pt wide at both scroll edges. |
| C11 | Prompt bar | h **38**, `surfaceSunken`, r**9**, 1pt `stroke` → `accent` at 1.5pt when focused (M17). Leading: `⌘K` keycap when unfocused, hidden when focused. `TextField` in `body` style, placeholder "Tell it what to change…" in `textTertiary`. Trailing: `arrow.up.circle.fill` 18pt in `accent`, only when non-empty; plus a `⌘↩` keycap hint. |
| C12 | Footer rail | h **48**, horizontal inset **16**, top border 1pt `stroke`, fill `#000` α0.14 (dark) / `#000` α0.03 (light). |
| C13 | Keycap hint | `keycap` style text in a 5pt-radius box, `surfaceRaised`, 1pt `stroke`, padding 5×2, followed by a `caption` label with 4pt gap. Group spacing **12**. |
| C14 | Secondary button | h **30**, padding 0×14, r**9**, `surfaceRaised`, 1pt `stroke`, label `button` style `textPrimary`. Hover → `surfaceHover`. |
| C15 | Primary button | h **30**, padding 0×16, r**9**, fill `accentFill`, label `button` style `#FFFFFF` (4.56:1 ✓), plus a 1pt inner rim in `accentGradient` at α0.5. Hover: **fill unchanged** (contrast-preserving) + outer glow `accent` α0.35 blur 12 + M12-less 1.02 scale. Pressed: `accentPressed`. Disabled: fill `surfaceRaised`, label `textDisabled`, no rim. |

#### States

| State | Result canvas | Quick actions | Prompt bar | Footer left (hints) | Footer right |
|---|---|---|---|---|---|
| **capturing** (0–150 ms, before the first byte) | M4 skeleton, 3 bars | enabled, dimmed to 0.6 | enabled | `esc cancel` | `[ ■ Stop ]` only |
| **streaming** | text + M8 fade-in + M6 caret; `streaming` badge in C5; canvas stroke `streaming` α0.35; panel rim pulses (M7) | dimmed 0.6, still clickable (click = cancel + re-run with that action) | enabled | `esc stop · ⌘R redo · ⌘, settings` | `[ ■ Stop ]` `[ Copy ]` (Copy enabled once ≥1 char, copies partial) |
| **done** | final text, no caret, canvas stroke back to `stroke`; C5 right shows `+14 words` / `−22 words` via M18 | full opacity; the used action shows selected | enabled | `esc close · ↩ copy · ⌘↩ replace · ⌘R redo` | `[ Replace ]` `[ Copy ]` (Copy pulses once, M10) |
| **cancelled** | partial text retained; badge becomes `STOPPED` pill in `warning` α0.14 with `warning` text; canvas stroke `warning` α0.30 | full opacity | enabled | `esc close · ↩ copy · ⌘R redo` | `[ Redo ]` `[ Copy ]` |
| **empty-input** (`emptyInput`) | Replaces the whole Source + Result block with a centred empty card, h 132: `doc.on.clipboard` 22pt `textTertiary`; "Nothing to improve" (`label`); "Copy some text with ⌘C, then press ⌘⇧Space." (`caption`) | hidden | hidden | `esc close` | `[ Try again ]` (re-reads the pasteboard) |
| **error** (any `AIServiceError` except the three below) | Error card (see below) | full opacity | enabled | `esc close · ⌘R retry` | `[ Retry ]` primary |
| **no-API-key** (`noProviderConfigured` / `missingKey`) | Setup card (see below) | hidden | hidden | `esc close · ⌘, settings` | `[ Save & run ]` primary, disabled until the field is non-empty |
| **offline** (`offline`) | Error card with `wifi.slash`, "You're offline." / "Reconnect and press ⌘R." | dimmed 0.5, disabled | disabled | `esc close · ⌘R retry` | `[ Retry ]` |
| **invalid-key** (`invalidKey`) | Error card with `key.fill` in `danger`, `errorDescription`, `recoverySuggestion`, plus an inline key field pre-focused | hidden | hidden | `esc close · ⌘, settings` | `[ Save & retry ]` |
| **rate-limited** (`rateLimited`) | Error card with `hourglass` in `warning`; if `retryAfter` is non-nil, a live countdown "Retry in 14s" using M18 and an auto-retry when it hits 0 | dimmed | enabled | `esc close` | `[ Retry now ]` |
| **quota** (`quotaExceeded`) | Error card with `creditcard.fill` in `warning`; secondary button "Open billing ↗" → `provider.consoleURL` | hidden | hidden | `esc close · ⌘] next provider` | `[ Switch provider ]` if another key exists, else `[ Open billing ↗ ]` |

**Error card** (fills the result canvas, replacing C7's text): `HStack(alignment: .top, spacing: 10)` — a 16pt SF Symbol in the semantic colour; a `VStack(alignment: .leading, spacing: 4)` of `error.errorDescription` in `body` at `textPrimary`, then `error.recoverySuggestion` in `caption` at `textTertiary`. Canvas stroke → semantic colour α0.45, canvas fill → semantic colour α0.06 over `surfaceSunken`. Card animates in per M16. **Never render a raw `error.localizedDescription` string or an HTTP status code.**

**Setup card** (no-API-key state, fills the result canvas): `sectionHeader` "GET STARTED"; a 3-up segmented row of provider tiles (icon + name + a `key.fill` badge if configured); below it a `SecureField` with the selected provider's `keyPlaceholder` in `mono` style; below that a `caption` row "Stored in your Mac's Keychain. Never leaves your device." and a link "Get a key ↗" → `provider.consoleURL`. Pressing Return validates via `AIServiceFactory.service(for:apiKey:modelID:)` + `validateKey()`, shows an inline spinner on the button for ≤4 s, then either saves and immediately runs the improvement, or flips to an inline `danger` caption under the field.

#### Full keyboard map

| Key | Action | Available when | Shown as hint |
|---|---|---|---|
| `esc` | streaming → cancel stream (keeps partial); otherwise → close panel | always | yes, first slot |
| `↩` | Copy result to pasteboard, show M15, close | result non-empty, focus not in a text field | yes |
| `⇧↩` | Copy result, **do not close** | same | no (in Help) |
| `⌘↩` | Replace in place: close, reactivate the previously-frontmost app, paste | result non-empty **and** Accessibility granted | yes, when granted; when not granted the `[ Replace ]` button is present but shows a permission explainer on click |
| `⌘C` | If a selection exists in the result, copy it; else copy the whole result (no close) | always | no |
| `⌘R` | Regenerate — re-run the last request unchanged | not capturing | yes |
| `⌘K` | Focus the prompt field | always | inline in C11 |
| `⌘1`…`⌘9` | Run `QuickAction.allCases[n-1]` — **generated from the array, only for indices that exist** | not capturing | shown as a small index badge on each chip on `⌘`-hold |
| `⌘]` | Next configured provider, re-run | ≥2 configured providers | in the provider menu |
| `⌘[` | Previous configured provider, re-run | ≥2 configured providers | in the provider menu |
| `⌘,` | Open Settings (panel stays open) | always | yes, third slot |
| `⌘⌫` | Clear the prompt field | prompt field focused | no |
| `Tab` / `⇧Tab` | Cycle focus: provider chip → result canvas → quick-action rail → prompt field → Replace → Copy → close | always | no |
| `↑` / `↓` | Scroll the result canvas by one line | result canvas focused | no |
| `?` | Toggle a shortcuts overlay listing every binding above | prompt field not focused | in the footer as `? keys` when the panel is idle |

Holding `⌘` for >400 ms reveals index badges on the quick-action chips and swaps footer hints to their `⌘` variants (Superhuman's teach-the-shortcut pattern).

### 7.2 Settings window

SwiftUI `Settings { }` scene → a real macOS settings window. `TabView` with the **settings toolbar style** (centred tabs) per HIG. **Restore the last-viewed tab.** **No Save button — everything applies immediately.**

Size: **560 × 620**, non-resizable width, resizable height 560…760.

#### Wireframe — Providers tab

```
┌──────────────────────────────────────────────────────────┐
│            ⬡ Providers    ⚙ General    ⓘ About           │ ← settings tabs
├──────────────────────────────────────────────────────────┤
│                                                          │ 20
│  DEFAULT PROVIDER                                        │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐            │
│  │ ● Anthropic│ │ ○ OpenAI   │ │ ○ Gemini   │            │ 3-up, h 56
│  │   ✓ key    │ │   add key  │ │   ✓ key    │            │
│  └────────────┘ └────────────┘ └────────────┘            │
│                                                          │ 20
│  ┃ ● Anthropic                              ✓ Verified   │ ← 2pt provider rail
│  ┌──────────────────────────────────────────────────────┐│
│  │ API key                                              ││
│  │ ┌──────────────────────────────────┐ ┌────────────┐  ││
│  │ │ 🔑 sk-ant-api03-••••••••••••3f2a │ │   Test     │  ││ h 32
│  │ └──────────────────────────────────┘ └────────────┘  ││
│  │ Stored in Keychain. Get a key ↗                      ││
│  │                                                      ││
│  │ Model            ┌──────────────────────────────┐    ││
│  │                  │ Claude Sonnet 4.5 · Best… ⌄  │    ││ h 28
│  │                  └──────────────────────────────┘    ││
│  └──────────────────────────────────────────────────────┘│
│                                                          │
│  ┃ ○ OpenAI                                   No key     │
│  ┌──────────────────────────────────────────────────────┐│ collapsed → h 44
│  │ 🔑 sk-…                                     [ Add ]  ││
│  └──────────────────────────────────────────────────────┘│
│                                                          │
│  ┃ ○ Google Gemini                          ✓ Verified   │
│  ┌──────────────────────────────────────────────────────┐│ collapsed
│  └──────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────┘
```

Components:
- **Default-provider segmented row.** 3 tiles, equal width, h **56**, r**12**, `surfaceRaised`, 1pt `stroke`. Selected: `accentMuted` fill + `accent` 1.5pt stroke + the app's radio dot in `accent`. Each tile: `provider.iconSymbol` 15pt tinted `provider.accent`, `displayName` in `label`, and a `caption` status line ("✓ key" `success` / "add key" `warning`). Selecting a provider with no key selects it **and** auto-expands its row below and focuses the key field.
- **Provider rows.** One per `AIProvider.allCases`. Card r**12**, `surfaceRaised`, 1pt `stroke`, with a 2pt leading rail in `provider.accent` (leading corners r12). The selected provider's row is expanded by default; the others collapse to a 44pt summary row (click anywhere to expand; only one expanded at a time).
- **Key field.** `SecureField`, `mono` style, h **32**, `surfaceSunken`, r**9**. Placeholder = `provider.keyPlaceholder`. When a key exists, show a masked form: first 12 chars + `••••••••` + last 4, and a "Change" text button that clears and focuses. If `provider.keyPrefixHint != nil` and the typed key doesn't start with it, show an inline `warning` caption "That doesn't look like a \(hint)… key" — **warning, not blocking**.
- **Test button.** h **32**, `control` r9, secondary style. States: `Test` → (spinner + `Testing…`, disabled, ≤ 6 s) → `✓ Verified` in `success` for 2 s then back to `Test`, or `✕ Invalid` in `danger` with the `recoverySuggestion` as a caption below the field. Uses `AIServiceFactory.service(for:apiKey:modelID:).validateKey()`.
- **Model picker.** SwiftUI `Picker` with `.menu` style over `provider.models`. Row content: `name` in `label` + `blurb` in `caption` `textTertiary`. Index 0 is the default. Changing it calls `setModelID(_:for:)` immediately.
- **Console link.** `Link` "Get a key ↗" → `provider.consoleURL`, `accentText`, `caption` style, `arrow.up.right` 9pt.
- **Delete key.** Right-click a provider row → "Remove key" (calls `setAPIKey("", for:)`), plus a `trash` button in the expanded row's top-right at `textTertiary`, hover `danger`. Confirmation is an inline undoable pill ("Key removed. Undo"), not an alert.

#### General tab

```
  SHORTCUT
  ┌────────────────────────────────────────────────────┐
  │ Improve text          ⌘ ⇧ ␣                        │  h 44  (v1: display-only,
  └────────────────────────────────────────────────────┘        keycaps, with a
                                                                caption "Custom
  CAPTURE                                                        shortcuts coming soon")
  ┌────────────────────────────────────────────────────┐
  │ Use the current selection            ( ●   )       │  Toggle → autoCaptureSelection
  │ Reads selected text instead of the clipboard.      │
  ├────────────────────────────────────────────────────┤
  │ ⚠ Accessibility access needed        [ Grant… ]    │  only when not trusted
  │ Lets WriteBetter read your selection and paste     │
  │ the result back. Everything else works without it. │
  └────────────────────────────────────────────────────┘

  APP
  ┌────────────────────────────────────────────────────┐
  │ Launch at login                      (   ○ )       │
  ├────────────────────────────────────────────────────┤
  │ Appearance          [ System ⌄ ]                   │  System / Dark / Light
  ├────────────────────────────────────────────────────┤
  │ Reduce visual effects                (   ○ )       │  forces the opaque surface
  └────────────────────────────────────────────────────┘   even without the system setting
```

- Toggle rows: h **44** with a subtitle, **36** without. Title `label`, subtitle `caption` `textTertiary`. `Toggle` with `.toggleStyle(.switch)` and `.tint(accent)`.
- The Accessibility row only renders when `AXIsProcessTrusted() == false`. `warning` icon, `[ Grant… ]` secondary button. Behaviour in §9.
- `Launch at login` writes `SettingsStore.launchAtLogin`; U performs `SMAppService.mainApp.register()/unregister()` and, on throw, reverts the toggle and shows an inline `danger` caption.

#### About tab

Centred column: in-app mark glyph at **64 × 64**; "WriteBetter" `displayTitle`; "Version 1.0 (build)" `caption` `textTertiary` with `.monospacedDigit()`; a 12pt gap; a row of three link buttons (Website / Shortcuts / Privacy) using C14; at the bottom, `caption` "Your text is sent only to the provider you choose. Keys stay in your Mac's Keychain."; and a destructive text button "Reset all settings" in `danger` at 0.8 opacity.

#### Settings states

| State | Presentation |
|---|---|
| no keys at all | Default-provider row shows all three as "add key"; a `warning` banner pinned above it: "No provider configured — WriteBetter can't run yet." with a `[ Set up ]` button that expands the first provider row |
| one key | That provider is auto-selected as default; the other two collapse; no banner |
| multiple keys | All configured providers show `✓`; default is whatever the user picked; `⌘[`/`⌘]` cycling is enabled in the panel and a caption under the segmented row says "Switch in the panel with ⌘[ and ⌘]" |
| key fails validation | Row keeps the key (never silently delete it), stroke → `danger` α0.5, `✕ Invalid` badge, `recoverySuggestion` caption, field pre-selected on next focus. The provider stays selectable — the user may have a transient outage |
| test in flight | Button disabled with spinner; the rest of the row stays interactive |
| offline during test | `✕ Offline` badge with "Reconnect and press Test again." |

### 7.3 Menu-bar menu

`MenuBarExtra` with **`.menuBarExtraStyle(.menu)`** — a real `NSMenu`, which is the HIG-correct, keyboard-navigable, VoiceOver-correct option. Do **not** use `.window` style.

Icon: the template rendition of the mark (§2.2), 18 × 18. Three icon states:
- **Ready** — plain template.
- **Working** — template + a 3pt dot at the upper-right pulsing per M20. (The dot is part of the template image, drawn at runtime; still `isTemplate`.)
- **Needs setup** — template + a 3pt dot in `warning`, non-template overlay, static.

```
┌──────────────────────────────────────────────┐
│  Anthropic · Claude Sonnet 4.5               │  disabled header row, caption style
│ ──────────────────────────────────────────── │
│  Improve Clipboard Text            ⇧⌘Space   │
│  Improve Selection                           │  hidden unless Accessibility granted
│ ──────────────────────────────────────────── │
│  Provider                                  ▸ │  submenu
│ ──────────────────────────────────────────── │
│  Settings…                              ⌘,   │
│  Keyboard Shortcuts…                         │
│ ──────────────────────────────────────────── │
│  Quit WriteBetter                       ⌘Q   │
└──────────────────────────────────────────────┘

Provider ▸
┌──────────────────────────────────────────────┐
│ ✓ Anthropic                                  │
│     Claude Sonnet 4.5                      ▸ │  model submenu, checkmarked
│   OpenAI                                     │
│     Add API key…                             │  when unconfigured
│   Google Gemini                              │
│     Gemini 2.5 Pro                         ▸ │
└──────────────────────────────────────────────┘
```

Rules:
- The header row is `isEnabled = false` and shows the current provider + model. When nothing is configured it reads **"No provider configured"** in a `warning`-tinted attributed string, and the first action item becomes "Set up WriteBetter…".
- Unconfigured providers stay visible but their only child is "Add API key…", which opens Settings on that row.
- Never more than 9 items at the top level.
- Every item gets an `NSMenuItem.image` (16pt SF Symbol, template) so the menu scans visually: `sparkles`, `text.cursor`, `gearshape`, `keyboard`, `power`.

---

## 8. Provider switching UX

### 8.1 In the panel (fast switch)

Clicking C3 (the provider chip) opens an `NSMenu`-equivalent SwiftUI `Menu` anchored under the chip, `e2` elevation:

```
┌────────────────────────────────────┐
│  ● Anthropic                   ✓   │  ← configured, current
│      Claude Sonnet 4.5             │     caption, textTertiary
│  ● OpenAI                          │  ← configured
│      GPT-5.1                       │
│  ○ Google Gemini      Add key…     │  ← not configured, row dimmed to 0.55
│ ────────────────────────────────── │
│  Change model…                 ⌘M  │  → opens Settings on the current provider
│  Settings…                     ⌘,  │
└────────────────────────────────────┘
```

- Selecting a **configured** provider: `SettingsStore.selectedProvider = p` → M13 on the chip → **cancel any in-flight stream and immediately re-run the last request** with the new provider. The result canvas cross-fades (M14) rather than clearing to empty.
- Selecting an **unconfigured** provider: does **not** change `selectedProvider`. Opens Settings, Providers tab, that row expanded, key field focused. The panel stays open behind it.
- `⌘]` / `⌘[` cycle **only through configured providers**, in `AIProvider.allCases` order, wrapping. Same re-run behaviour. Disabled (and hidden from hints) when `configuredProviders.count < 2`.
- Model changes are **not** available inline — that's a Settings decision, and inline model menus make the chip unbounded. `⌘M` jumps there in one keystroke.

### 8.2 Case matrix

| Situation | Panel behaviour | Chip appearance |
|---|---|---|
| **No keys at all** | Panel opens directly in the **no-API-key** state with the Setup card. The hotkey still works — never show a bare error | Chip reads "Choose a provider ⌄" with a `warning` dot; clicking opens the same 3-up picker |
| **Exactly one key** | Normal. `⌘[`/`⌘]` disabled and not hinted | Normal chip; the menu shows the other two as "Add key…" |
| **Multiple keys** | Normal. `⌘[`/`⌘]` enabled and hinted in the menu | Normal chip |
| **Selected provider's key fails at request time** (`invalidKey`) | Error card + inline key field pre-focused. If another provider is configured, the footer's primary becomes `[ Try OpenAI ]` (the next configured provider) and the error card gains a secondary "Fix key" | Chip dot turns `danger` |
| **Selected provider rate-limited** | Countdown + auto-retry; if another provider is configured, offer `[ Switch to Gemini ]` as the secondary | Chip dot turns `warning` |
| **Key removed while the panel is open** | Panel transitions to the no-API-key state on the next run, keeping the last result visible above the setup card | Chip reverts to "Choose a provider" |

### 8.3 Persistence

The chosen provider and each provider's model persist via `SettingsStore` (per contract). A fast switch in the panel **does** change the persisted default — that is the expected behaviour for a keyboard-first tool (Raycast/Superhuman semantics). There is no "temporary" provider.

---

## 9. Onboarding / first run

### 9.1 Trigger

On `applicationDidFinishLaunching`, if `!SettingsStore.shared.isConfigured` **and** no key exists for any provider, present the **Welcome window** (not the Settings window): a single 560 × 620 window, `e3` elevation, `panel` radius, centred, activated with `NSApp.activate(ignoringOtherApps: true)`. It is dismissible (`esc`, or "Skip for now") and never reappears automatically after the first launch — the menu-bar header row becomes the persistent nudge instead.

### 9.2 The 60-second path

One scrolling page, four blocks, no wizard steps. Everything is visible at once so the user can see the finish line.

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│                        ◤                                 │  mark 64×64
│                    WriteBetter                           │  displayTitle
│        Select text anywhere. Press ⇧⌘Space.              │  subtitle
│                                                          │
│  ── 1 ──  Pick a provider ──────────────────────────────  │  sectionHeader
│  ┌────────────┐ ┌────────────┐ ┌────────────┐            │
│  │ ◆ Anthropic│ │ ◆ OpenAI   │ │ ◆ Gemini   │            │  h 72 tiles
│  │  Claude    │ │  GPT       │ │  Gemini    │            │  modelFamilyName
│  └────────────┘ └────────────┘ └────────────┘            │
│                                                          │
│  ── 2 ──  Paste your key ───────────────────────────────  │
│  ┌──────────────────────────────────┐ ┌──────────────┐   │
│  │ sk-ant-api03-…                   │ │  Continue    │   │  h 36
│  └──────────────────────────────────┘ └──────────────┘   │
│  Don't have one? Get a key ↗   ·   Stored in Keychain    │
│                                                          │
│  ── 3 ──  Try it ───────────────────────────────────────  │  disabled until verified
│  ┌──────────────────────────────────────────────────────┐│
│  │ "i think we should probly move the meeting, lmk"     ││  editable sample
│  └──────────────────────────────────────────────────────┘│
│                                   [  ✨ Improve this  ]  │
│                                                          │
│  ── Optional ───────────────────────────────────────────  │
│  ⚡ Replace text in place              [ Enable… ]        │
│  Needs Accessibility access. Everything else works       │
│  without it.                                             │
│                                                          │
│                              Skip for now   [  Done  ]   │
└──────────────────────────────────────────────────────────┘
```

Timing budget: pick a provider **3 s** → "Get a key ↗" opens `provider.consoleURL` in the browser **~20 s** → paste **4 s** → Continue runs `validateKey()` **~2 s** → "Improve this" streams the sample in place **~8 s** → Done. **≈ 37 s**, with headroom.

Details:
- Block 1 tiles: h **72**, r**12**, icon 20pt in `provider.accent`, `displayName` in `label`, `modelFamilyName` in `caption`. Selection = `accentMuted` + `accent` 1.5pt stroke.
- Block 2 unlocks the moment a provider is chosen and auto-focuses. Pressing `↩` = Continue. Continue shows an inline spinner ≤ 6 s, then `✓ Verified` in `success` (M15 checkmark) and **auto-scrolls** to block 3, or an inline `danger` caption with `recoverySuggestion`.
- Block 3 is a live, real streaming run inside the welcome window using the exact `C7` result canvas component — the user sees the product's core surface before they ever press the hotkey. Below it, once complete: "That's it. Anywhere on your Mac: copy text, press **⇧⌘Space**." with the keycaps rendered as C13.
- "Skip for now" closes the window; the menu-bar icon switches to the **Needs setup** variant.
- `Done` is enabled once a key is verified; it closes the window and shows a one-shot `NSUserNotification`-style in-menu-bar hint is **not** used — instead the menu-bar icon does a single M15-style pulse to teach the user where the app lives.

### 9.3 Accessibility permission — the optional ask

Non-negotiable rules:
1. **Never call `AXIsProcessTrustedWithOptions(prompt: true)` at launch.** Only ever from a direct user click on "Enable…" / "Grant…".
2. Always show the explainer **before** the system dialog, in our own words: title "Replace text in place", body "WriteBetter needs Accessibility access to read your current selection and paste the improved text back. Without it, copy with ⌘C first and paste with ⌘V after — everything else works exactly the same."
3. The app is fully functional without it: clipboard capture works, Copy works, only **auto-capture of selection** and **Replace in place** are gated.
4. Clicking "Enable…" calls `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`. Immediately also offer a secondary "Open System Settings" that deep-links `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (the research shows the system prompt is unreliable and the API returns stale values).
5. **Poll** `AXIsProcessTrusted()` every **1.0 s** while the Welcome window or the General settings tab is visible, capped at **120 s**, and flip the UI to granted the instant it returns true — no restart, no "quit and reopen" instruction.
6. If the app is ever sandboxed, `AXIsProcessTrusted()` always returns false and the prompt never appears. In that case, hide the Replace feature entirely rather than showing a button that can't work. (Agent D: WriteBetter must ship **unsandboxed** for Replace-in-place to exist.)
7. Granted state: the row collapses to a single `success` line "Replace in place is on" with a "Turn off" that just disables our use of it (we cannot revoke the TCC grant).

### 9.4 Empty/edge first-run cases

- Hotkey pressed with an empty clipboard and no key → panel opens showing the **Setup card**, not the empty-input card (fix the blocking problem first).
- Hotkey pressed with a key but empty clipboard → **empty-input** state.
- Hotkey pressed with >20,000 characters on the clipboard → truncate to the first 20,000, show a `warning` caption in the source strip: "Only the first 20,000 characters were used."

---

## 10. Accessibility checklist

Every item is a ship blocker.

**Contrast**
- [ ] All body text pairs meet **4.5:1**; all icons/borders/focus rings meet **3:1**. The tables in §3 are pre-verified — do not substitute colours.
- [ ] `textDisabled` is used **only** on disabled controls, never to convey information.
- [ ] Semantic colour is never the sole carrier of meaning — each is paired with a glyph (§3.4 rule 3).

**Reduce Transparency** (`@Environment(\.accessibilityReduceTransparency)`, OR the app's own "Reduce visual effects" toggle)
- [ ] Panel background: skip layers 1–3 of §5.4 entirely; fill with opaque `surface`.
- [ ] Raise `stroke` 0.09 → **0.16** and `strokeStrong` 0.18 → **0.30**.
- [ ] Drop the accent bloom, the rim gradient's animation (M7 → static), and the streaming glow.
- [ ] Skeleton bars go from α0.06 to α0.14.

**Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`)
- [ ] Every row of §6 uses its stated fallback. No transform animations at all — only opacity and cross-fades.
- [ ] The streaming caret stops blinking but **stays visible** (meaning is preserved as a static indicator, per Apple's guidance).
- [ ] The shimmer skeleton becomes static bars — still present, because it conveys "loading".

**Increase Contrast** (`NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`)
- [ ] Promote `stroke` → `strokeStrong` globally; every button gains a 1pt visible border; `textTertiary` → `textSecondary`.

**VoiceOver**
- [ ] Panel: `.accessibilityElement(children: .contain)` with `.accessibilityLabel("WriteBetter")`.
- [ ] Result canvas: label "Improved text", value = the current text, and **`.accessibilityAddTraits(.updatesFrequently)`** while streaming. Post `.announcement` on completion: "Done. 42 words."  Do **not** announce every token.
- [ ] Streaming badge: label "Streaming", not the raw glyph.
- [ ] Source strip: label "Original text", value = the text, hint "Double tap to expand".
- [ ] Provider chip: label "Provider", value "Anthropic, Claude Sonnet 4.5", hint "Opens the provider menu".
- [ ] Quick-action chips: label = `action.title`, hint = "Rewrites the text. Command \(index+1)".
- [ ] Every icon-only button has an `.accessibilityLabel` and a `.help()` tooltip with the same words: close, stop, regenerate, copy, replace, remove key, test key.
- [ ] Decorative elements (the mark glyph, the rim, skeleton bars) get `.accessibilityHidden(true)`.
- [ ] Key fields: `.accessibilityLabel("\(provider.displayName) API key")`; never read the key value aloud — use `SecureField`, which VoiceOver handles correctly.
- [ ] Menu-bar item: `NSStatusItem.button?.setAccessibilityLabel("WriteBetter")` and update it to include state ("WriteBetter, needs setup").

**Focus & keyboard**
- [ ] Focus order in the panel is exactly the `Tab` sequence in §7.1. Verify with **Full Keyboard Access** on (`⌃F7` / System Settings → Keyboard → Keyboard navigation).
- [ ] Focus ring: 2pt `accent`, drawn **outside** the control at +2pt offset, radius = control radius + 2, animated per M17. Never rely on the macOS default ring inside a borderless panel — it's easy to lose against glass.
- [ ] Nothing is reachable only by mouse. Every action in §7.1 has a key. Right-click-only actions (remove key) also have a visible button.
- [ ] `esc` always does something predictable and never destroys unsaved text without the partial result remaining copyable.
- [ ] The `?` shortcuts overlay lists every binding, so keyboard users can discover them without documentation.

**Text**
- [ ] Nothing below **10pt** anywhere.
- [ ] Result text is selectable (`.textSelection(.enabled)`) so a user can copy a fragment.
- [ ] All numeric readouts use `.monospacedDigit()`.
- [ ] No text is rendered as an image.

---

## 11. Implementation notes — SwiftUI on macOS 14

### 11.1 Effects: what to use where

| Need | macOS 14 (ship this) | macOS 26 (gate with `#available(macOS 26.0, *)`) |
|---|---|---|
| Panel background | `NSViewRepresentable` around `NSVisualEffectView` (`.hudWindow`, `.behindWindow`, `.active`, `isEmphasized`) + the 5-layer stack in §5.4 | `GlassEffectContainer { … .glassEffect(.regular, in: .rect(cornerRadius: 18)) }`, rim alphas halved |
| Nested radii | Literal values from §5.2 | `.rect(cornerRadius: .containerConcentric)` for flush-nested only |
| Primary button | Custom `ButtonStyle` per C15 | `.buttonStyle(.glassProminent)` **only if** it still yields ≥4.5:1 on the label; otherwise keep C15 |
| Chips | Custom style per C10 | `.buttonStyle(.glass)` — but **only** if the panel is the sole glass layer; if C10 chips sit on the panel's glass this violates "glass cannot sample glass", so **keep the custom style** and do not adopt `.glass` here |
| Numeric transitions | `.contentTransition(.numericText())` — available macOS 14 ✓ | same |
| Springs | `.spring(response:dampingFraction:)` and `.snappy` / `.bouncy` / `.smooth` — all macOS 14 ✓ | same |

Write **one** `GlassSurface: ViewModifier` that branches internally, and use it everywhere. Do not scatter `#available` checks through the views.

### 11.2 Known pitfalls, with the fix

1. **Shadow is clipped.** The current code sets `window.hasShadow = false` and then draws `.shadow(radius: 25, y: 8)` in SwiftUI. A borderless window clips its content to its bounds, so most of that shadow is cut off. **Fix:** set `window.hasShadow = true` and delete the outermost SwiftUI shadow — AppKit draws it outside the window frame. Keep only the inner rim/edge strokes in SwiftUI. (If you need the exact §5.3 `e3` shadow, the alternative is to enlarge the window by 44pt on each side and inset the content — do not do this unless the AppKit shadow is visibly wrong.)
2. **`panel.close()` silently fails.** If the panel is only `orderFront`ed and never made key, programmatic close does nothing. **Fix:** always `makeKeyAndOrderFront(nil)` when showing.
3. **Activation steals the source app's focus, breaking Replace.** `NSApp.activate(ignoringOtherApps: true)` makes WriteBetter frontmost, so a subsequent synthetic ⌘V lands in *our* panel. **Fix:** capture `NSWorkspace.shared.frontmostApplication` **before** showing the panel; on Replace, write to the pasteboard → `close()` → `previousApp.activate(options: [])` → wait **80 ms** → post the ⌘V `CGEvent` pair to `.cghidEventTap`. Restore the user's previous pasteboard contents after another 300 ms if you overwrote it.
4. **The key monitor is unscoped.** `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` in the current build fires for every window in the app, including Settings. **Fix:** compare `event.window === panelWindow` and return the event untouched otherwise. Prefer SwiftUI `.keyboardShortcut(_:modifiers:)` and `.onExitCommand` for everything expressible that way, and keep exactly one monitor for the rest.
5. **`.textSelection(.enabled)` swallows keys.** A selectable `Text` inside a `ScrollView` takes ⌘C and arrow keys. **Fix:** handle ⌘C in the monitor *before* forwarding (copy the selection if `NSPasteboard` reports one after letting the event through; simplest robust behaviour is: let ⌘C pass through when the result canvas has focus, and bind our "copy everything" to `↩` and `⇧↩` only).
6. **Streaming performance.** SwiftUI `Text` re-lays out the entire string on every mutation via CoreText, and this is measurably bad past ~50 lines. **Fix, all four:**
   - **Coalesce.** Buffer incoming chunks and flush to the `@Published` string at most every **50 ms** (20 fps). This is invisible to the user (200–600 ms to first token is the perceptual budget) and removes ~90% of the layout passes.
   - **One `Text`.** Render the whole result as a single `Text(improvedText)`. Never `ForEach` over tokens or lines — that is dramatically worse.
   - **No lazy container.** Do not put the result in a `LazyVStack`; it's one view.
   - **Cap the buffer** at **20,000 characters** for display (keep the full string for copying).
   - Auto-scroll with `ScrollViewReader.scrollTo(bottomAnchorID, anchor: .bottom)` on each flush, but **only when the user has not scrolled up** — track that with a `GeometryReader` in the scroll content and a `userDidScrollUp` flag reset by a "Jump to bottom" affordance.
7. **Token fade-in without re-animating everything.** Do not animate the whole `Text`. Render `Text(stable) + Text(justArrived).foregroundStyle(...)` as a concatenation and animate only the trailing run's opacity via a `@State` keyed on the flush index; or, simplest acceptable: apply the 140 ms fade to the last flushed batch only, using an `.id(flushIndex)` on an overlaid trailing `Text`. If this proves fiddly, **drop M8** — it is the lowest-value animation in the spec. Never trade streaming smoothness for it.
8. **Material in a borderless window.** SwiftUI's `.ultraThinMaterial` does not reliably sample behind a borderless `NSPanel`. Use the `NSVisualEffectView` representable. Also set the hosting view's layer: `wantsLayer = true`, `layer?.cornerRadius = 18`, `layer?.cornerCurve = .continuous`, `layer?.masksToBounds = true` — otherwise the material paints square corners under your rounded clip.
9. **`MenuBarExtra` style.** Use `.menuBarExtraStyle(.menu)`. The `.window` style loses keyboard navigation and VoiceOver menu semantics and does not look native.
10. **`LSUIElement`.** With no Dock icon (Agent D sets this), the `Settings` scene can open behind other apps. Always `NSApp.activate(ignoringOtherApps: true)` immediately before showing Settings or the Welcome window.
11. **Do not `.drawingGroup()`** anywhere in the panel — it breaks hit-testing (confirmed in the research).
12. **Do not animate materials or shadow radii.** Cross-fade two static states instead.
13. **`#Preview` per screen is a contract deliverable.** Every preview must exercise at least: `done`, `streaming`, `error`, and `no-API-key`, and must render without network access (inject a fake result string; never call `AIServiceFactory` from a preview).
14. **macOS 15 scroll stutter** (`_hitTestForEvent`, ~85% of frame time) is a system regression, not our bug — but it makes point 6's coalescing more important, not less. Do not add extra hit-testable overlays inside the result `ScrollView`.

### 11.3 SF Symbols used (all macOS 11+ unless noted; verify in SF Symbols 5)

`sparkles` · `wand.and.stars` · `text.cursor` · `doc.on.doc` · `doc.on.clipboard` · `checkmark` · `checkmark.circle.fill` · `checkmark.seal.fill` · `text.insert` (Replace) · `arrow.clockwise` (regenerate) · `stop.fill` · `arrow.up.circle.fill` · `xmark` · `chevron.down` · `chevron.up` · `chevron.left` · `chevron.right` · `gearshape` · `keyboard` · `key.fill` · `trash` · `arrow.up.right` · `exclamationmark.triangle.fill` · `exclamationmark.circle.fill` · `wifi.slash` · `hourglass` · `creditcard.fill` · `accessibility` · `bolt.fill` · `power`

Avoid `arrow.trianglehead.*` (macOS 15+) and `key.horizontal` (macOS 14 — fine for us, but `key.fill` is safer for the icon set as a whole).

Provider `iconSymbol` values are owned by Agent P. Recommended (all render at any weight): Anthropic → `sparkle`, OpenAI → `circle.hexagongrid.fill`, Gemini → `diamond.fill`. Agent U reads `provider.iconSymbol` and must not substitute.

---

## Appendix A — Token names Agent U should create

Agent U owns the SwiftUI `Theme`. Use exactly these names so Agent D's asset naming matches:

```
Theme.Color:   bgBase surface surfaceRaised surfaceSunken surfaceHover
               stroke strokeStrong strokeGlass
               textPrimary textSecondary textTertiary textDisabled
               accent accentText accentFill accentPressed accentMuted accentGradientEnd
               streaming success warning danger diffAddBg diffDelBg scrim
Theme.Gradient: signature  (accent → accentGradientEnd, topLeading → bottomTrailing)
Theme.Radius:  panel(18) window(12) card(12) control(9) chip(8) keycap(5)
Theme.Space:   xxs(2) xs(4) sm(6) md(8) lg(12) xl(16) xxl(20) h1(24) h2(32) h3(40)
Theme.Font:    displayTitle title subtitle sectionHeader result source body
               label button caption keycap mono badge
Theme.Motion:  instant quick standard enter celebrate  (+ the reduceMotion-aware wrapper)
Theme.Shadow:  e2 e3 glow
```

Every colour resolves through `Color(nsColor: NSColor(name:dynamicProvider:))` or an asset-catalog colour set so light/dark switch automatically. Do not branch on `colorScheme` in view code.

## Appendix B — Sources

1. https://ubos.tech/news/macos-tahoe-liquid-glass-ui-review-a-critical-look/
2. https://www.macrumors.com/2026/06/09/macos-golden-gate-liquid-glass/
3. https://cloudship.co.uk/blog/macos-tahoe-liquid-glass/
4. https://www.conor.fyi/writing/liquid-glass-reference
5. https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo
6. https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos
7. https://developer.apple.com/design/human-interface-guidelines/materials
8. https://developer.apple.com/documentation/appkit/nsvisualeffectview
9. https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/raycast/DESIGN.md
10. https://open-design.ai/plugins/design-system-raycast/
11. https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette
12. https://multi.app/blog/pushing-the-limits-nsstatusitem
13. https://designmd.cc/benchmarks/linear
14. https://opendesigner.io/design-systems/linear-app
15. https://help.superhuman.com/hc/en-us/articles/45191759067411-Speed-Up-With-Shortcuts
16. https://nickgray.net/superhuman/
17. https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/
18. https://macos-tahoe.com/blog/macos-tahoe-spotlight-quick-keys-complete-guide-2026/
19. https://developer.apple.com/videos/play/wwdc2024/10168/
20. https://www.createwithswift.com/exploring-apple-intelligence-writing-tools/
21. https://www.tuaw.com/2026/07/20/apple-tests-faster-siri-writing-tools-for-mac
22. https://support.grammarly.com/hc/en-us/articles/4412816078349-Grammarly-for-Windows-and-Grammarly-for-Mac-user-guide
23. https://www.warp.dev/blog/how-we-designed-themes-for-the-terminal-a-peek-into-our-process
24. https://docs.warp.dev/terminal/appearance/custom-themes/
25. https://www.hackdesign.org/toolkit/cleanshot-x/
26. https://blog.grusz.dev/arc-vs-dia-a-frontend-devs-take-on-two-browsers
27. https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
28. https://bjango.com/articles/designingmenubarextras/
29. https://zenn.dev/usagimaru/articles/b2a328775124ef?locale=en
30. https://developer.apple.com/design/human-interface-guidelines/motion
31. https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria/
32. https://apple-docs.everest.mt/docs/design/human-interface-guidelines/typography/
33. https://developer.apple.com/videos/play/wwdc2020/10175/
34. https://developer.apple.com/videos/play/wwdc2022/110381/
35. https://github.com/cvs-health/ios-swiftui-accessibility-techniques/blob/main/iOSswiftUIa11yTechniques/Documentation/ReduceTransparency.md
36. https://mobilea11y.com/guides/swiftui/swiftui-settings/
37. https://thefrontkit.com/blogs/what-is-streaming-ui-in-ai-applications
38. https://thepromptbench.com/ai-product-ux/streaming-ui-patterns-that-dont-break/
39. https://www.aiuxplayground.com/pattern/streaming/
40. https://www.setproduct.com/blog/ai-chat-interface-ui-design
41. https://aipatterns.substack.com/p/ai-patterns-for-document-editors
42. https://www.groovyweb.co/blog/ui-ux-design-trends-ai-apps-2026
43. https://github.com/git-cola/git-cola/pull/1542
44. https://medium.com/illumination/building-a-visual-diff-system-for-ai-edits-like-git-blame-for-llm-changes-171899c36971
45. https://fazm.ai/blog/swiftui-floating-panel
46. https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices
47. https://juniperphoton.substack.com/p/pro-to-swiftui-text-performance-issue
48. https://developer.apple.com/forums/thread/764264
49. https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html
50. https://gertrude.app/blog/macos-request-accessibility-control
51. https://nilcoalescing.com/blog/AnimationTimingInSwiftUI/
52. https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-spring-animation
53. https://www.w3.org/TR/WCAG22/
54. https://webaim.org/resources/contrastchecker/
55. https://www.brandcolorcode.com/anthropic
56. https://www.loftlyy.com/en/anthropic
57. https://colorarchive.org/brands/openai/
58. https://logos-world.net/google-gemini-logo/
59. https://en.wikipedia.org/wiki/Google_Gemini
