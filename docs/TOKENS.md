# Keepwell design tokens (v1, Oct 3 2026)
For App Builder: put these in an Asset Catalog as Color Sets (Any / Dark), then reference them as `Color("BrandTeal")` and so on. Where a system color works, use it, so Dynamic Type, contrast and accessibility settings behave natively.

## Colors
| Token (Color Set name) | Light | Dark | Use |
|---|---|---|---|
| `BrandTeal` | `#0E8C7F` | `#2CC4B2` | primary tint, CTA fill, selected plan border, links (set it as the app's AccentColor) |
| `BrandTealText` | `#0B7268` | `#2CC4B2` | small teal text: links (Restore / Terms / Privacy), inline actions. 5.2:1 on light Background, 8.8:1 on dark |
| `OnBrand` | `#FFFFFF` | `#06231F` | text and icons drawn on BrandTeal |
| `BrandTint` | `#E3F4F1` | `#15302C` | icon chips, subtle highlights |
| `Background` | `#F6F3EE` | `#0E1013` | screen background (warm off-white / near-black) |
| `Surface` | `#FFFFFF` | `#1C1F23` | cards, plan rows, grouped lists |
| `TextPrimary` | `#111418` | `#F2F2F2` | titles, body (or use `.primary`) |
| `TextSecondary` | `#5B6470` | `#9AA3AE` | captions, fine print (or use `.secondary`) |
| `Separator` | `#E3E0DA` | `#2A2E33` | hairlines, close-button fill, unselected radio |
| `Keep` | `#1F9D5C` | `#3DD68C` | swipe-right overlay and "Keep" stamp |
| `Delete` | `#E5574A` | `#FF7A6B` | swipe-left overlay and "Delete" stamp (never as a full-screen alarm red) |
| `Placeholder` (design-only) | text `#B45309` on `#FEF3C7` | text `#FBBF24` on `#3A2E0B` | the "PLACEHOLDER PRICES" tag in mockups only; **do not ship** |

App icon palette (fixed, same in light and dark): gradient `#17A493` → `#0B5E57` (135°), card `#FFF8EE`, photo sky `#FFD9A8` → `#FFB37A`, hills `#0E8C7F`.

Contrast: TextSecondary on Background is 5.4:1 in light and 7.5:1 in dark. BrandTeal (`#0E8C7F`) on the light Background is only 3.7:1, so small teal text such as links uses `BrandTealText`. OnBrand on BrandTeal is about 4.1:1 in light, which passes AA only for large or bold text, so the 17 pt semibold CTA label is fine. If the label shrinks, darken the light-mode CTA to `#0B7268`.

## Typography
SF Pro, the system font only. No bundled fonts. Use text styles so Dynamic Type works. (The mockups render with Inter as a stand-in because SF Pro isn't available on Linux.)
| Role | SwiftUI | Mockup equivalent |
|---|---|---|
| Paywall / screen title | `.largeTitle.weight(.bold)` (~30–34 pt) | 28–30 pt bold, tracking -0.4 |
| Section label | `.footnote.weight(.semibold)`, `.textCase(.uppercase)` | 13 pt |
| Row title | `.body.weight(.semibold)` (17 pt) | 16 pt semibold |
| Row detail | `.footnote` / `.subheadline` | 13 pt |
| CTA label | `.headline` (17 pt semibold) | 17 pt |
| Fine print | `.caption2` (11 pt) | 11 pt |
| Space-freed counter | `.system(.largeTitle, design: .rounded).weight(.bold)` with `.monospacedDigit()` | n/a |
Use `.rounded` only for numbers (the freed-space counter, swipe count). Everything else is default SF Pro.

## Corner radii (use `RoundedRectangle(cornerRadius:style: .continuous)`)
| Element | Radius (pt) |
|---|---|
| Swipe photo card | 28 |
| Grouped card / benefits list | 16 |
| Plan row | 16 |
| Primary button (height 54) | 14 |
| Icon chip (34×34) | 9 |
| Thumbnails in duplicate groups | 10 |
| Tag / badge | 6 |
| Close button | circle, 30 pt diameter |
| App icon | none in the asset. Ship the square 1024 PNG and let iOS mask it. |

## Spacing and layout
- Screen horizontal padding 24 pt. Card inner padding 16 pt. Gap between plan rows 8 pt.
- Hit targets ≥ 44 pt. The close button's visual circle is 30 pt, but pad its tappable frame to 44.
- Selected plan: 2 pt BrandTeal border plus a filled radio. Unselected: no border. **The default selection is Yearly, never a weekly trial.** Lifetime is always visible without scrolling.

## Motion
- Swipe card: `.spring(response: 0.35, dampingFraction: 0.8)`. Rotation follows drag, up to ±12°. The Keep/Delete overlay opacity follows drag distance.
- Respect Reduce Motion: cross-fade instead of fly-off.
