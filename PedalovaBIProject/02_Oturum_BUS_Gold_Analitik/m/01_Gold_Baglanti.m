// =====================================================================
// 01_Gold_Baglanti.m  -  Excel Power Query: Gold analitik view'larına bağlan
//
// Önce iki parametre oluştur (Sorgu Yönet > Parametreleri Yönet > Yeni):
//   SqlSunucu     : Metin = localhost        (veya sunucu\instance)
//   SqlVeritabani : Metin = BikeRetailDW
// Her sorguyu "Boş Sorgu" olarak ayrı ekle, adını yorumdaki gibi ver.
// Yükleme: "Tablo" olarak yeni sayfaya (Veri Modeli gerekmez). Tablo adlarını ELLE değiştir (Tablo Tasarımı > Tablo Adı).
// =====================================================================

// ---------- Sorgu adı: Satis_Satir  | Tablo adı: Satis_Satir  (gold.vw_Analytics_SalesLine; 17.954 satır) ----------
// İlk 6 sütun (Quantity, DiscountRate, CustomerAgeAtOrder, NetAmount, GrossProfit, UnitPrice) betimsel istatistik ve
// korelasyon için bitişik analiz aralığıdır. Sütun sırasını DEĞİŞTİRME.
let
    Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
    Tablo  = Kaynak{[Schema = "gold", Item = "vw_Analytics_SalesLine"]}[Data],
    Tipli  = Table.TransformColumnTypes(Tablo, {
                {"Quantity", Int64.Type}, {"DiscountRate", type number}, {"CustomerAgeAtOrder", Int64.Type},
                {"NetAmount", type number}, {"GrossProfit", type number}, {"UnitPrice", type number}})
in
    Tipli

// ---------- Sorgu adı: Siparis_Duzeyi  | Tablo adı: Siparis_Duzeyi  (gold.vw_Analytics_Order; 7.269 satır) ----------
Regresyon: Y = A sütunu (NetAmount); X = B:D (OrderQty, AvgDiscountRate, CustomerAge)
let
    Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
    Tablo  = Kaynak{[Schema = "gold", Item = "vw_Analytics_Order"]}[Data],
    Tipli  = Table.TransformColumnTypes(Tablo, {
                {"NetAmount", type number}, {"OrderQty", Int64.Type},
                {"AvgDiscountRate", type number}, {"CustomerAge", Int64.Type}})
in
    Tipli

// ---------- Sorgu adı: Musteri_RFM  | Tablo adı: Musteri_RFM  (gold.vw_Analytics_Customer; 100 satır) ----------
//Recency (Yenilik / Son Alışveriş Tarihi)
//Frequency (Sıklık / Sipariş Sayısı)
//Monetary (Parasal / Toplam Harcama)
Python in Excel bu tabloyu xl("Musteri_RFM[#All]", headers=True) ile okur. Tablo adı BİREBİR "Musteri_RFM" olmalı.
let
    Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
    Tablo  = Kaynak{[Schema = "gold", Item = "vw_Analytics_Customer"]}[Data],
    Tipli  = Table.TransformColumnTypes(Tablo, {
                {"TotalSpend", type number}, {"OrderCount", Int64.Type}, {"AvgBasket", type number}})
in
    Tipli

// ---------- (İsteğe bağlı) Sorgu adı: Gold_Boyutlar_Kontrol ----------
// BUS Matrix doğrulaması için boyut satır sayıları: gold.DimDate, DimCustomer ... tablolarını Sql.Database ile aynı kalıpla okuyabilirsin.
