// =====================================================================
// 03_DQ_Son_Durum_Raporu.m  -  Silver sonrası "son durum raporu": DQ Skoru + kural/boyut kırılımı
// Parametreler: SqlSunucu, SqlVeritabani (02_Profiling_Raporu.m ile aynı).
// Her sorguyu ayrı Boş Sorgu olarak ekle.
// =====================================================================

// ---------- Sorgu adı: DQ_Ozet  (dq.vw_DQ_Summary; tek satır KPI) ----------
let
    Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
    Tablo  = Kaynak{[Schema = "dq", Item = "vw_DQ_Summary"]}[Data]
in
    Tablo

// ---------- Sorgu adı: DQ_Kural  (dq.vw_DQ_ByRule) ----------
// let
//     Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
//     Tablo  = Kaynak{[Schema = "dq", Item = "vw_DQ_ByRule"]}[Data],
//     Sirali = Table.Sort(Tablo, {{"ViolatedRows", Order.Descending}})
// in
//     Sirali

// ---------- Sorgu adı: DQ_Boyut  (dq.vw_DQ_ByDimension) ----------
// let
//     Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
//     Tablo  = Kaynak{[Schema = "dq", Item = "vw_DQ_ByDimension"]}[Data]
// in
//     Tablo

// Excel'de önerilen rapor sayfası "DQ_SonDurum":
//   - DQ_Ozet: DQScore (büyük kart), SilverRows / QuarantineRows / DuplicateRows
//   - DQ_Kural: çubuk grafik (RuleCode x ViolatedRows), Action'a göre renklendir
//   - DQ_Boyut: DimensionScore tablosu + koşullu biçimlendirme (veri çubuğu)
// Bu üç tablo, O3'te Power BI "Veri Kalitesi" sayfasının da kaynağıdır.
