# Raw profiling findings (Phases 4–6)

Source: `RetailAnalytics.raw.online_retail`  
SQL: `sql/02_raw_data_profiling.sql` (not modified in this run)  
Runner: `scripts/02_run_raw_profiling.py` (Phases 4–6 only)  
Results: `outputs/profiling/phase_4_6/`  
Manifest: `outputs/profiling/phase_4_6/manifest.json`  
Run: 2026-08-30, **20 statements completed, 0 failed**, ~11.5 seconds.

Phases 0–3 were not rerun. This note does **not** finalize Silver rules or change Raw data.

**How to read:** **Fact** = query output. **Interpretation** = hypothesis. **Proposal** = candidate rule, not approved. Values are **provisional** (same LineValue buckets as Phase 3). Negative quantity is **not** a confirmed refund.

---

## Execution status

All Phase 4–6 sections completed. Multi-result sections: `5.9.json` + `5.9_set2.json`, `5.10.json` + `5.10_set2.json`, `5.11.json` + `5.11_set2.json`. Example sets for 5.9 and 5.10 are empty because the count queries returned 0 invoices.

---

## Phase 4 — Product, service and adjustment codes

### Seed candidates (4.1, `4.1.json`)

**Facts** (line counts and % of 541,909; value buckets provisional):

| StockCode | Proposed label (SQL only) | Lines | % rows | Distinct invoices | Gross | Signed neg-qty value | Neg. price value | Net |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| POST | proposed_postage | 1,256 | 0.232% | 1,254 | 78,101.88 | −11,871.24 | 0 | 66,230.64 |
| DOT | proposed_postage | 710 | 0.131% | 710 | 206,248.77 | −3.29 | 0 | 206,245.48 |
| M | proposed_manual | 572 | 0.106% | 518 | 78,112.82 | −146,784.46 | 0 | −68,671.64 |
| D | proposed_discount | 77 | 0.014% | 65 | 0 | −5,696.22 | 0 | −5,696.22 |
| BANK CHARGES | proposed_bank_charges | 37 | 0.007% | 36 | 165.00 | −7,340.64 | 0 | −7,175.64 |
| AMAZONFEE | proposed_amazon_fee | 34 | 0.006% | 34 | 13,761.09 | −235,281.59 | 0 | −221,520.50 |
| CRUK | proposed_commission_or_fee | 16 | 0.003% | 16 | 0 | −7,933.43 | 0 | −7,933.43 |
| B | proposed_bad_debt_adjustment | 3 | 0.001% | 3 | 11,062.06 | 0 | −22,124.12 | −11,062.06 |

POST/DOT `sample_description_min` includes `""` (blank description on some postage lines). M/D/CRUK/AMAZONFEE/BANK CHARGES/B descriptions are consistent Manual / Discount / CRUK Commission / AMAZON FEE / Bank Charges / Adjust bad debt.

**Interpretation:** These codes are **candidates** for service/adjustment treatment. DOT’s net (~206k) is large relative to line count because of high unit prices, not because the code “looks alphanumeric.” AMAZONFEE and M dominate **signed negative-quantity** value among the seed set; that is **not** proof they are customer refunds.

**Proposal (not approved):** Flag this seed list as `is_service_or_adjustment` (or split postage vs fee vs manual vs discount vs bad debt) after you accept the labels. Do not classify other letter-containing SKUs the same way without 4.3 review.

**Unresolved:** Whether DOTCOM POSTAGE should sit with POST in one “postage” flag; whether blank-description POST/DOT lines are the same process.

### Sign mix on seed codes (4.2, `4.2.json`)

**Facts:** 17 sign combinations. Examples: AMAZONFEE 32 neg-qty / pos-price and 2 pos-qty / pos-price; B 2 pos-qty / **neg-price** and 1 pos-qty / pos-price; D 77 all neg-qty / pos-price; CRUK 16 all neg-qty / pos-price.

**Interpretation:** Seed codes are not a single transaction type. D and CRUK are entirely negative-qty at positive price in this extract; AMAZONFEE and BANK CHARGES mix signs.

### Keyword discovery (4.3, `4.3.json`) — not full-StockCode populations

**Facts:** **144** StockCodes matched description keywords (postage/manual/discount/amazon/adjust/bank/dotcom/cruk/gift/carriage/samples) **and** were **not** in the seed list. Top net by this **keyword-row** measure include gift **products** (e.g. `23007` SPACEBOY BABY GIFT SET, 188 lines, net 7,657.00) and `C2` CARRIAGE (143 lines, 143 invoices, net 6,986.00). `S` SAMPLES: 63 lines, net −3,049.39.

**Interpretation / caution:** 4.3 counts **rows whose Description matched keywords**, not necessarily every row of that StockCode. **GIFT matches legitimate products.** `C2` / `S` are stronger service/sample candidates than gift-tag SKUs.

**Proposal:** Do **not** treat the 144 codes as a non-product list. Review `C2` and `S` (and similar) as extra candidates; ignore gift-set SKUs unless a separate product taxonomy says otherwise.

**Unresolved:** PADS was not in 4.3 output (no keyword hit under the current patterns). Full-code volumes for `C2`/`S` vs keyword-only rows were not separately queried.

### Examples per seed code (4.4, `4.4.json`)

**Facts:** 73 example rows (TOP 10 per StockCode; B has only 3 lines). AMAZONFEE examples start at `raw_row_id` **24515** (C537600, qty −1). B: **309983** (A563185, qty 1, unit price **+11,062.06**), **309984**, **309985** (unit price **−11,062.06**). Full lists are in `4.4.json`.

### Net-value identity (4.5, `4.5.json`)

**Facts:**

- gross_sales_value = **10,666,684.5440**
- signed_refund_value = **−896,812.4900**
- negative_price_value = **−22,124.1200**
- net_line_value = **9,747,747.9340**
- reconstructed_net_line_value = **9,747,747.9340**
- **identity_difference = 0.0000**

**Interpretation:** The Phase 3 bucket identity holds on the full table. Zero-price lines contribute 0 to all three addends.

### Negative price vs Adjust bad debt (4.6, `4.6.json`)

**Facts:** Negative-price lines: **2**, value **−22,124.1200**. Description `Adjust bad debt`: **3** lines, value **−11,062.0600**. Difference (neg-price minus adjust-bad-debt net): **−11,062.0600**.

**Interpretation / caution:** These are **different populations**. The two negative-price rows (`309984`, `309985`) sum to −22,124.12. The third Adjust bad debt row (`309983`) has **positive** unit price +11,062.06, so the three-line net is −11,062.06. A difference is **not** an error; it is expected from including the offsetting positive-price B line in 4.6’s description filter.

**Proposal:** If Silver flags “bad debt,” decide whether to include all three B lines or only negative-price lines.

---

## Phase 5 — Duplicates and invoice consistency

### Collation (5.1, `5.1.json`)

**Facts:** InvoiceNo, StockCode, Description, CustomerID, Country use **Chinese_PRC_CI_AS** (same as the database). Exact duplicate grouping is **case-insensitive, accent-sensitive** under this collation, not byte-for-byte.

### Exact duplicates — eight business columns (5.2–5.3)

**Facts (5.2, `5.2.json`):** **4,879** groups; **10,147** rows in those groups (**1.872%** of 541,909); **5,268** extra rows beyond the first (**0.972%**).

**Facts (5.3, `5.3.json`):** Largest group: InvoiceNo **555524**, StockCode **22698**, 20 identical lines, `raw_row_id`s **223177,223178,223184,223192–223209** (see file). Next: same invoice **22697**, 12 rows (`223176,223179–223191`). Other examples: **572861/22775** (8 ids starting 429849), **538514/21756** (6 ids starting 36489).

**Interpretation:** Repeats look like repeated line entry on the same invoice/timestamp, not load duplication of the whole file. Extra rows (~5.3k) would inflate quantity and value if summed as independent demand.

**Proposal:** Do **not** delete. Candidate Silver flag `is_exact_duplicate_extra` on extras only, or keep all lines and document over-counting — **your decision**.

### Five-column potential duplicates (5.4–5.5)

**Facts (5.4, `5.4.json`):** **4,882** groups; **10,153** rows; **5,271** extras (**1.874%** of rows in groups). This is **not** the same as 5.2 (3 extra groups / 6 extra rows vs exact dups).

**Facts (5.5, `5.5.json`):** Top groups match 5.3’s largest invoices (`555524` 22698/22697) with `distinct_descriptions` = 1 and `distinct_invoice_dates` = 1 in those examples.

**Interpretation:** Almost all five-column repeats are also exact eight-column duplicates. The small gap (4882 vs 4879 groups) means a few repeats differ on Description, InvoiceDate, or Country.

**Proposal:** Treat 5.4 as a **sensitivity check**, not a second delete rule.

### Description drift (5.6–5.7)

**Facts (5.6, `5.6.json`):** **1,320** StockCodes have more than one distinct Description (**33.35%** of distinct StockCodes). Distinct-code % must not be summed with other %s as a row share.

**Facts (5.7, `5.7.json`):** Highest drift examples: **23084** (8 descriptions, 1,067 lines, max text `website fixed`); **20713** (8, 684 lines, `wrongly marked. 23343 in box`); **85175**, **21830**; **23343** includes `wrongly coded 20713`. Min description is often `""`.

**Interpretation:** Drift includes blank text and warehouse notes, not only marketing copy changes.

**Proposal:** Prefer StockCode as product key; do not require a single Description in Silver without a chosen “canonical text” rule.

### Invoice CustomerID / Country / Date (5.8–5.11)

**Facts:**

- **5.8** (`5.8.json`): invoices with **>1 non-null** CustomerID: **0**. `line_count` here counts **only non-null CustomerID rows** in the inner query; with 0 invoices this is 0.
- **5.9** (`5.9.json`, `5.9_set2.json`): mixed null and non-null CustomerID on one invoice: **0** invoices; example set empty.
- **5.10** (`5.10.json`, `5.10_set2.json`): multiple Country: **0**.
- **5.11** (`5.11.json`): **43** invoices (**0.166%** of 25,900 invoices), **3,347** lines, have **>1 InvoiceDate**. Examples (`5.11_set2.json`): **574076** (2 timestamps one minute apart, 416 lines, ids from 445481); **567183** (399 lines, 15:32–15:33); **544186**, **549524** similarly one-minute splits.

**Interpretation:** Customer and country are consistent per invoice in this extract. Multiple InvoiceDate values look like **checkout clock tick / split batch**, not multi-day invoices, in the largest examples.

**Proposal:** Keep one invoice key; optionally store min/max time. Do not split 574076 into two customers.

---

## Phase 6 — Time and geography

### Monthly coverage (6.1, `6.1.json`)

**Facts:** 13 calendar months. **Line counts sum to 541,909.** Monthly **gross / signed neg-qty / neg-price / net** sum to **10,666,684.5440 / −896,812.4900 / −22,124.1200 / 9,747,747.9340**, matching 4.5 / Phase 3.

December 2010: 42,481 lines, dates 2010-12-01 08:26 through **2010-12-23** (not flagged incomplete by 6.1).  
**2011-12:** 25,525 lines (**4.71%**), min 2011-12-01 08:12, max **2011-12-09 12:50**, flag **`potentially_incomplete_final_month`**. Signed neg-qty value in that month **−205,124.67** (large vs other months; includes the ±80,995 pair from Phase 3). Negative-price value **−22,124.12** sits entirely in **2011-08**. Peak lines: **2011-11** 84,711 (15.63%).

**Interpretation:** Flagging Dec 2011 as potentially incomplete follows the **last observed timestamp**, not “no rows on 31 Dec.” Dec 2010 ending on the 23rd is **observed**, not automatically incomplete. Do **not** add monthly identified-customer counts to get 4,372.

**Proposal:** For monthly sales charts, annotate Dec 2011 as partial. For RFM, decide whether to use last date 2011-12-09 as snapshot date.

### Countries (6.2, `6.2.json`; 6.3, `6.3.json`)

**Facts:** **38** countries. **Line counts sum to 541,909.** Value buckets sum to the same full-table totals as 4.5. UK: **495,478** lines (**91.43%**), **23,494** invoices, **3,950** identified customers, net **8,187,806.36** (**84.00%** of net). Non-UK: **46,431** lines (**8.57%**), **2,406** invoices, **422** identified customers, net **1,559,941.57** (**16.00%**). Next nets: Netherlands 284,661.54 (2,371 lines); EIRE 263,276.82 (8,196 lines); Germany 221,698.21 (9,495 lines); France 197,403.90 (8,557 lines).

**Interpretation:** UK dominates **lines** more than **net value share** (91% vs 84%). Non-UK punch above weight on net. Do **not** add UK + non-UK identified customers (3,950+422) and call it global distinct (4,372): customers can appear in only one group here, but the method is still not a substitute for `COUNT(DISTINCT CustomerID)` on the full table (Phase 0.3 = 4,372; 3950+422 = 4,372 happens to match in this split).

**Proposal:** Keep Country as an attribute; optional UK flag. Values still provisional (fees/postage still inside).

---

## Validation summary

| Check | Result |
| --- | --- |
| 6.1 line_count sum | **541,909** |
| 6.2 line_count sum | **541,909** |
| 6.3 line_count sum | **541,909** |
| 6.1 / 6.2 value buckets vs 4.5 | **Match** (gross, signed neg-qty, neg-price, net) |
| 4.5 identity_difference | **0.0000** |
| Distinct customers/invoices across months or countries | **Not** used as a global distinct total |

---

## Decisions needed before Silver design

1. **Seed codes (4.1):** Accept proposed postage / manual / discount / fee / bad-debt flags, or a subset? Include **C2** (carriage) and **S** (samples) from 4.3, **excluding** GIFT product SKUs?
2. **B / bad debt:** Flag all three Adjust bad debt lines, or only the two negative-price lines?
3. **Duplicates:** Keep all 10,147 grouped rows, or flag 5,268 extras without deleting?
4. **Description drift:** Canonical Description vs StockCode-only product key?
5. **RFM / sales windows:** Treat Dec 2011 as partial; snapshot date = 2011-12-09?
6. **Unidentified customers and C% / other negative qty** remain from Phases 0–3 (not re-decided here).

## Targeted follow-up (only if useful)

- Full-StockCode (not keyword-only) counts for `C2` and `S`.
- How much of 4.1 net sits inside Dec 2011 AMAZONFEE / M (optional; not required for identity).
- Whether duplicate extras are concentrated on a few invoices (5.3 already shows 555524).

Phases **7–9** (decision list and Silver scope) are still not implemented.
