# Late Logging / Backdate Feature - Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                          │
│                  (lib/pages/total_money_page.dart)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐        ┌──────────────────┐             │
│  │  Quick Adjust    │        │  Edit Source     │             │
│  │    Dialog        │        │     Dialog       │             │
│  ├──────────────────┤        ├──────────────────┤             │
│  │ • Amount input   │        │ • Name input     │             │
│  │ • Categorize     │        │ • Amount input   │             │
│  │ [NEW] Backdate ✓│        │ [NEW] Backdate ✓│             │
│  │ [NEW] DatePicker│        │ [NEW] DatePicker│             │
│  └────────┬─────────┘        └────────┬─────────┘             │
│           │ _QuickAdjustmentDraft    │ result map            │
│           │ (with effectiveDate)     │ (with effectiveDate)  │
│           └────────┬─────────────────┘                         │
│                    │                                           │
└────────────────────┼───────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HOME PAGE CALLBACKS                          │
│                (lib/pages/home_page.dart)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  onQuickAdd() ──────┐                                          │
│  onQuickSubtract()─┼──> _adjustMoneySourceByName()            │
│  onEditSource()───┘    └─> _editMoneySource()                 │
│                            └─> _addMoneySource()              │
│                                                                 │
│  All methods now accept optional: DateTime? effectiveDate      │
│                                                                 │
└────────────────────┬───────────────────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │ Normal  │ │ Backdate│ │ Normal  │
    │ Add/Sub │ │Add/Sub  │ │ Edit    │
    │ (today) │ │ (hist.) │ │ (today) │
    └────┬────┘ └────┬────┘ └────┬────┘
         │           │           │
         └───────────┴───────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│              HISTORY DELTA APPLICATION LOGIC                    │
│              (lib/pages/home_page.dart)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Normal Path (effectiveDate == null):                          │
│  ┌─────────────────────────────────────────┐                  │
│  │ _addOrUpdateTodayHistory()              │                  │
│  │  - Update/create today's TotalMoneyDay  │                  │
│  │  - NO cascade (today is endpoint)       │                  │
│  └─────────────────────────────────────────┘                  │
│                                                                 │
│  Backdate Path (effectiveDate != null):                        │
│  ┌─────────────────────────────────────────┐                  │
│  │ _applyDeltaToHistory(effectiveDate,δ)   │                  │
│  │                                         │                  │
│  │ 1. Find/Create TotalMoneyDay for date   │                  │
│  │    - If new: use prior day's total + δ  │                  │
│  │    - If exists: add δ to it             │                  │
│  │                                         │                  │
│  │ 2. Cascade δ forward:                   │                  │
│  │    FOR each day > effectiveDate:        │                  │
│  │      total += δ                         │                  │
│  │                                         │                  │
│  │ 3. Return dayId for category attach     │                  │
│  └─────────────────────────────────────────┘                  │
│                                                                 │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PERSISTENCE LAYER                            │
│              (lib/store/money_storage.dart)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────┐                     │
│  │ updateMoneySource()                  │                     │
│  │  - Update money_sources table        │                     │
│  │  - Keep ID same                      │                     │
│  └──────────────────────────────────────┘                     │
│                                                                 │
│  ┌──────────────────────────────────────┐                     │
│  │ addMoneySourceChange()               │                     │
│  │  - Create changelog entry            │                     │
│  │  - createdAt = effectiveDate (key!)  │                     │
│  │  - Preserve exact timestamp          │                     │
│  └──────────────────────────────────────┘                     │
│                                                                 │
│  ┌──────────────────────────────────────┐                     │
│  │ updateTotalMoneyDay()                │                     │
│  │  - Update historical totals          │                     │
│  │  - Called multiple times (cascade)   │                     │
│  └──────────────────────────────────────┘                     │
│                                                                 │
│  ┌──────────────────────────────────────┐                     │
│  │ upsertDeltaEntry()                   │                     │
│  │  - Attach category to DAY (not date) │                     │
│  │  - Uses dayId from _applyDeltaTo...  │                     │
│  └──────────────────────────────────────┘                     │
│                                                                 │
└────────────────────┬───────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   SQLite DATABASE                               │
│                                                                 │
│  ┌──────────────────────┐  ┌──────────────────────┐           │
│  │  money_sources       │  │  money_source_       │           │
│  │  ═══════════════     │  │  changes             │           │
│  │  id (PK)             │  │  ═══════════════     │           │
│  │  name                │  │  id (PK)             │           │
│  │  amount     ◄────────┼──┤  sourceId (FK)       │           │
│  │              [sync]  │  │  deltaAmount ◄───┐  │           │
│  └──────────────────────┘  │  resultingAmount  │  │           │
│                            │  createdAt ◄─────┤──┤ [KEY]      │
│                            │  type             │  │ When user  │
│  ┌──────────────────────┐  │  note             │  │ specifies  │
│  │  total_money_days    │  └──────────────────┘  │ backdate   │
│  │  ═══════════════     │                        │           │
│  │  id (PK)             │                        │           │
│  │  date                │  ┌──────────────────────┐           │
│  │  totalAmount ◄───────┼──┤  tags                │           │
│  │     [cascade]        │  │  ═══════════════     │           │
│  │  note                │  │  id (PK)             │           │
│  └──────────────────────┘  │  name                │           │
│                            │  type (income/exp)   │           │
│                            └──────────────────────┘           │
│                                                                 │
│  ┌──────────────────────┐                                     │
│  │  total_money_day_    │                                     │
│  │  delta_entries       │                                     │
│  │  ═══════════════     │                                     │
│  │  id (PK)             │                                     │
│  │  dayId (FK) ◄────────┼─── Points to chosen date           │
│  │  tagId (FK)          │    (not today!)                     │
│  │  amount              │                                     │
│  │  autoBalanced        │                                     │
│  └──────────────────────┘                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow Example: Backdate $50 Expense 3 Days Ago

```
User Action:
  ↓
[Quick Subtract] $50 from "Cash" + Backdate to 3 days ago + Category: "Dining"
  ↓
UI Dialog returns:
  {
    amount: 50,
    categoryName: "Dining",
    categoryAmount: 50,
    effectiveDate: DateTime(2026, 5, 5)
  }
  ↓
HomePage._adjustMoneySourceByName(
  "Cash",
  -50,
  categoryName: "Dining",
  categoryAmount: 50,
  effectiveDate: DateTime(2026, 5, 5)
)
  ↓
  ├─ Update cash source amount: -50 (now = old - 50)
  ├─ Create MoneySourceChange record with createdAt = May 5
  │
  └─ Call _applyDeltaToHistory(May 5, -50)
      ├─ Find or create TotalMoneyDay for May 5
      ├─ Reduce May 5 total by 50
      │
      ├─ Find all days after May 5 (May 6, 7, 8, ...)
      │ └─ Reduce each by 50 (cascade)
      │
      └─ Return dayId for May 5
         │
         └─ Create delta entry:
              {
                dayId: 42,         [May 5's ID]
                tagId: 15,         ["Dining" tag]
                amount: 50,
                autoBalanced: false
              }
  ↓
Database Updated:
  • money_sources: Cash amount -= 50
  • money_source_changes: New entry, createdAt = May 5
  • total_money_days: 
    - May 5 total -= 50
    - May 6 total -= 50
    - May 7 total -= 50
    - May 8 total -= 50 (today)
  • tags: "Dining" (income/expense = expense)
  • total_money_day_delta_entries: Category for May 5
  ↓
UI Updates:
  • Cash source card shows new amount
  • History graph shows reduced May 5 onwards
  • Insights page shows Dining expense for May 5
```

## Key Design Principles

1. **Immutable Past Totals** – Once a day's total is set, changes backdate cascade forward, never rewrite history backwards.

2. **Effective Date Tracking** – `MoneySourceChange.createdAt` stores user-chosen date (not record creation time).

3. **Category-Day Binding** – Categories attach to the **effective day**, not today, enabling historical insights.

4. **Cascade Semantics** – A backdate to day N updates days N, N+1, N+2, ... but never modifies days < N.

5. **Intelligent Gap Filling** – If no prior history exists when backdating, intelligently estimates based on available data.

---

**Status**: ✅ Complete & Integrated  
**Compilation**: 0 errors introduced  
**Analysis**: 17 issues (pre-existing)

