# Late Logging Feature - Quick Reference

## What Users Can Do Now

### ✅ Log a transaction to a past date
- Add/subtract amount from a money source
- Choose a historical date (up to 3 years ago)
- History totals auto-update with cascade effect

### ✅ Edit a source amount retroactively
- Edit the money source amount
- Choose when that edit should take effect
- All subsequent day totals update automatically

### ✅ Categorize backdated transactions
- When adding/subtracting, optionally categorize
- Category entries attached to the chosen date
- Insights page reflects categorization for that date

## How It Works

**Backdate Mechanism**:
```
User logs $50 expense 3 days ago
        ↓
System finds/creates that day's total
        ↓
Adds $50 to that day
        ↓
Cascades $50 forward to today and beyond
        ↓
History graph shows updated totals
```

## UI Features Added

| Feature | Location | Trigger |
|---------|----------|---------|
| Backdate checkbox | Quick add/subtract dialog | After entering amount |
| Backdate checkbox | Edit money source dialog | After entering new amount |
| Date picker | Both dialogs | When backdate checkbox checked |
| Date constraints | Date picker | Min: 3 years ago, Max: Today |

## Code Locations

- **Core logic**: `lib/pages/home_page.dart` (~74 lines)
  - `_applyDeltaToHistory()` – main backdate implementation
  - Updated methods: `_addMoneySource()`, `_editMoneySource()`, `_adjustMoneySourceByName()`

- **UI**: `lib/pages/total_money/total_money_page.dart` (~60 lines)
  - Quick adjustment dialog with date picker
  - Edit money source dialog with date picker
  - Updated callback signatures

## Testing

```bash
# Verify no errors introduced
flutter analyze --no-fatal-infos

# Should show only pre-existing deprecation warnings (no new errors)
```

**Current state**: 17 issues (all pre-existing deprecated API warnings)

## Example Scenario

**Situation**: User forgot to log a $150 restaurant expense from last week.

**Steps**:
1. Open Money Tracker app
2. Tap on their "Cash" money source
3. Tap "Subtract amount"
4. Enter 150
5. Check "Log this change to a different date"
6. Select date from last week
7. Optionally categorize as "Dining"
8. Tap Save

**Result**:
- Cash balance decreases by 150 today
- Last week's day total decreases by 150
- Every day after last week increases by 150 (cascade)
- "Dining" category shows in insights for that date

---

**Status**: Ready for user testing ✅

