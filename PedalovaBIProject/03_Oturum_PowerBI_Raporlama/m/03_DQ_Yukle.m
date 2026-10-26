// =====================================================================
// 03_DQ_Yukle.m  -  Power BI "Veri Kalitesi" sayfası: O1'in dq.* view'larını al
// Parametreler: SqlSunucu, SqlVeritabani (01_Gold_Yukle.m ile aynı). Her sorguyu ayrı Boş Sorgu olarak ekle.
// Bu üç tablo modelde İLİŞKİSİZDİR (bağımsız KPI tabloları).
// =====================================================================

// ---------- Sorgu adı: DQ_Ozet  (dq.vw_DQ_Summary; tek satır) ----------
let
    Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
    Tablo  = Kaynak{[Schema = "dq", Item = "vw_DQ_Summary"]}[Data],
    Tipli  = Table.TransformColumnTypes(Tablo, {
                 {"BronzeRows", Int64.Type}, {"CleanRows", Int64.Type}, {"ViolatedRows", Int64.Type},
                 {"DQScore", type number}, {"DuplicateRows", Int64.Type}, {"QuarantineRows", Int64.Type},
                 {"SilverRows", Int64.Type}, {"CorrectedRows", Int64.Type},
                 {"SilverAcceptancePct", type number}, {"QuarantinePct", type number}, {"DuplicatePct", type number}})
in
    Tipli

// ---------- Sorgu adı: DQ_Kural  (dq.vw_DQ_ByRule; 19 satır) ----------
// let
//     Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
//     Tablo  = Kaynak{[Schema = "dq", Item = "vw_DQ_ByRule"]}[Data],
//     Tipli  = Table.TransformColumnTypes(Tablo, {{"ViolatedRows", Int64.Type}, {"ViolatedPct", type number}})
// in
//     Tipli

// ---------- Sorgu adı: DQ_Boyut  (dq.vw_DQ_ByDimension; 5 satır) ----------
// let
//     Kaynak = Sql.Database(SqlSunucu, SqlVeritabani),
//     Tablo  = Kaynak{[Schema = "dq", Item = "vw_DQ_ByDimension"]}[Data],
//     Tipli  = Table.TransformColumnTypes(Tablo, {{"ViolatedRows", Int64.Type}, {"BronzeRows", Int64.Type}, {"DimensionScore", type number}})
// in
//     Tipli

// Beklenen: DQ_Ozet -> DQScore 94,98; BronzeRows 164.694; SilverRows 161.809; QuarantineRows 1.291; DuplicateRows 1.594
//           DQ_Boyut -> Tamlık 783 (99,525) · Geçerlilik 2.226 (98,648) · Tutarlılık 3.254 (98,024) · Benzersizlik 1.594 (99,032) · Bütünlük 480 (99,709)
//           DQ_Kural -> 19 satır (ör. DQ17 = 1.594, DQ12 = 1.072, DQ11 = 671)
