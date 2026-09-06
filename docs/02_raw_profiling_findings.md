# Raw profiling findings (Phases 0–3)

Source: `RetailAnalytics.raw.online_retail`  
Script: `sql/02_raw_data_profiling.sql` (unchanged; read-only)  
Runner: `scripts/02_run_raw_profiling.py`  
Results: `outputs/profiling/phase_0_3/` (`manifest.json` records source file and timings)  
Run: 2026-08-30, **28 labelled statements completed, 0 failed**, ~16.8 seconds (section 3.3 ~15.9s).

Percentages use the **actual** table total **541,909** (not the expected-count literal except in 0.1). SQL `NULL` in JSON is `null`; empty `Description` is `""`.

This note **does not** finalize Silver rules, create Silver objects, or change Raw data.

**Still pending:** Phases 4–6 (adjustment vs product codes; duplicates and keys; time and geography) and Phases 7–9.

---

## How to read this note

- **Observed fact:** values from the saved JSON result sets.
- **Interpretation:** possible meaning; not a confirmed business rule.
- Negative quantity is **not** treated as a confirmed refund.
- Null `CustomerID` is **not** treated as a confirmed guest checkout.
- Outliers and duplicates are **not** proposed for deletion.
- `gross_sales_value` and `refund_value` are **provisional** until Phase 4.

---

## Phase 0 — Baseline

### Finding 0.1 — Load row-count assertion

| Field | Content |
| --- | --- |
| SQL section | 0.1 |
| Observed count and percentage | **541,909** actual rows; expected **541,909**; check **PASS**. Percentage N/A. |
| Example `raw_row_id`s | Not applicable. |
| Interpretation | The loaded table matches the Excel row count used at load time. |
| Potential impact | Percentages and value totals in later sections share this denominator. |
| Proposed treatment | Keep Raw as source of truth for Phases 4–6. No load re-run indicated. |

### Finding 0.2 — Invoice date range

| Field | Content |
| --- | --- |
| SQL section | 0.2 |
| Observed | Min **2010-12-01 08:26:00**, max **2011-12-09 12:50:00**. |
| Example `raw_row_id`s | Not applicable. |
| Interpretation | About 12 months of line timestamps, ending early in December 2011. |
| Potential impact | Sales and RFM windows should use this span. Partial first/last months are **not** measured (Phase 6 pending). |
| Proposed treatment | Do not trim dates until Phase 6. |

### Finding 0.3 — Distinct keys

| Field | Content |
| --- | --- |
| SQL section | 0.3 |
| Observed | Distinct invoices **25,900**; stock codes **3,958**; identified customers **4,372** (null `CustomerID` excluded by the query); countries **38**. |
| Example `raw_row_id`s | Not applicable. |
| Interpretation | Grain is not one row per invoice or per customer. Identified-customer count is not “all shoppers.” |
| Potential impact | RFM can use at most 4,372 keys; many lines have no customer key (see 1.2). |
| Proposed treatment | Keep line-level grain in Raw. |

### Finding 0.4 — Lines per invoice

| Field | Content |
| --- | --- |
| SQL section | 0.4 |
| Observed | Min **1**, max **1,114**, average **20.923127** lines per `InvoiceNo`. |
| Example `raw_row_id`s | Not applicable. |
| Interpretation | Typical invoices have many lines; some invoices are single-line. |
| Potential impact | Invoice-level metrics need aggregation; Raw is line-level. |
| Proposed treatment | Treat grain as invoice line unless later keys work (Phase 5) says otherwise. |

### Finding 0.5 — `CustomerID` leftover `.0`

| Field | Content |
| --- | --- |
| SQL section | 0.5 |
| Observed | **0** rows (0%). |
| Example `raw_row_id`s | None (no matches). |
| Interpretation | No Excel-style `.0` suffix on `CustomerID` in Raw. |
| Potential impact | Customer keys are not split by a `.0` artefact. |
| Proposed treatment | No conversion fix indicated. |

### Finding 0.6 — `InvoiceNo` / `StockCode` leftover `.0`

| Field | Content |
| --- | --- |
| SQL section | 0.6 |
| Observed | InvoiceNo `.0`: **0** (0%). StockCode `.0`: **0** (0%). |
| Example `raw_row_id`s | None. |
| Interpretation | Identifier strings do not show float leftovers under this pattern. |
| Potential impact | Low for key matching on this check. |
| Proposed treatment | No conversion fix indicated. |

### Finding 0.7 — Column metadata

| Field | Content |
| --- | --- |
| SQL section | 0.7 |
| Observed | 11 columns. Business columns: `InvoiceNo` nvarchar(20) NOT NULL; `StockCode` nvarchar(20) NOT NULL; `Description` nvarchar(255) NOT NULL; `Quantity` int NOT NULL; `InvoiceDate` datetime2 NOT NULL; `UnitPrice` decimal(18,4) NOT NULL; `CustomerID` nvarchar(20) **NULL**; `Country` nvarchar(100) NOT NULL. Also `raw_row_id` bigint NOT NULL, `source_file`, `loaded_at`. |
| Example `raw_row_id`s | Not applicable. |
| Interpretation | Schema allows SQL NULL only on `CustomerID` among business columns. Blank `Description` in data is therefore not SQL NULL (see 1.4–1.5). Cause of that representation is **not** proven by this catalog query. |
| Potential impact | Silver types should align with these declarations. |
| Proposed treatment | Use catalog when designing Silver; do not infer Excel-mapping history from nullability alone. |

---

## Phase 1 — Completeness

### Finding 1.1 — Completeness summary

| Field | Content |
| --- | --- |
| SQL section | 1.1 |
| Observed | Blank InvoiceNo/StockCode/Country: **0**. Null Quantity/InvoiceDate/UnitPrice: **0**. Blank Description: **1,454** (**0.2683%**). Null CustomerID: **135,080** (**24.9267%**). |
| Example `raw_row_id`s | See 1.3 and 1.5. |
| Interpretation | Material incompleteness is unidentified customers and blank descriptions. Required text keys and numeric timestamps are complete. |
| Potential impact | Customer analysis cannot cover about a quarter of lines. Product names missing on 1,454 lines. |
| Proposed treatment | Keep all rows in Raw. Candidate flags later; **not finalized.** |

### Finding 1.2 — Null `CustomerID`

| Field | Content |
| --- | --- |
| SQL section | 1.2 |
| Observed | **135,080** rows, **24.9267%**. |
| Example `raw_row_id`s | See 1.3. |
| Interpretation | **Fact:** no customer key. **Not a fact:** guest checkout. |
| Potential impact | RFM on identified customers ignores these lines; revenue can still include them. |
| Proposed treatment | Keep. Candidate “unidentified customer” flag — **not finalized.** Do not label as guest. |

### Finding 1.3 — Example unidentified-customer lines

| Field | Content |
| --- | --- |
| SQL section | 1.3 |
| Observed | TOP 10 `raw_row_id`: **10623, 11444, 11445, 11446, 11447, 11448, 11449, 11450, 11451, 11452**. |
| Interpretation | Earliest ordered examples include blank description and zero price (10623) and other UK lines with product text. `CustomerID` is JSON `null`. |
| Potential impact | Missing ID is not limited to one obvious invoice pattern in this sample. |
| Proposed treatment | Review with Phase 4 codes; no deletion. |

### Finding 1.4 — Blank `Description`

| Field | Content |
| --- | --- |
| SQL section | 1.4 |
| Observed | **1,454** rows, **0.2683%**. |
| Example `raw_row_id`s | See 1.5. |
| Interpretation | **Fact:** blank or whitespace-only description in SQL. Cause (Excel null vs empty vs NOT NULL column) is **not verified** here. |
| Potential impact | Description-based product analysis is incomplete on these lines; `StockCode` may still identify them. |
| Proposed treatment | Keep. Candidate missing-description flag — **not finalized.** |

### Finding 1.5 — Example blank-description lines

| Field | Content |
| --- | --- |
| SQL section | 1.5 |
| Observed | TOP 10 `raw_row_id`: **10623, 11971, 11972, 11973, 11988, 11989, 12025, 12026, 12027, 12407**. |
| Interpretation | Sample lines store `Description` as `""`. Several also have null `CustomerID` and zero `UnitPrice` in this ordered sample. |
| Potential impact | Overlap of blank description, unidentified customer, and zero price should be quantified later (not done in Phases 0–3 beyond examples). |
| Proposed treatment | Investigate overlap in Phase 4/7; do not drop. |

### Finding 1.6 — Blank InvoiceNo / StockCode / Country

| Field | Content |
| --- | --- |
| SQL section | 1.6 (count + examples) |
| Observed | **0** rows (0%). Example result set empty. |
| Example `raw_row_id`s | None. |
| Interpretation | No blank required text keys in Raw. |
| Potential impact | None for this issue. |
| Proposed treatment | No action. |

---

## Phase 2 — Transaction behaviour

### Finding 2.1 — `InvoiceNo` like `C%`

| Field | Content |
| --- | --- |
| SQL section | 2.1 |
| Observed | **9,288** rows, **1.7139%**. |
| Example `raw_row_id`s | See 2.5. |
| Interpretation | **Fact:** cancellation-style prefix. **Not a fact:** every line is a completed refund. |
| Potential impact | Including/excluding these lines changes net value and RFM if treated as activity. |
| Proposed treatment | Keep. Candidate prefix flag — **not finalized.** |

### Finding 2.2 — Negative `Quantity`

| Field | Content |
| --- | --- |
| SQL section | 2.2 |
| Observed | **10,624** rows, **1.9605%**. |
| Example `raw_row_id`s | 2.5 (C-prefix) and 2.7 (no C-prefix). |
| Interpretation | **Fact:** quantity &lt; 0. **Not a fact:** confirmed refund. Count is **higher** than C-prefix rows (see 2.4). |
| Potential impact | Signed qty changes line value. |
| Proposed treatment | Keep. Do not equate to refund until codes (Phase 4) and 2.4/2.7 are used in a decision list. |

### Finding 2.3 — Zero `Quantity`

| Field | Content |
| --- | --- |
| SQL section | 2.3 |
| Observed | **0** rows (0%). |
| Example `raw_row_id`s | None. |
| Interpretation | No zero-quantity lines. |
| Potential impact | None. |
| Proposed treatment | No action. |

### Finding 2.4 — Cross-tab: `C%` vs quantity sign

| Field | Content |
| --- | --- |
| SQL section | 2.4 |
| Observed | Not C, negative qty: **1,336** (**0.2465%**). Not C, positive qty: **531,285** (**98.0395%**). C-prefix, negative qty: **9,288** (**1.7139%**). No C-prefix with zero qty; no C-prefix with positive qty in this grid. |
| Example `raw_row_id`s | Not in 2.4. |
| Interpretation | Every `C%` line in this extract has negative quantity. Negative quantity **also** occurs **without** `C` (1,336 lines). |
| Potential impact | A flag that uses only `C%` misses 1,336 negative-qty lines; a flag that uses only qty &lt; 0 includes both groups. |
| Proposed treatment | Define cancellation vs adjustment using both prefix and qty **after** Phase 4. Do not delete either group. |

### Finding 2.5 — Example `C%` lines

| Field | Content |
| --- | --- |
| SQL section | 2.5 |
| Observed | TOP 10 `raw_row_id`: **10142, 10155, 10236, 10237, 10238, 10239, 10240, 10241, 10242, 10940**. |
| Interpretation | Sample of earliest C-prefix lines; use with Phase 4 for product vs adjustment text. |
| Potential impact | Examples only; not a rate. |
| Proposed treatment | Review in Phase 4/7. |

### Finding 2.6 — `C%` with non-negative quantity

| Field | Content |
| --- | --- |
| SQL section | 2.6 |
| Observed | **0** rows (0%). Example result set empty. |
| Example `raw_row_id`s | None. |
| Interpretation | No mismatch of C-prefix with qty ≥ 0 in this extract (agrees with 2.4). |
| Potential impact | None for this mismatch type. |
| Proposed treatment | No action on this mismatch. |

### Finding 2.7 — Negative quantity without `C%`

| Field | Content |
| --- | --- |
| SQL section | 2.7 |
| Observed | **1,336** rows, **0.2465%**. TOP 10 `raw_row_id`: **12407, 14348, 17189, 17190, 17191, 17193, 17194, 17196, 17197, 17198**. |
| Interpretation | Negative quantity is **not** only C-invoices. These are **not** classified as refunds. |
| Potential impact | Revenue and “returns” rules that key only on `C` will miss this group. |
| Proposed treatment | Keep; inspect stock codes/descriptions in Phase 4 (e.g. whether they are adjustments). **Not decided.** |

### Finding 2.8 — Example zero-quantity lines

| Field | Content |
| --- | --- |
| SQL section | 2.8 |
| Observed | Empty result (consistent with 2.3 = 0). |
| Example `raw_row_id`s | None. |
| Interpretation | No examples to review. |
| Potential impact | None. |
| Proposed treatment | No action. |

---

## Phase 3 — Price and value

Provisional measures **exclude** classification of postage/manual/fee/adjustment codes (Phase 4 pending).

### Finding 3.1 — `UnitPrice` sign

| Field | Content |
| --- | --- |
| SQL section | 3.1 |
| Observed | Negative price: **2** (**0.0004%**). Zero price: **2,515** (**0.4641%**). Positive price: **539,392** (**99.5355%**). |
| Example `raw_row_id`s | 3.6, 3.7. |
| Interpretation | Almost all lines have positive unit price; zero price is uncommon; negative price is rare (two lines). |
| Potential impact | Zero-price lines add quantity/mix but not provisional sales value. Negative price is a large absolute value (see 3.2 / 3.7). |
| Proposed treatment | Keep all; do not drop zeros or the two negative-price lines without Phase 4 context. |

### Finding 3.2 — Provisional value measures

| Field | Content |
| --- | --- |
| SQL section | 3.2 |
| Observed | `gross_sales_value` **10,666,684.5440**; `refund_value` **-896,812.4900**; `refund_amount_abs` **896,812.4900**; `net_line_value` **9,747,747.9340**; zero-price rows **2,515** (**0.4641%**), value **0**; negative-price rows **2** (**0.0004%**), value **-22,124.1200**. |
| Example `raw_row_id`s | Not in 3.2. |
| Interpretation | **Fact:** arithmetic under the script definitions. **Not a fact:** refund_value is confirmed refunds. Adjustment lines (e.g. Manual, AMAZON FEE, Adjust bad debt in 3.5/3.7) are still inside these totals. |
| Potential impact | Reporting these as “sales” or “refunds” would be premature and can misstate revenue. |
| Proposed treatment | Quote only as provisional. Recalculate after Phase 4. Do not store in Raw. **Not decided for Silver.** |

### Finding 3.3 — Quantity and price percentiles

| Field | Content |
| --- | --- |
| SQL section | 3.3 |
| Observed | Quantity min **-80,995**, max **80,995**; p01 **-2**, p05 **1**, p50 **3**, p95 **29**, p99 **100**. UnitPrice min **-11,062.0600**, max **38,970.0000**; p01 **0.19**, p05 **0.42**, p50 **2.08**, p95 **9.95**, p99 **18.00**. |
| Example `raw_row_id`s | 3.4, 3.5. |
| Interpretation | Typical qty and price are small; tails are extreme. Min/max qty are equal in magnitude (see 3.4 pair). |
| Potential impact | Tails can dominate monetary RFM and net value if unflagged. |
| Proposed treatment | Do **not** delete outliers; investigate 3.4/3.5 examples (possible genuine bulk plus matching C-line, and high-price Manual/fees). |

### Finding 3.4 — Extreme `|Quantity|`

| Field | Content |
| --- | --- |
| SQL section | 3.4 |
| Observed | TOP 10 `raw_row_id`: **550422** (qty 80995), **550423** (qty -80995, invoice C581484), **71620**, **71625**, **512123**, **235530**, **235531**, **14288**, **235529**, **84615**. |
| Interpretation | Largest positive and negative quantities are paired paper-craft lines on the same customer (16446) minutes apart — consistent with a sale and a C-prefix reversal, **not proven** as the only process. Other extremes need Phase 4. |
| Potential impact | A single pair moves line value by ±168,469.60. |
| Proposed treatment | Keep; do not drop. Document as outlier pair for later rules. **Not decided.** |

### Finding 3.5 — Extreme `|UnitPrice|`

| Field | Content |
| --- | --- |
| SQL section | 3.5 |
| Observed | TOP 10 `raw_row_id`: **232682** (StockCode `M`, Manual, 38970), **534603** (`AMAZONFEE`), **53703**, **53704**, **25017**, **25018**, **26357**, **26233**, **534602**, **309983**. |
| Interpretation | Highest absolute prices include **Manual** and **AMAZON FEE**, not typical shelf SKUs. This supports treating 3.2 totals as provisional. Alphanumeric format alone was **not** used to classify them (Phase 4 still required). |
| Potential impact | These lines can dominate “refund” and net value. |
| Proposed treatment | Classify in Phase 4 by **code and description**, not format. Do not delete. |

### Finding 3.6 — Zero `UnitPrice`

| Field | Content |
| --- | --- |
| SQL section | 3.6 |
| Observed | **2,515** rows, **0.4641%**. TOP 10 `raw_row_id`: **10623, 11971, 11972, 11973, 11988, 11989, 12025, 12026, 12027, 12407**. |
| Interpretation | Zero-priced lines exist; sample overlaps blank description / unidentified customer examples. |
| Potential impact | Quantity mix without provisional sales value. |
| Proposed treatment | Keep; candidate zero-price flag later. **Not finalized.** |

### Finding 3.7 — Negative `UnitPrice`

| Field | Content |
| --- | --- |
| SQL section | 3.7 |
| Observed | **2** rows, **0.0004%**. `raw_row_id`: **309984**, **309985**. InvoiceNo `A563186` / `A563187`, StockCode `B`, Description `Adjust bad debt`, Quantity 1, UnitPrice -11062.06, `CustomerID` null. |
| Interpretation | **Fact:** negative unit price on two “Adjust bad debt” lines. **Not a fact:** these are customer refunds (`refund_value` definition used qty &lt; 0 and price &gt; 0, so these sit in `negative_price_value` instead). |
| Potential impact | **-22,124.12** in `negative_price_value` and `net_line_value`. |
| Proposed treatment | Keep; treat as adjustment-candidate in Phase 4. **Not decided.** |

---

## Cross-cutting (not measured)

| Topic | Status |
| --- | --- |
| Duplicate groups / extra duplicate rows | Phase 5 — pending |
| Multiple `InvoiceDate` per `InvoiceNo` | Later — pending |
| Partial first/last calendar months | Phase 6 — pending |
| Non-product / adjustment `StockCode` | Phase 4 — pending |
| Silver rules | Phases 8–9 — **not finalized** |

---

## Result files

Directory: `outputs/profiling/phase_0_3/`  
Index: `manifest.json`  
One JSON file per statement (and `_set2.json` where a section ran two result sets: 1.6, 2.6, 2.7, 3.6, 3.7).
