/* =====================================================================
   34_Silver_Prosedur.sql
   Amaç      : Bronze -> Silver yüklemesi (tam yenileme). Sırasıyla:
               1) silver.vw_Sales_Stage'i bir kez hesapla (#Stage)
               2) dq.RuleViolation  : her satır x ihlal edilen kural
               3) dq.SalesQuarantine: karantina kuralı ihlal eden (ve tekrar olmayan) satırlar
               4) silver.Sales      : tekrar olmayan + karantinaya gitmeyen satırlar (TEMİZ değerlerle)
               5) dq.SilverRunLog   : çalıştırma özeti
   Bağımlılık: 11_, 30_, 31_, 32_, 33_
   Sıra kuralı: ÖNCE tekrarlar elenir (DQ17), SONRA kalan satırlarda karantina kuralları uygulanır.
   ===================================================================== */
USE BikeRetailDW;
GO

CREATE OR ALTER PROCEDURE silver.usp_Load_Silver_Sales
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Start DATETIME2(0) = SYSDATETIME();

    IF NOT EXISTS (SELECT 1 FROM bronze.Sales)
        THROW 50002, N'bronze.Sales boş. Önce bronze.usp_Load_Bronze_Sales çalıştırılmalı (11_Bronze_Yukle.sql).', 1;

    -- 1) Değerlendirmeyi BİR KEZ yap (view ağır; sonuçları geçici tabloya al)
    IF OBJECT_ID(N'tempdb..#Stage') IS NOT NULL DROP TABLE #Stage;
    SELECT * INTO #Stage FROM silver.vw_Sales_Stage;
    CREATE UNIQUE CLUSTERED INDEX IX_Stage_BronzeRowID ON #Stage (BronzeRowID);

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE dq.RuleViolation;
        TRUNCATE TABLE dq.SalesQuarantine;
        TRUNCATE TABLE silver.Sales;

        -- 2) Kural ihlalleri (bayrak sütunlarını satıra çevir)
        INSERT INTO dq.RuleViolation (BronzeRowID, RuleCode, Action)
        SELECT s.BronzeRowID, v.RuleCode, c.Action
        FROM #Stage AS s
        CROSS APPLY (VALUES
            ('DQ01', s.DQ01), ('DQ02', s.DQ02), ('DQ03', s.DQ03), ('DQ04', s.DQ04), ('DQ05', s.DQ05),
            ('DQ06', s.DQ06), ('DQ07', s.DQ07), ('DQ08', s.DQ08), ('DQ09', s.DQ09), ('DQ10', s.DQ10),
            ('DQ11', s.DQ11), ('DQ12', s.DQ12), ('DQ13', s.DQ13), ('DQ14', s.DQ14), ('DQ15', s.DQ15),
            ('DQ16', s.DQ16), ('DQ17', s.DQ17), ('DQ18', s.DQ18), ('DQ19', s.DQ19)
        ) AS v (RuleCode, Flag)
        JOIN dq.RuleCatalog AS c ON c.RuleCode = v.RuleCode
        WHERE v.Flag = 1;

        -- 3) Karantina: ham satır + neden
        INSERT INTO dq.SalesQuarantine
        (
            BronzeRowID, QuarantineReason, QuarantinedAt, SourceFileName, BatchID,
            KaynakAy, SiparisID, SiparisSatirID, SiparisTarihi, MusteriID, MusteriAdi, MusteriCinsiyet, MusteriYas,
            MusteriUyelikYili, MusteriSehir, MagazaID, MagazaAdi, MagazaBolge, SatisKanali, UrunID, UrunAdi,
            UrunKategori, UrunAltKategori, UrunMarka, SiparisAdedi, BirimFiyat, UrunMaliyeti, IndirimOrani,
            KampanyaAdi, OdemeTipi
        )
        SELECT
            s.BronzeRowID,
            STUFF(CONCAT(CASE WHEN s.DQ03 = 1 THEN N', DQ03' ELSE N'' END,
                         CASE WHEN s.DQ04 = 1 THEN N', DQ04' ELSE N'' END,
                         CASE WHEN s.DQ06 = 1 THEN N', DQ06' ELSE N'' END,
                         CASE WHEN s.DQ07 = 1 THEN N', DQ07' ELSE N'' END,
                         CASE WHEN s.DQ18 = 1 THEN N', DQ18' ELSE N'' END,
                         CASE WHEN s.StructuralError = 1 THEN N', YAPISAL' ELSE N'' END), 1, 2, N''),
            @Start, b.SourceFileName, b.BatchID,
            b.KaynakAy, b.SiparisID, b.SiparisSatirID, b.SiparisTarihi, b.MusteriID, b.MusteriAdi, b.MusteriCinsiyet, b.MusteriYas,
            b.MusteriUyelikYili, b.MusteriSehir, b.MagazaID, b.MagazaAdi, b.MagazaBolge, b.SatisKanali, b.UrunID, b.UrunAdi,
            b.UrunKategori, b.UrunAltKategori, b.UrunMarka, b.SiparisAdedi, b.BirimFiyat, b.UrunMaliyeti, b.IndirimOrani,
            b.KampanyaAdi, b.OdemeTipi
        FROM #Stage AS s
        JOIN bronze.Sales AS b ON b.BronzeRowID = s.BronzeRowID
        WHERE s.DQ17 = 0 AND s.HasQuarantineRule = 1;

        -- 4) Silver: tekrar olmayan + karantinaya gitmeyen satırlar, TEMİZ değerlerle
        INSERT INTO silver.Sales
        (
            BronzeRowID, SourceFileName, BatchID, LoadDateTime, SilverLoadDateTime,
            KaynakAy, SiparisID, SiparisSatirID, SiparisTarihi,
            MusteriID, MusteriAdi, MusteriCinsiyet, MusteriYas, MusteriUyelikYili, MusteriSehir,
            MagazaID, MagazaAdi, MagazaBolge, SatisKanali,
            UrunID, UrunAdi, UrunKategori, UrunAltKategori, UrunMarka,
            SiparisAdedi, BirimFiyat, UrunMaliyeti, IndirimOrani, KampanyaAdi, OdemeTipi, IsCorrected
        )
        SELECT
            s.BronzeRowID, s.SourceFileName, s.BatchID, s.LoadDateTime, @Start,
            s.KaynakAy, s.SiparisID, s.SiparisSatirID, s.SiparisTarihi,
            s.MusteriID, s.MusteriAdi, s.MusteriCinsiyet, s.MusteriYas, s.MusteriUyelikYili, s.MusteriSehir,
            s.MagazaID, s.MagazaAdi, s.MagazaBolge, s.SatisKanali,
            s.UrunID, s.UrunAdi, s.UrunKategori, s.UrunAltKategori, s.UrunMarka,
            s.SiparisAdedi, s.BirimFiyat, s.UrunMaliyeti, s.IndirimOrani, s.KampanyaAdi, s.OdemeTipi, s.IsCorrected
        FROM #Stage AS s
        WHERE s.DQ17 = 0 AND s.HasQuarantineRule = 0;

        -- 5) Çalıştırma günlüğü
        INSERT INTO dq.SilverRunLog (RunDateTime, BronzeRows, ViolatedRows, DuplicateRows, QuarantineRows, SilverRows, CorrectedRows, DurationSec)
        SELECT @Start,
               (SELECT COUNT(*) FROM #Stage),
               (SELECT COUNT(DISTINCT BronzeRowID) FROM dq.RuleViolation),
               (SELECT COUNT(*) FROM #Stage WHERE DQ17 = 1),
               (SELECT COUNT(*) FROM dq.SalesQuarantine),
               (SELECT COUNT(*) FROM silver.Sales),
               (SELECT COUNT(*) FROM silver.Sales WHERE IsCorrected = 1),
               DATEDIFF(SECOND, @Start, SYSDATETIME());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT TOP (1) * FROM dq.SilverRunLog ORDER BY RunID DESC;
END
GO

EXEC silver.usp_Load_Silver_Sales;
GO

/* Uzlaştırma: Bronze = Silver + Karantina + Tekrar  (fark 0 olmalı)
   Beklenen (mevcut veri): 17.997 = 17.957 + 11 + 29 */
SELECT (SELECT COUNT(*) FROM bronze.Sales)        AS Bronze,
       (SELECT COUNT(*) FROM silver.Sales)        AS Silver,
       (SELECT COUNT(*) FROM dq.SalesQuarantine)  AS Karantina,
       (SELECT COUNT(DISTINCT BronzeRowID) FROM dq.RuleViolation WHERE RuleCode = 'DQ17') AS Tekrar,
       (SELECT COUNT(*) FROM bronze.Sales)
         - (SELECT COUNT(*) FROM silver.Sales)
         - (SELECT COUNT(*) FROM dq.SalesQuarantine)
         - (SELECT COUNT(DISTINCT BronzeRowID) FROM dq.RuleViolation WHERE RuleCode = 'DQ17') AS Fark;
GO
