# Power BI Guide - Loan Default Risk Dashboard

Power BI files (`.pbix`) are binary, so they can't be generated as code. This guide gives you everything
needed to build the dashboard in about 60-90 minutes, then save the `.pbix` into this folder.

## 1. Load the data

Power BI Desktop -> **Get Data -> Text/CSV**, and load from `outputs/powerbi/`:

| File | Table name | Use |
|---|---|---|
| `loans_scored.csv` | `loans` | Main fact table (one row per loan, includes model score and risk band) |
| `risk_deciles.csv` | `deciles` | Predicted vs actual default by decile |
| `model_drivers.csv` | `drivers` | Odds ratios for the "What drives default" chart |
| `policy_cutoffs.csv` | `policy` | Result of rejecting N riskiest deciles |

In **Power Query** (Transform Data): check column types - `issue_date` = Date, `is_default` = Whole number,
`int_rate`, `dti`, `profit`, `pd_score`, `expected_profit` = Decimal.

Create a **Date table** (Modeling -> New table):
```DAX
DimDate = CALENDAR(DATE(2015,1,1), DATE(2018,12,31))
```
Relate `DimDate[Date]` -> `loans[issue_date]` (many-to-one... i.e. one DimDate row to many loans).
Mark `DimDate` as a date table. Add columns `Year = YEAR([Date])`, `Quarter = "Q" & QUARTER([Date])`.

## 2. DAX measures (create a separate `_Measures` table to hold them)

```DAX
Total Loans         = COUNTROWS(loans)
Total Disbursed     = SUM(loans[loan_amount])
Defaults            = SUM(loans[is_default])
Default Rate        = DIVIDE([Defaults], [Total Loans])
Avg Interest Rate   = AVERAGE(loans[int_rate]) / 100
Net Profit          = SUM(loans[profit])
Profit per Loan     = DIVIDE([Net Profit], [Total Loans])
Defaulted Amount    = CALCULATE(SUM(loans[loan_amount]), loans[is_default] = 1)
Loss Rate (by $)    = DIVIDE([Defaulted Amount], [Total Disbursed])

Portfolio Default Rate = CALCULATE([Default Rate], ALL(loans))
Gap vs Portfolio (pp)  = ([Default Rate] - [Portfolio Default Rate]) * 100

Default Rate PY =
    CALCULATE([Default Rate], DATEADD(DimDate[Date], -1, YEAR))

High-Risk Share =
    DIVIDE(CALCULATE([Total Loans], loans[risk_band] IN {"High", "Very High"}), [Total Loans])

-- Policy: decline loans the model expects to lose money on
Loans Declined (EV rule)  = CALCULATE([Total Loans], loans[expected_profit] < 0)
Profit After EV Rule      = CALCULATE([Net Profit], loans[expected_profit] >= 0)
Profit Change (EV rule)   = [Profit After EV Rule] - [Net Profit]
Default Rate After EV Rule= CALCULATE([Default Rate], loans[expected_profit] >= 0)
```

**What-if parameter (interactive policy slider):** Modeling -> New parameter -> Name `Deciles Declined`,
Whole number, min 0, max 5, increment 1, default 1, add slicer. Then:
```DAX
Profit After Decile Rule =
    CALCULATE([Net Profit], loans[risk_decile] <= 10 - 'Deciles Declined'[Deciles Declined Value])
Profit Change (Decile Rule) = [Profit After Decile Rule] - [Net Profit]
```

**Sort order fix:** `dti_band`, `util_band` sort alphabetically by default. Add helper columns in Power Query
(e.g. `dti_sort` 1-4) and use *Sort by column*.

## 3. Page layout

### Page 1 - Portfolio Overview
- **KPI cards (top row):** Total Loans, Total Disbursed, Default Rate, Avg Interest Rate, Net Profit
- **Line chart:** Default Rate by `DimDate[Year]` and `[Quarter]` (axis = Year-Quarter hierarchy)
- **Column chart:** Total Disbursed by Year
- **Donut:** Total Loans by `purpose`
- **Slicers:** Year, Term (`term_months`), Home ownership

### Page 2 - Risk Segmentation
- **Column chart:** Default Rate by `grade` + **line** Profit per Loan on secondary axis (the "profit peaks at D" insight)
- **Column chart:** Default Rate by `dti_band`
- **Bar chart:** Default Rate by `purpose` (sorted descending)
- **Filled map or bar:** Default Rate by `state`
- **Matrix heatmap:** rows = `grade`, columns = `term_months`, values = Default Rate (conditional formatting: colour scale)
- **Tooltip page** (optional): show Total Loans & Profit per Loan on hover

### Page 3 - Model & Recommendations
- **Clustered column:** `deciles[avg_pd]` vs `deciles[actual_default_rate]` by `risk_decile` (shows the model is calibrated)
- **Bar chart:** `drivers[odds_ratio]` by `feature` (reference line at 1.0)
- **Cards:** Loans Declined (EV rule), Default Rate After EV Rule, Profit Change (EV rule)
- **What-if slicer + card:** `Deciles Declined` -> Profit Change (Decile Rule)
- **Text box - Recommendations** (3 bullets):
  1. Decline or reprice loans with negative expected profit (about 6-7% of applicants): default rate drops from ~15.4% to ~13.6% and profit rises ~4%.
  2. Don't tighten blindly: declining beyond the riskiest decile destroys profit because good loans pay interest.
  3. Treat small-business and medical loans plus DTI above 30 as enhanced-review segments.

## 4. Design tips that make it look professional
- One colour theme (navy `#2F5D8C` + red `#C0392B` for risk). Same font everywhere.
- Align visuals to a grid; give every visual a clear title ("Default rate by grade", not "Chart 1").
- Turn off clutter: gridlines, redundant legends, axis titles that repeat the chart title.
- Add **bookmarks + navigation buttons** between pages.
- Keep each page to ~6-8 visuals.

## 5. Publish / share
- **Best for resume:** export each page to PNG (File -> Export -> PDF, or screenshot) and put them in `powerbi/screenshots/`, then reference them in the README.
- **Power BI Service:** Home -> Publish (free work/school account needed). "Publish to web" gives a public link but requires admin permission on many tenants. If it's not available, screenshots + a 60-second screen-recording (Loom/YouTube unlisted) work well.
- Save the file as `powerbi/Loan_Default_Risk.pbix` and commit it (it's small).
