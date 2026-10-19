/* =====================================================================
   11_Bronze_Yukle.sql
   Amaç      : Klasördeki TÜM aylık CSV'leri tek çağrıda Bronze'a yükler (Python ELT).
               sp_execute_external_script -> pandas (dtype=str) -> #Stage -> bronze.Sales
   Bağımlılık: 10_Bronze_Kurulum.sql (bronze.Sales, bronze.LoadLog, bronze.ETL_Parametre)
   Yöntem    : TAM YENİLEME (TRUNCATE + INSERT). Python çalışırken hata olursa Bronze'a dokunulmaz.
   ETL meta  : SourceFileName  -> Python'da (dosya adı)
               LoadDateTime    -> SQL'de (SYSDATETIME)
               BatchID         -> SQL'de (NEWID; bu çalıştırmadaki tüm satırlar aynı BatchID)
   Not       : Python kodunda TEK TIRNAK (') kullanma; kod bir T-SQL string'i içinde.
   ===================================================================== */
USE BikeRetailDW;
GO

CREATE OR ALTER PROCEDURE bronze.usp_Load_Bronze_Sales
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FolderPath    NVARCHAR(500) =
            (SELECT Deger FROM bronze.ETL_Parametre WHERE ParametreAdi = N'SalesRawDataPath');
    DECLARE @BatchID       UNIQUEIDENTIFIER = NEWID();
    DECLARE @LoadDateTime  DATETIME2(0)     = SYSDATETIME();

    IF @FolderPath IS NULL
        THROW 50001, N'bronze.ETL_Parametre içinde SalesRawDataPath tanımlı değil (10_Bronze_Kurulum.sql).', 1;

    -- 1) Python: klasörü tara, tüm CSV'leri METİN olarak oku, dosya adını ekle
    CREATE TABLE #Stage
    (
        StageID           INT IDENTITY(1,1) NOT NULL,
        KaynakAy          NVARCHAR(MAX), SiparisID         NVARCHAR(MAX), SiparisSatirID    NVARCHAR(MAX),
        SiparisTarihi     NVARCHAR(MAX), MusteriID         NVARCHAR(MAX), MusteriAdi        NVARCHAR(MAX),
        MusteriCinsiyet   NVARCHAR(MAX), MusteriYas        NVARCHAR(MAX), MusteriUyelikYili NVARCHAR(MAX),
        MusteriSehir      NVARCHAR(MAX), MagazaID          NVARCHAR(MAX), MagazaAdi         NVARCHAR(MAX),
        MagazaBolge       NVARCHAR(MAX), SatisKanali       NVARCHAR(MAX), UrunID            NVARCHAR(MAX),
        UrunAdi           NVARCHAR(MAX), UrunKategori      NVARCHAR(MAX), UrunAltKategori   NVARCHAR(MAX),
        UrunMarka         NVARCHAR(MAX), SiparisAdedi      NVARCHAR(MAX), BirimFiyat        NVARCHAR(MAX),
        UrunMaliyeti      NVARCHAR(MAX), IndirimOrani      NVARCHAR(MAX), KampanyaAdi       NVARCHAR(MAX),
        OdemeTipi         NVARCHAR(MAX), SourceFileName    NVARCHAR(260)
    );

    INSERT INTO #Stage
    (
        KaynakAy, SiparisID, SiparisSatirID, SiparisTarihi, MusteriID, MusteriAdi, MusteriCinsiyet, MusteriYas,
        MusteriUyelikYili, MusteriSehir, MagazaID, MagazaAdi, MagazaBolge, SatisKanali, UrunID, UrunAdi,
        UrunKategori, UrunAltKategori, UrunMarka, SiparisAdedi, BirimFiyat, UrunMaliyeti, IndirimOrani,
        KampanyaAdi, OdemeTipi, SourceFileName
    )
    EXEC sp_execute_external_script
        @language = N'Python',
        @script = N'
import os
import glob
import pandas as pd

KOLONLAR = ["KaynakAy", "SiparisID", "SiparisSatirID", "SiparisTarihi", "MusteriID", "MusteriAdi",
            "MusteriCinsiyet", "MusteriYas", "MusteriUyelikYili", "MusteriSehir", "MagazaID", "MagazaAdi",
            "MagazaBolge", "SatisKanali", "UrunID", "UrunAdi", "UrunKategori", "UrunAltKategori", "UrunMarka",
            "SiparisAdedi", "BirimFiyat", "UrunMaliyeti", "IndirimOrani", "KampanyaAdi", "OdemeTipi"]

klasor = folder_path_param
dosyalar = sorted(glob.glob(os.path.join(klasor, "Satis_????_??.csv")))
if not dosyalar:
    raise FileNotFoundError("CSV bulunamadi: " + klasor)

parcalar = []
for dosya in dosyalar:
    # dtype=str: tip dönüşümü YOK, her değer ham metin; keep_default_na=False: boş hücre NULL değil "" olur
    d = pd.read_csv(dosya, dtype=str, keep_default_na=False, encoding="utf-8-sig")
    eksik = [k for k in KOLONLAR if k not in d.columns]
    if eksik:
        raise ValueError(os.path.basename(dosya) + " eksik kolon: " + ", ".join(eksik))
    d = d[KOLONLAR].copy()
    d["SourceFileName"] = os.path.basename(dosya)
    parcalar.append(d)
    print("Okundu:", os.path.basename(dosya), len(d), "satir")

OutputDataSet = pd.concat(parcalar, ignore_index=True)
print("Toplam:", len(OutputDataSet), "satir,", len(parcalar), "dosya")
',
        @params = N'@folder_path_param NVARCHAR(500)',
        @folder_path_param = @FolderPath

    --!!! Yukarıda insert varken WITH hata verir.
    --WITH RESULT SETS
    --((
    --    KaynakAy          NVARCHAR(MAX), SiparisID         NVARCHAR(MAX), SiparisSatirID    NVARCHAR(MAX),
    --    SiparisTarihi     NVARCHAR(MAX), MusteriID         NVARCHAR(MAX), MusteriAdi        NVARCHAR(MAX),
    --    MusteriCinsiyet   NVARCHAR(MAX), MusteriYas        NVARCHAR(MAX), MusteriUyelikYili NVARCHAR(MAX),
    --    MusteriSehir      NVARCHAR(MAX), MagazaID          NVARCHAR(MAX), MagazaAdi         NVARCHAR(MAX),
    --    MagazaBolge       NVARCHAR(MAX), SatisKanali       NVARCHAR(MAX), UrunID            NVARCHAR(MAX),
    --    UrunAdi           NVARCHAR(MAX), UrunKategori      NVARCHAR(MAX), UrunAltKategori   NVARCHAR(MAX),
    --    UrunMarka         NVARCHAR(MAX), SiparisAdedi      NVARCHAR(MAX), BirimFiyat        NVARCHAR(MAX),
    --    UrunMaliyeti      NVARCHAR(MAX), IndirimOrani      NVARCHAR(MAX), KampanyaAdi       NVARCHAR(MAX),
    --    OdemeTipi         NVARCHAR(MAX), SourceFileName    NVARCHAR(260)
    --));

    -- 2) Bronze'a yaz (tek transaction): ETL meta burada eklenir
    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE bronze.Sales;

        INSERT INTO bronze.Sales
        (
            KaynakAy, SiparisID, SiparisSatirID, SiparisTarihi, MusteriID, MusteriAdi, MusteriCinsiyet, MusteriYas,
            MusteriUyelikYili, MusteriSehir, MagazaID, MagazaAdi, MagazaBolge, SatisKanali, UrunID, UrunAdi,
            UrunKategori, UrunAltKategori, UrunMarka, SiparisAdedi, BirimFiyat, UrunMaliyeti, IndirimOrani,
            KampanyaAdi, OdemeTipi, LoadDateTime, SourceFileName, BatchID
        )
        SELECT
            KaynakAy, SiparisID, SiparisSatirID, SiparisTarihi, MusteriID, MusteriAdi, MusteriCinsiyet, MusteriYas,
            MusteriUyelikYili, MusteriSehir, MagazaID, MagazaAdi, MagazaBolge, SatisKanali, UrunID, UrunAdi,
            UrunKategori, UrunAltKategori, UrunMarka, SiparisAdedi, BirimFiyat, UrunMaliyeti, IndirimOrani,
            KampanyaAdi, OdemeTipi, @LoadDateTime, SourceFileName, @BatchID
        FROM #Stage
        ORDER BY StageID;                       -- BronzeRowID sırası = dosya/satır sırası

        INSERT INTO bronze.LoadLog (BatchID, LoadDateTime, SourceFileName, LoadedRowCount)
        SELECT @BatchID, @LoadDateTime, SourceFileName, COUNT(*)
        FROM #Stage
        GROUP BY SourceFileName;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    -- 3) Özet
    SELECT SourceFileName, LoadedRowCount, BatchID, LoadDateTime
    FROM bronze.LoadLog
    WHERE BatchID = @BatchID
    ORDER BY SourceFileName;
END
GO

-- Çalıştır
EXEC bronze.usp_Load_Bronze_Sales;
GO

-- Hızlı kontrol
SELECT COUNT(*) AS ToplamSatir, COUNT(DISTINCT SourceFileName) AS DosyaSayisi, COUNT(DISTINCT BatchID) AS BatchSayisi
FROM bronze.Sales;

SELECT TOP (5) BronzeRowID, SourceFileName, SiparisID, SiparisTarihi, MusteriAdi, UrunKategori, SiparisAdedi, BirimFiyat, LoadDateTime, BatchID
FROM bronze.Sales
ORDER BY BronzeRowID;
GO
