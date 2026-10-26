// =====================================================================
// 01_Gold_Yukle.m  -  Power BI Desktop (Veri Al > SQL Server > Import): Gold tabloları
//
// Önce iki parametre oluştur (Giriş > Parametreleri Yönet > Yeni Parametre):
//   SqlSunucu     : Metin = localhost        (veya sunucu\instance)
//   SqlVeritabani : Metin = BikeRetailDW
// Hızlı yol: Veri Al > SQL Server > sunucu + veritabanı > "Import" > gold şemasındaki 8 tabloyu işaretle.
// Kod yolu (parametreli, tekrar kullanılabilir): her sorguyu "Boş Sorgu"ya yapıştır, adını yorumdaki gibi ver.
// Depolama modu: IMPORT (veri küçük; DAX hızlı). DirectQuery ve kompozit model -> Genel Kültür kutusu.
// =====================================================================

// ---------- Sorgu adı: fnGold  (yardımcı fonksiyon; "Yükle" işaretini kapat) ----------
(tablo as text) as table =>
let
    Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
    Tablo  = Kaynak{[Schema = "gold", Item = tablo]}[Data]
in
    Tablo

// ---------- Sorgu adı: FactSales ----------
// Lineage kolonları (SourceFileName, BatchID, GoldLoadDateTime) raporda gereksiz: model küçülsün diye kaldırılır.
// let
//     Kaynak = fnGold("FactSales"),
//     Kolonlar = Table.RemoveColumns(Kaynak, {"SourceFileName", "BatchID", "GoldLoadDateTime"}),
//     Tipli = Table.TransformColumnTypes(Kolonlar, {
//         {"DateKey", Int64.Type}, {"CustomerKey", Int64.Type}, {"ProductKey", Int64.Type}, {"StoreKey", Int64.Type},
//         {"ChannelKey", Int64.Type}, {"PaymentKey", Int64.Type}, {"CampaignKey", Int64.Type},
//         {"OrderID", Int64.Type}, {"OrderLineID", Int64.Type}, {"Quantity", Int64.Type},
//         {"UnitPrice", type number}, {"UnitCost", type number}, {"DiscountRate", type number},
//         {"GrossAmount", type number}, {"DiscountAmount", type number}, {"NetAmount", type number},
//         {"CostAmount", type number}, {"GrossProfit", type number}, {"CustomerAgeAtOrder", Int64.Type}})
// in
//     Tipli

// ---------- Sorgu adı: DimDate ----------
// let
//     Kaynak = fnGold("DimDate"),
//     Tipli = Table.TransformColumnTypes(Kaynak, {{"FullDate", type date}, {"DateKey", Int64.Type}})
// in
//     Tipli

// ---------- Sorgu adları: DimCustomer, DimProduct, DimStore, DimChannel, DimPayment, DimCampaign ----------
// Her biri:  let Kaynak = fnGold("DimCustomer") in Kaynak     (tablo adını değiştir)

// Beklenen satır sayıları (Bilinmiyor üyesi dahil): FactSales 161.809 · DimDate 1.826 · DimCustomer 2.997 · DimProduct 29 ·
//   DimStore 16 · DimChannel 4 · DimPayment 4 · DimCampaign 8
