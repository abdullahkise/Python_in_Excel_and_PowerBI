/* =====================================================================
   32_Silver_Tablolar.sql
   Amaç      : Silver hedef tablosu ve DQ tabloları (ihlal, karantina, çalıştırma günlüğü).
   Bağımlılık: 10_Bronze_Kurulum.sql, 30_Silver_Referans.sql (dq.RuleCatalog).
   Yeniden çalıştırma: tablolar silinip yeniden oluşturulur (34_ ile tekrar yüklenir).
   ===================================================================== */
USE BikeRetailDW;
GO

/* ---------- silver.Sales: temiz, tipli, standart. Grain = (SiparisID, SiparisSatirID) ---------- */
IF OBJECT_ID(N'silver.Sales', N'U') IS NOT NULL DROP TABLE silver.Sales;
GO
CREATE TABLE silver.Sales
(
    -- lineage (hangi Bronze satırından, hangi dosyadan, hangi batch'ten?)
    BronzeRowID        BIGINT           NOT NULL,
    SourceFileName     NVARCHAR(260)    NOT NULL,
    BatchID            UNIQUEIDENTIFIER NOT NULL,
    LoadDateTime       DATETIME2(0)     NOT NULL,       -- Bronze'a yüklenme zamanı
    SilverLoadDateTime DATETIME2(0)     NOT NULL,

    KaynakAy           CHAR(7)          NOT NULL,
    SiparisID          BIGINT           NOT NULL,
    SiparisSatirID     INT              NOT NULL,
    SiparisTarihi      DATE             NOT NULL,

    MusteriID          CHAR(6)          NOT NULL,
    MusteriAdi         NVARCHAR(100)    NOT NULL,
    MusteriCinsiyet    NVARCHAR(10)     NOT NULL,
    MusteriYas         TINYINT          NULL,           -- geçersiz yaş NULL'a çevrilir (satır korunur)
    MusteriUyelikYili  SMALLINT         NOT NULL,
    MusteriSehir       NVARCHAR(50)     NOT NULL,

    MagazaID           CHAR(4)          NOT NULL,
    MagazaAdi          NVARCHAR(100)    NOT NULL,
    MagazaBolge        NVARCHAR(50)     NOT NULL,
    SatisKanali        NVARCHAR(20)     NOT NULL,

    UrunID             CHAR(4)          NOT NULL,
    UrunAdi            NVARCHAR(100)    NOT NULL,
    UrunKategori       NVARCHAR(30)     NOT NULL,
    UrunAltKategori    NVARCHAR(50)     NOT NULL,
    UrunMarka          NVARCHAR(50)     NOT NULL,

    SiparisAdedi       INT              NOT NULL,
    BirimFiyat         DECIMAL(12,2)    NOT NULL,
    UrunMaliyeti       DECIMAL(12,2)    NOT NULL,
    IndirimOrani       DECIMAL(4,2)     NOT NULL,

    KampanyaAdi        NVARCHAR(60)     NOT NULL,
    OdemeTipi          NVARCHAR(20)     NOT NULL,

    IsCorrected        BIT              NOT NULL,       -- satırda en az bir düzeltme yapıldı mı?

    CONSTRAINT PK_silver_Sales PRIMARY KEY (SiparisID, SiparisSatirID)   -- DQ17'yi veritabanı da garanti eder
);
GO

/* ---------- dq.RuleViolation: satır x kural ihlali (tüm Bronze satırları için) ---------- */
IF OBJECT_ID(N'dq.RuleViolation', N'U') IS NOT NULL DROP TABLE dq.RuleViolation;
GO
CREATE TABLE dq.RuleViolation
(
    BronzeRowID BIGINT       NOT NULL,
    RuleCode    CHAR(4)      NOT NULL,
    Action      NVARCHAR(20) NOT NULL,       -- Düzelt / NULL / Karantina / Tekrar Elendi (RuleCatalog'dan)
    CONSTRAINT PK_dq_RuleViolation PRIMARY KEY (BronzeRowID, RuleCode)
);
GO

/* ---------- dq.SalesQuarantine: Silver'a ALINMAYAN satırlar (ham haliyle) + neden ---------- */
IF OBJECT_ID(N'dq.SalesQuarantine', N'U') IS NOT NULL DROP TABLE dq.SalesQuarantine;
GO
CREATE TABLE dq.SalesQuarantine
(
    BronzeRowID       BIGINT        NOT NULL CONSTRAINT PK_dq_SalesQuarantine PRIMARY KEY,
    QuarantineReason  NVARCHAR(100) NOT NULL,          -- örn. 'DQ04' veya 'DQ03, DQ07'
    QuarantinedAt     DATETIME2(0)  NOT NULL,
    SourceFileName    NVARCHAR(260) NOT NULL,
    BatchID           UNIQUEIDENTIFIER NOT NULL,

    KaynakAy NVARCHAR(MAX), SiparisID NVARCHAR(MAX), SiparisSatirID NVARCHAR(MAX), SiparisTarihi NVARCHAR(MAX),
    MusteriID NVARCHAR(MAX), MusteriAdi NVARCHAR(MAX), MusteriCinsiyet NVARCHAR(MAX), MusteriYas NVARCHAR(MAX),
    MusteriUyelikYili NVARCHAR(MAX), MusteriSehir NVARCHAR(MAX), MagazaID NVARCHAR(MAX), MagazaAdi NVARCHAR(MAX),
    MagazaBolge NVARCHAR(MAX), SatisKanali NVARCHAR(MAX), UrunID NVARCHAR(MAX), UrunAdi NVARCHAR(MAX),
    UrunKategori NVARCHAR(MAX), UrunAltKategori NVARCHAR(MAX), UrunMarka NVARCHAR(MAX), SiparisAdedi NVARCHAR(MAX),
    BirimFiyat NVARCHAR(MAX), UrunMaliyeti NVARCHAR(MAX), IndirimOrani NVARCHAR(MAX), KampanyaAdi NVARCHAR(MAX),
    OdemeTipi NVARCHAR(MAX)
);
GO

/* ---------- dq.SilverRunLog: her Silver yüklemesinin özeti (vw_DQ_Summary buradan okur) ---------- */
IF OBJECT_ID(N'dq.SilverRunLog', N'U') IS NOT NULL DROP TABLE dq.SilverRunLog;
GO
CREATE TABLE dq.SilverRunLog
(
    RunID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dq_SilverRunLog PRIMARY KEY,
    RunDateTime    DATETIME2(0)  NOT NULL,
    BronzeRows     INT           NOT NULL,
    ViolatedRows   INT           NOT NULL,     -- en az 1 kural ihlal eden benzersiz Bronze satırı
    DuplicateRows  INT           NOT NULL,     -- elenen tekrar satırı
    QuarantineRows INT           NOT NULL,
    SilverRows     INT           NOT NULL,
    CorrectedRows  INT           NOT NULL,     -- Silver'da düzeltilen (IsCorrected = 1)
    DurationSec    INT           NOT NULL
);
GO

SELECT N'Silver/DQ tabloları hazır' AS Durum;
GO
