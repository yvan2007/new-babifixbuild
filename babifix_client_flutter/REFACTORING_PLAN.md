# REFACTORING PLAN - main.dart babifix_client_flutter

## Current state
- **File:** `lib/main.dart`
- **Lines:** 6291
- **Classes:** 16

---

## PLAN BY STEP

### STEP 1: Shared Widgets (small components)
Create `lib/shared/widgets/` with:

| Widget | Lines | Target file |
|--------|-------|------------|
| `_VerticalDivider` | 5986-6000 (15) | `lib/shared/widgets/vertical_divider.dart` |
| `_MiniStatChip` | 5888-5943 (56) | `lib/shared/widgets/mini_stat_chip.dart` |
| `_LegalLink` | 5944-5985 (42) | `lib/shared/widgets/legal_link.dart` |
| `_HelpRow` | 5843-5887 (45) | `lib/shared/widgets/help_row.dart` |
| `_MmLogoChip` | 5784-5842 (59) | `lib/shared/widgets/mm_logo_chip.dart` |
| `_HomeQuickChip` | 5721-5783 (63) | `lib/shared/widgets/home_quick_chip.dart` |
| `_SectionLabel` | 6088-6113 (26) | `lib/shared/widgets/section_label.dart` |

### STEP 2: Premium Components
| Widget | Lines | Target file |
|--------|-------|------------|
| `_PremiumActionTile` | 6001-6087 (87) | `lib/shared/widgets/premium_action_tile.dart` |

### STEP 3: Splash Screen
| Widget | Lines | Target file |
|--------|-------|------------|
| `_SplashScreen` | 5630-5636 (7) | `lib/features/splash/splash_screen.dart` |
| `_SplashScreenState` | 5637-5720 (84) | `lib/features/splash/splash_screen.dart` |

### STEP 4: Settings Sheet
| Widget | Lines | Target file |
|--------|-------|------------|
| `_SettingsSheet` | 6114-6134 (21) | `lib/features/settings/settings_sheet.dart` |
| `_SettingsSheetState` | 6135-6291 (157) | `lib/features/settings/settings_sheet.dart` |

### STEP 5: Home Screen (LARGEST)
| Widget | Lines | Target file |
|--------|-------|------------|
| `ClientHomePage` | 267-282 (16) | `lib/features/home/client_home_page.dart` |
| `_ClientHomePageState` | 283-5629 (5347) | `lib/features/home/client_home_page.dart` |

### STEP 6: App Shell
| Widget | Lines | Target file |
|--------|-------|------------|
| `BabifixClientApp` | 99-105 (7) | `lib/app.dart` |
| `_BabifixClientAppState` | 106-266 (161) | `lib/app.dart` |

### STEP 7: Final cleanup
- Remove extracted classes from `main.dart`
- Update imports

---

## CREATION ORDER (safety)

1. ALWAYS run `flutter analyze` after each file
2. IF error -> fix immediately BEFORE continuing
3. Ideal order: Small -> Large (detect problems early)

---

## COMMANDS TO EXECUTE

```bash
# Check state
cd babifix_client_flutter
flutter analyze

# Create folders
mkdir -p lib/shared/widgets
mkdir -p lib/features/splash
mkdir -p lib/features/settings
mkdir -p lib/features/home
```

---

## EXTRACTION RULES

For each file to extract:

1. Copy exact lines (start -> end)
2. Add necessary imports at top
3. Check dependencies (_ClientHomePageState depends on many things)
4. Test with `flutter analyze`

---

## RISKS & SOLUTIONS

| Risk | Solution |
|------|----------|
| Missing import | Add imports at top of file |
| Circular dependency | Create small ones first |
| Missing reference | Keep in main.dart temporarily |

---

## EXPECTED FINAL RESULT

```
lib/
|-- main.dart           (~150 lines after cleanup)
|-- app.dart          (168 lines - App shell)
+-- features/
    +-- home/
    |   +-- client_home_page.dart  (5363 lines)
    +-- splash/
    |   +-- splash_screen.dart     (91 lines)
    +-- settings/
        +-- settings_sheet.dart  (178 lines)
+-- shared/
    +-- widgets/                   (9 files)
```

**Total lines:** ~6291 -> ~6300 (slight increase due to imports)
**Goal:** Better organization, not line reduction