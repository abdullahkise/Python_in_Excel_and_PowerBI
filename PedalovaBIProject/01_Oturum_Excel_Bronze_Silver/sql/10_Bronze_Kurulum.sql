/* =====================================================================
   10_Bronze_Kurulum.sql
   Amaç      : BikeRetailDW veritabanı, şemalar (bronze/silver/gold/dq), ETL parametre tablosu,
               bronze.Sales (ham, NVARCHAR(MAX)) ve bronze.LoadLog tablolarını kurar.
   Bağımlılık: 00_Ortam_Kontrol.sql başarılı olmalı. 
   Yeniden çalıştırma: bronze.Sales ve bronze.LoadLog SİLİNİP yeniden oluşturulur (veri gider; 11_ ile tekrar yüklenir).
   ===================================================================== */

IF DB_ID(N'BikeRetailDW') IS NULL
    CREATE DATABASE BikeRetailDW;
GO

USE BikeRetailDW;
GO

IF SCHEMA_ID(N'bronze') IS NULL EXEC (N'CREATE SCHEMA bronze');
IF SCHEMA_ID(N'silver') IS NULL EXEC (N'CREATE SCHEMA silver');
IF SCHEMA_ID(N'gold')   IS NULL EXEC (N'CREATE SCHEMA gold');
IF SCHEMA_ID(N'dq')     IS NULL EXEC (N'CREATE SCHEMA dq');
GO

/* ---------- ETL parametre tablosu: klasör yolunun TEK tanımlandığı yer ---------- */
IF OBJECT_ID(N'bronze.ETL_Parametre', N'U') IS NULL
    CREATE TABLE bronze.ETL_Parametre
    (
        ParametreAdi NVARCHAR(100) NOT NULL CONSTRAINT PK_ETL_Parametre PRIMARY KEY,
        Deger        NVARCHAR(500) NOT NULL,
        Aciklama     NVARCHAR(300) NULL
    );
GO

-- >>> Klasör yolunu yalnızca BURADA değiştir <<<
DECLARE @SalesRawDataPath NVARCHAR(500) = N'C:\PedalovaBIProject\SalesRawData';

IF EXISTS (SELECT 1 FROM bronze.ETL_Parametre WHERE ParametreAdi = N'SalesRawDataPath')
    UPDATE bronze.ETL_Parametre SET Deger = @SalesRawDataPath WHERE ParametreAdi = N'SalesRawDataPath';
ELSE
    INSERT INTO bronze.ETL_Parametre (ParametreAdi, Deger, Aciklama)
    VALUES (N'SalesRawDataPath', @SalesRawDataPath, N'Aylık Satis_YYYY_MM.csv dosyalarının bulunduğu klasör (SQL Python süreci okuyabilmeli)');
GO

/* ---------- bronze.Sales: ham veri, TÜM kaynak kolonlar NVARCHAR(MAX) ----------
   Neden metin? Kirli değerler ("720,42", "15.03.2023", "") yükleme sırasında tip hatası vermesin;
   ham veri kaynağa sadık kalsın. Tipleme Silver'da yapılır. */
IF OBJECT_ID(N'bronze.Sales', N'U') IS NOT NULL DROP TABLE bronze.Sales;
GO

CREATE TABLE bronze.Sales
(
    BronzeRowID       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_bronze_Sales PRIMARY KEY,

    KaynakAy          NVARCHAR(MAX) NULL,
    SiparisID         NVARCHAR(MAX) NULL,
    SiparisSatirID    NVARCHAR(MAX) NULL,
    SiparisTarihi     NVARCHAR(MAX) NULL,
    MusteriID         NVARCHAR(MAX) NULL,
    MusteriAdi        NVARCHAR(MAX) NULL,
    MusteriCinsiyet   NVARCHAR(MAX) NULL,
    MusteriYas        NVARCHAR(MAX) NULL,
    MusteriUyelikYili NVARCHAR(MAX) NULL,
    MusteriSehir      NVARCHAR(MAX) NULL,
    MagazaID          NVARCHAR(MAX) NULL,
    MagazaAdi         NVARCHAR(MAX) NULL,
    MagazaBolge       NVARCHAR(MAX) NULL,
    SatisKanali       NVARCHAR(MAX) NULL,
    UrunID            NVARCHAR(MAX) NULL,
    UrunAdi           NVARCHAR(MAX) NULL,
    UrunKategori      NVARCHAR(MAX) NULL,
    UrunAltKategori   NVARCHAR(MAX) NULL,
    UrunMarka         NVARCHAR(MAX) NULL,
    SiparisAdedi      NVARCHAR(MAX) NULL,
    BirimFiyat        NVARCHAR(MAX) NULL,
    UrunMaliyeti      NVARCHAR(MAX) NULL,
    IndirimOrani      NVARCHAR(MAX) NULL,
    KampanyaAdi       NVARCHAR(MAX) NULL,
    OdemeTipi         NVARCHAR(MAX) NULL,

    -- ETL meta verisi (CSV'de yok; yükleme sırasında eklenir)
    LoadDateTime      DATETIME2(0)     NOT NULL,
    SourceFileName    NVARCHAR(260)    NOT NULL,
    BatchID           UNIQUEIDENTIFIER NOT NULL
);
GO

/* ---------- bronze.LoadLog: dosya bazlı yükleme kaydı (uzlaştırma için) ---------- */
IF OBJECT_ID(N'bronze.LoadLog', N'U') IS NOT NULL DROP TABLE bronze.LoadLog;
GO

CREATE TABLE bronze.LoadLog
(
    LoadLogID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_bronze_LoadLog PRIMARY KEY,
    BatchID         UNIQUEIDENTIFIER NOT NULL,
    LoadDateTime    DATETIME2(0)     NOT NULL,
    SourceFileName  NVARCHAR(260)    NOT NULL,
    LoadedRowCount  INT              NOT NULL
);
GO

SELECT N'Kurulum tamam' AS Durum, DB_NAME() AS Veritabani,
       (SELECT Deger FROM bronze.ETL_Parametre WHERE ParametreAdi = N'SalesRawDataPath') AS SalesRawDataPath;
GO
