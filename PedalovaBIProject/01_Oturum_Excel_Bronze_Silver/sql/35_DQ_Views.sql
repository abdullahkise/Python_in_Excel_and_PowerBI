/* =====================================================================
   35_DQ_Views.sql
   Amaç      : DQ Skoru ve kalite raporu view'ları (Power BI KPI + Excel "son durum raporu" kaynağı).
   Bağımlılık: 34_Silver_Prosedur.sql çalıştırılmış olmalı (dq.SilverRunLog, dq.RuleViolation dolu).
   Üretir    : dq.vw_DQ_Summary      tek satır: DQ Skoru, kabul/karantina/tekrar oranı (son çalıştırma)
               dq.vw_DQ_ByRule       kural bazlı ihlal (19 satır)
               dq.vw_DQ_ByDimension  kalite boyutu bazlı skor (5 satır)
               dq.vw_DQ_Quarantine   karantinadaki satırlar (inceleme listesi)
   Tanımlar  : DQ Skoru (%) = 100 x (hiçbir kuralı ihlal etmeyen Bronze satırı / toplam Bronze satırı)
               Boyut skoru  = 100 x (1 - o boyutta en az 1 ihlali olan satır / toplam Bronze satırı)
   ===================================================================== */
USE BikeRetailDW;
GO

CREATE OR ALTER VIEW dq.vw_DQ_Summary
AS
SELECT
    r.RunID,
    r.RunDateTime,
    r.BronzeRows,
    r.BronzeRows - r.ViolatedRows                                         AS CleanRows,
    r.ViolatedRows,
    CAST(100.0 * (r.BronzeRows - r.ViolatedRows) / NULLIF(r.BronzeRows, 0) AS DECIMAL(5,2)) AS DQScore,
    r.DuplicateRows,
    r.QuarantineRows,
    r.SilverRows,
    r.CorrectedRows,
    CAST(100.0 * r.SilverRows     / NULLIF(r.BronzeRows, 0) AS DECIMAL(5,2)) AS SilverAcceptancePct,
    CAST(100.0 * r.QuarantineRows / NULLIF(r.BronzeRows, 0) AS DECIMAL(5,2)) AS QuarantinePct,
    CAST(100.0 * r.DuplicateRows  / NULLIF(r.BronzeRows, 0) AS DECIMAL(5,2)) AS DuplicatePct
FROM dq.SilverRunLog AS r
WHERE r.RunID = (SELECT MAX(RunID) FROM dq.SilverRunLog);
GO

CREATE OR ALTER VIEW dq.vw_DQ_ByRule
AS
SELECT
    c.RuleCode,
    c.Dimension,
    c.RuleDescription,
    c.Action,
    COUNT(v.BronzeRowID)                                                           AS ViolatedRows,
    CAST(100.0 * COUNT(v.BronzeRowID) / NULLIF(s.BronzeRows, 0) AS DECIMAL(6,3))   AS ViolatedPct
FROM dq.RuleCatalog AS c
LEFT JOIN dq.RuleViolation AS v ON v.RuleCode = c.RuleCode
CROSS JOIN dq.vw_DQ_Summary AS s
GROUP BY c.RuleCode, c.Dimension, c.RuleDescription, c.Action, s.BronzeRows;
GO

CREATE OR ALTER VIEW dq.vw_DQ_ByDimension
AS
SELECT
    d.Dimension,
    COUNT(DISTINCT d.BronzeRowID)                                                  AS ViolatedRows,
    s.BronzeRows,
    CAST(100.0 * (1 - 1.0 * COUNT(DISTINCT d.BronzeRowID) / NULLIF(s.BronzeRows, 0)) AS DECIMAL(6,3)) AS DimensionScore
FROM
(
    SELECT c.Dimension, v.BronzeRowID
    FROM dq.RuleCatalog AS c
    LEFT JOIN dq.RuleViolation AS v ON v.RuleCode = c.RuleCode
) AS d
CROSS JOIN dq.vw_DQ_Summary AS s
GROUP BY d.Dimension, s.BronzeRows;
GO

CREATE OR ALTER VIEW dq.vw_DQ_Quarantine
AS
SELECT BronzeRowID, SourceFileName, QuarantineReason, SiparisID, SiparisSatirID, SiparisTarihi, MusteriID,
       UrunID, SiparisAdedi, BirimFiyat
FROM dq.SalesQuarantine;
GO

/* ---------- Kullanım ----------
   Beklenen (mevcut veri: 17.997 Bronze satır; python\hesapla_beklenen_degerler.py çıktısı):
   Summary : BronzeRows 17997 | ViolatedRows 88 | CleanRows 17909 | DQScore 99.51 | DuplicateRows 29 |
             QuarantineRows 11 | SilverRows 17957 | CorrectedRows 48 | SilverAcceptancePct 99.78 | QuarantinePct 0.06
   Boyut   : Tamlık 9 satır (99.950) | Geçerlilik 20 (99.889) | Tutarlılık 25 (99.861) | Benzersizlik 29 (99.839) | Bütünlük 5 (99.972) */
SELECT * FROM dq.vw_DQ_Summary;
SELECT * FROM dq.vw_DQ_ByDimension ORDER BY DimensionScore;
SELECT * FROM dq.vw_DQ_ByRule      ORDER BY ViolatedRows DESC, RuleCode;
SELECT * FROM dq.vw_DQ_Quarantine  ORDER BY BronzeRowID;
GO
