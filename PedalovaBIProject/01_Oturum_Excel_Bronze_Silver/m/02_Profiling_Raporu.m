// =====================================================================
// 02_Profiling_Raporu.m  -  SQL Server'daki profiling view'larını Excel'e al (rapor = Power Query + PivotTable)
//
// Önce iki parametre oluştur (Sorgu Yönet > Parametreleri Yönet):
//   SqlSunucu    : Metin = localhost            (veya sunucu\instance)
//   SqlVeritabani: Metin = BikeRetailDW
// Her sorguyu "Boş Sorgu"ya ayrı ayrı yapıştır; adlarını yorumdaki gibi ver.
// =====================================================================

// ---------- Sorgu adı: Profil_Kolon  (bronze.vw_DataProfiling) ----------
// let
//     Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
//     Tablo  = Kaynak{[Schema = "bronze", Item = "vw_DataProfiling"]}[Data],
//     Sirali = Table.Sort(Tablo, {{"ColumnOrder", Order.Ascending}}),
//     // Sayısal kolonlara tür ver (rapor için)
//     Tipli  = Table.TransformColumnTypes(Sirali, {
//                 {"RecordCount", Int64.Type}, {"NullCount", Int64.Type}, {"BlankCount", Int64.Type},
//                 {"DistinctCount", Int64.Type}, {"InvalidTypeCount", Int64.Type}}),
//     // Boş + tipe uymayan = "sorunlu" yüzde (PivotTable/koşullu biçimlendirme için)
//     Yuzde  = Table.AddColumn(Tipli, "ProblemPct",
//                 each Number.Round(100.0 * ([BlankCount] + [InvalidTypeCount]) / [RecordCount], 3), type number)
// in
//     Yuzde

// ---------- Sorgu adı: Profil_Kirli  (bronze.vw_DirtyDataMetrics) ----------
let
    Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
    Tablo  = Kaynak{[Schema = "bronze", Item = "vw_DirtyDataMetrics"]}[Data],
    Sirali = Table.Sort(Tablo, {{"AffectedRows", Order.Descending}})
in
    Sirali

// Excel'de: iki sorguyu da sayfaya yükle -> Ekle > PivotTable / Çubuk grafik:
//   Profil_Kirli: MetricName (eksen) x AffectedRows (değer)  -> "en çok hangi kirlilik var?"
//   Profil_Kolon: ColumnName x (BlankCount, InvalidTypeCount, DistinctCount) -> kolon bazlı sağlık tablosu
