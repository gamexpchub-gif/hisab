# GAME X PC HUB — Ultimate Accounting & Business Management Roadmap

ERP + POS + Inventory + Accounting + GST + CRM + Finance — Android APK first, then Desktop/Web.

Status: ✅ done in v1 · 🔜 next · 📋 planned

> সবচেয়ে গুরুত্বপূর্ণ নিয়ম: আগে Accounting Engine ও Inventory Engine নির্ভুল, তারপর AI/Automation। হিসাব ভুল হলে সুন্দর Dashboard-এর কোনো মূল্য নেই।

---

## Phase 1 — Foundation ✅
- ✅ Local SQLite database, integer-paise money, schema versioning
- ✅ Chart of accounts (Assets, Liabilities, Equity, Income, COGS, Expenses, GST In/Out)
- ✅ Business settings (name, tagline, owner, phone, address, GSTIN)
- ✅ Audit log of every action (feeds Recent Activity)
- ✅ Premium UI: white + purple/blue, glass cards, soft shadows, 3D illustrations, bottom nav, FAB
- 🔜 PIN / fingerprint app lock
- 📋 Users & roles (Super Admin, Owner, Manager, Accountant, Cashier, Staff, Auditor) with per-module permissions (view/create/edit/delete/approve/export, hide cost price & profit)

## Phase 2 — Core business ✅
- ✅ Products: brand, category, SKU/barcode, HSN, GST %, sale price, avg cost, condition, low-stock level
- ✅ Customers & suppliers with opening balance, credit limit, GSTIN
- ✅ Sales invoice: multi-item, GST, discount, cash / credit / partial / UPI / bank, walk-in
- ✅ Purchase bill: supplier bill no., GST input, partial payment
- ✅ Invoice view + copy for WhatsApp
- 🔜 PDF invoice (A4 + 58/80 mm thermal), share PDF to WhatsApp, Bluetooth thermal printing
- 🔜 Estimate / Quotation, Proforma, Sales Order, Delivery Challan
- 🔜 Barcode scanner (camera) for product & IMEI
- 📋 Custom invoice prefix / series, terms & conditions, signature, logo on invoice
- 📋 Split payment (part cash + part UPI) on one invoice

## Phase 3 — Inventory & devices 🔜
- ✅ Weighted-average costing, stock never negative, stock value report
- ✅ IMEI / serial captured per sale & purchase line, IMEI search
- 🔜 Device register: one row per unit (IMEI 1 & 2, serial, RAM/ROM, colour, battery health, box/accessories, test report) — **IMEI unique, no duplicates**
- 🔜 Sales return / purchase return (stock + accounting reversal), exchange, refund, store credit
- 📋 Stock adjustment (damaged / defective / lost), physical stock audit
- 📋 Warehouses / rack location, stock transfer, stock ageing, dead stock, fast/slow movers
- 📋 Warranty tracking & reminders, repair history

## Phase 4 — Accounting engine ✅ (core)
- ✅ Automatic double-entry from sales, purchases, receipts, payments, expenses, transfers, opening balances
- ✅ Debit = credit check on every entry; duplicate-post protection
- ✅ COGS posted at sale time (profit = sales − cost of goods sold − expenses)
- ✅ Customer ledger, supplier ledger, any account ledger with opening/closing, Day Book
- 🔜 Manual Journal / Contra / Debit Note / Credit Note vouchers
- 🔜 Reversal entries for corrections (posted entries are never edited or deleted)
- 📋 Owner capital & drawings screens, depreciation, bad debts / write-off, prepaid & outstanding expenses
- 📋 Financial-year closing, period lock, cost centres

## Phase 5 — Finance & GST 🔜
- ✅ Expenses with custom categories; cash/bank/UPI accounts; transfers; receipts & payments
- ✅ GST summary (output GST, input credit, net payable)
- 🔜 CGST/SGST vs IGST split by place of supply, B2B / B2C, HSN summary
- 🔜 GSTR-1 & GSTR-3B export (Excel/JSON) — always verify before filing
- 🔜 EMI / Khata: installment schedule, down payment, collections, overdue list, finance-partner settlement tracked separately
- 📋 Bank reconciliation, daily cash closing & cash difference report, cheque tracking
- 📋 Recurring expenses, expense budget vs actual
- 📋 E-invoice / E-way bill (when applicable, via authorised GSP)

## Phase 6 — Reports ✅ (core)
- ✅ Dashboard: today's net & gross profit, receivable, payable, cash/bank balances, stock value, 6-month sales vs purchase chart, low stock, highest dues, top products, recent invoices
- ✅ Profit & Loss, Balance Sheet (with balance check), Trial Balance, Day Book, GST summary
- 🔜 Cash flow statement, outstanding ageing (0-30-60-90 days)
- 🔜 Product-wise & customer-wise profit, payment-method breakdown
- 📋 Excel / PDF export of every report, year-on-year comparison, sales targets

## Phase 7 — CRM, HR & multi-branch 📋
- 📋 Customer groups (VIP / wholesale / regular), follow-ups, birthday & warranty reminders
- 📋 WhatsApp payment reminders & statements (WhatsApp Business API)
- 📋 Employees, attendance, salary, advance, commission, cashier-wise collection
- 📋 Multiple branches with branch-wise stock, cash, P&L and consolidated reports

## Phase 8 — Backup, sync & security 🔜
- 🔜 One-tap backup / restore of the database file (share to Google Drive / WhatsApp)
- 🔜 Automatic daily backup with backup history
- 📋 Excel import (products, customers, opening balances) with error report
- 📋 Cloud sync (Flask/PostgreSQL backend) so phone + laptop share the same books
- 📋 Desktop/Web version for full accounting & administration
- 📋 Login history, device management, sensitive-action confirmation

## Phase 9 — AI & automation 📋
- 📋 "এই মাসে কত লাভ হয়েছে?" — natural-language questions over your own books
- 📋 Reorder suggestions & low-stock prediction
- 📋 Purchase bill OCR (photo → purchase entry)
- 📋 Daily / weekly business summary notification
- 📋 Duplicate invoice & suspicious transaction alerts

---

## Testing checklist (run before every release)
- Sale reduces stock; purchase increases stock; return restores it
- Trial balance debits = credits; balance sheet Assets = Liabilities + Equity
- Customer due & supplier payable match their ledgers
- GST totals match invoices
- Cash & bank balances match ledgers
- Same document can't be posted twice
- Backup → restore gives identical reports

`test/books_test.dart` already automates the double-entry, stock, and duplicate-post checks, and CI runs it on every push.
