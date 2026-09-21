import fs from "node:fs/promises";
import { Workbook, SpreadsheetFile } from "@oai/artifact-tool";

const sourceDir = "/Users/prajeethavijayan/Desktop/Prajeetha/projects - prac/coffee sales/walkin_case_study_analytics_consultant";
const outputDir = "/Users/prajeethavijayan/Documents/Coffee shop data/outputs/clean_dataset";

async function readCsv(name) {
  const text = await fs.readFile(`${sourceDir}/${name}`, "utf8");
  const wb = await Workbook.fromCSV(text, { sheetName: "Data" });
  const values = wb.worksheets.getItem("Data").getUsedRange(true).values;
  const headers = values[0].map(String);
  return values.slice(1).map(row => Object.fromEntries(headers.map((h, j) => [h, row[j]])));
}

const customersRaw = await readCsv("customer_level_data.csv");
const transactionsRaw = await readCsv("transaction_level_data.csv");
const itemsRaw = await readCsv("item_level_data.csv");

function parseDateTime(v) {
  if (!v) return null;
  const d = new Date(String(v).replace(" ", "T") + "Z");
  return Number.isNaN(d.getTime()) ? null : d;
}
function parseDate(v) {
  if (!v || v === "0000-00-00") return null;
  const d = new Date(`${v}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}
function yearsBetween(a, b) {
  if (!a || !b || a > b) return null;
  let years = b.getUTCFullYear() - a.getUTCFullYear();
  if (b.getUTCMonth() < a.getUTCMonth() || (b.getUTCMonth() === a.getUTCMonth() && b.getUTCDate() < a.getUTCDate())) years--;
  return years >= 10 && years <= 100 ? years : null;
}
function offerType(v) {
  const s = String(v || "").toUpperCase();
  if (!s || s === "NA") return "NO_OFFER";
  if (s.includes("FREE")) return "FREE_ITEM";
  if (s.includes("%") || s.includes("CASHBACK")) return "PERCENT_CASHBACK";
  if (s.includes("LOYALTY POINT")) return "FIXED_POINTS";
  return "OTHER_OFFER";
}

const customers = customersRaw.map(r => {
  const install = parseDateTime(r.app_install_time);
  const dob = parseDate(r.date_of_birth);
  const age = yearsBetween(dob, install);
  const genderRaw = String(r.gender || "").trim().toUpperCase();
  const maritalRaw = String(r.marital_status || "").trim().toUpperCase();
  return [
    Number(r.customer_number), install,
    genderRaw === "NA" ? null : genderRaw,
    maritalRaw === "NA" ? null : maritalRaw,
    dob, age,
    r.referral_as_source_of_app_install === "Installed_through_referral",
    !dob || age === null,
    genderRaw === "NA",
    maritalRaw === "NA",
  ];
});

const transactions = transactionsRaw.map(r => {
  const t = parseDateTime(r.transaction_time);
  const store = String(r.store_name || "").trim().toUpperCase();
  const m = store.match(/^(.*?) STORE (\d+)$/);
  const sale = Number(r.sale_amount_including_loyalty_points_used);
  const points = Number(r.loyalty_points_used_by_customer);
  const offer = String(r.offer_used_by_customer_to_earn_loyalty_points || "").trim();
  return [
    Number(r.transaction_number), Number(r.customer_number), t,
    t ? new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate())) : null,
    t ? t.getUTCHours() : null,
    t ? ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][t.getUTCDay()] : null,
    store, m ? m[1] : null, m ? Number(m[2]) : null,
    sale, points, sale - points,
    offer === "NA" ? null : offer,
    offer !== "NA", offerType(offer),
  ];
});

const items = itemsRaw.map(r => {
  const raw = String(r.item_name || "").trim().toUpperCase();
  const unknown = !raw || raw === "#N/A" || raw === "MISCELLANEOUS";
  return [
    Number(r.transaction_number), Number(r.customer_number),
    unknown ? null : raw, raw, Number(r.sale_amount), unknown,
  ];
});

const wb = Workbook.create();
const readme = wb.worksheets.add("README");
const cs = wb.worksheets.add("Customers");
const ts = wb.worksheets.add("Transactions");
const is = wb.worksheets.add("Items");
const qs = wb.worksheets.add("Data Quality");

readme.getRange("A1:B1").values = [["Coffee Shop Clean Analytical Dataset", ""]];
readme.getRange("A3:B11").values = [
  ["Purpose", "Clean, analysis-ready tables preserving customer, transaction, and item grains."],
  ["Customers grain", "One row per customer_number."],
  ["Transactions grain", "One row per transaction_number. Use this sheet for revenue and transaction metrics."],
  ["Items grain", "One row per purchased item record. Join to Transactions by transaction_number for basket analysis."],
  ["Revenue warning", "Do not sum transaction sale amount after joining it to Items; multi-item transactions will duplicate revenue."],
  ["Missing values", "Source values such as NA, #N/A, and invalid dates are represented as blank cleaned fields plus explicit flags."],
  ["Currency", "Amounts are Indian Rupees; one loyalty point equals one Rupee."],
  ["Time coverage", "2018-06-01 through 2018-09-30."],
  ["Source scope", "Synthetic case-study data containing app-based purchases only."],
];

const customerHeaders = ["customer_number","app_install_time","gender_clean","marital_status_clean","birth_date_clean","age_at_install","installed_through_referral","invalid_birth_date_flag","missing_gender_flag","missing_marital_status_flag"];
const transactionHeaders = ["transaction_number","customer_number","transaction_time","transaction_date","transaction_hour","day_of_week","store_name_clean","store_city_clean","store_number","gross_sale_amount","loyalty_points_used","cash_or_digital_paid","offer_name_clean","offer_used_flag","offer_type"];
const itemHeaders = ["transaction_number","customer_number","item_name_clean","item_name_raw","item_sale_amount","unknown_item_flag"];

function writeTable(sheet, headers, rows, tableName) {
  sheet.getRangeByIndexes(0, 0, 1, headers.length).values = [headers];
  sheet.getRangeByIndexes(1, 0, rows.length, headers.length).values = rows;
  const range = sheet.getRangeByIndexes(0, 0, rows.length + 1, headers.length);
  const table = sheet.tables.add(range, true, tableName);
  table.style = "TableStyleMedium2";
  sheet.freezePanes.freezeRows(1);
  sheet.showGridLines = false;
  range.format.autofitColumns();
  range.format.rowHeight = 18;
}

writeTable(cs, customerHeaders, customers, "CustomersTable");
writeTable(ts, transactionHeaders, transactions, "TransactionsTable");
writeTable(is, itemHeaders, items, "ItemsTable");

cs.getRange(`B2:B${customers.length + 1}`).format.numberFormat = "yyyy-mm-dd hh:mm:ss";
cs.getRange(`E2:E${customers.length + 1}`).format.numberFormat = "yyyy-mm-dd";
ts.getRange(`C2:C${transactions.length + 1}`).format.numberFormat = "yyyy-mm-dd hh:mm:ss";
ts.getRange(`D2:D${transactions.length + 1}`).format.numberFormat = "yyyy-mm-dd";
ts.getRange(`J2:L${transactions.length + 1}`).format.numberFormat = '₹#,##0.00';
is.getRange(`E2:E${items.length + 1}`).format.numberFormat = '₹#,##0.00';

const quality = [
  ["Check", "Count", "Interpretation"],
  ["Registered customers", customers.length, "Rows in cleaned Customers table"],
  ["Transactions", transactions.length, "Rows in cleaned Transactions table"],
  ["Item records", items.length, "Rows in cleaned Items table"],
  ["Invalid or implausible birth date", customers.filter(r => r[7]).length, "Blank birth_date_clean and age_at_install"],
  ["Missing gender", customers.filter(r => r[8]).length, "gender_clean is blank"],
  ["Missing marital status", customers.filter(r => r[9]).length, "marital_status_clean is blank"],
  ["Unknown or miscellaneous item", items.filter(r => r[5]).length, "item_name_clean is blank; raw label retained"],
  ["Transactions without offer", transactions.filter(r => !r[13]).length, "offer_type is NO_OFFER"],
  ["Negative cash/digital paid", transactions.filter(r => r[11] < 0).length, "Should be zero"],
];
qs.getRangeByIndexes(0, 0, quality.length, 3).values = quality;
const qt = qs.tables.add(qs.getRangeByIndexes(0, 0, quality.length, 3), true, "QualityTable");
qt.style = "TableStyleMedium2";
qs.freezePanes.freezeRows(1);
qs.showGridLines = false;
qs.getRange("A1:C10").format.autofitColumns();

readme.showGridLines = false;
readme.getRange("A1:B1").format = { fill: "#5B382A", font: { bold: true, color: "#FFFFFF", size: 16 }, horizontalAlignment: "left" };
readme.getRange("A3:A11").format = { fill: "#E8D8C9", font: { bold: true, color: "#3B241B" } };
readme.getRange("A3:B11").format.borders = { preset: "inside", style: "thin", color: "#D8C5B6" };
readme.getRange("A3:B11").format.wrapText = true;
readme.getRange("A3:A11").format.columnWidth = 25;
readme.getRange("B3:B11").format.columnWidth = 90;
readme.getRange("A3:B11").format.autofitRows();

await fs.mkdir(outputDir, { recursive: true });
const outputPath = `${outputDir}/coffee_shop_clean_analytical_dataset.xlsx`;
const out = await SpreadsheetFile.exportXlsx(wb);
await out.save(outputPath);

const inspect = await wb.inspect({ kind: "table", range: "Data Quality!A1:C10", include: "values,formulas", tableMaxRows: 12, tableMaxCols: 4 });
console.log(inspect.ndjson);
const errors = await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 30 }, summary: "formula error scan" });
console.log(errors.ndjson);
for (const name of ["README", "Customers", "Transactions", "Items", "Data Quality"]) {
  const preview = await wb.render({ sheetName: name, range: name === "README" ? "A1:B11" : name === "Data Quality" ? "A1:C10" : "A1:H18", scale: 1, format: "png" });
  await fs.writeFile(`${outputDir}/${name.replaceAll(" ", "_")}.png`, new Uint8Array(await preview.arrayBuffer()));
}
console.log(`OUTPUT ${outputPath}`);
