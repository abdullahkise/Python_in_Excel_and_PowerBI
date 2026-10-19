/* =====================================================================
   12_Bronze_Kontrol.sql
   Amaç      : Bronze yüklemesini doğrula (satır uzlaştırma) ve ince bir view sun.
   Bağımlılık: 11_Bronze_Yukle.sql çalıştırılmış olmalı.
   ===================================================================== */
USE BikeRetailDW;
GO

CREATE OR ALTER VIEW bronze.vw_Bronze_Sales
AS
SELECT
    BronzeRowID, SourceFileName, BatchID, LoadDateTime,
    KaynakAy, SiparisID, SiparisSatirID, SiparisTarihi, MusteriID, MusteriAdi, MusteriCinsiyet, MusteriYas,
    MusteriUyelikYili, MusteriSehir, MagazaID, MagazaAdi, MagazaBolge, SatisKanali, UrunID, UrunAdi,
    UrunKategori, UrunAltKategori, UrunMarka, SiparisAdedi, BirimFiyat, UrunMaliyeti, IndirimOrani,
    KampanyaAdi, OdemeTipi
FROM bronze.Sales;
GO

/* ---------- 1) Dosya bazlı satır uzlaştırma ----------
   Beklenen değerler (mevcut veri seti, hesapla_beklenen_degerler.py çıktısı):
     Satis_2023_01.csv = 5.126 | Satis_2023_02.csv = 5.120 | Satis_2023_03.csv = 7.751 | TOPLAM = 17.997
   Başka bir veri setinde sayılar farklıdır: python\hesapla_beklenen_degerler.py <klasör> çalıştır. */
SELECT s.SourceFileName,
       COUNT(*)            AS BronzeSatir,
       l.LoadedRowCount    AS LoadLogSatir,
       CASE WHEN COUNT(*) = l.LoadedRowCount THEN N'OK' ELSE N'FARK VAR' END AS Uzlastirma
FROM bronze.Sales AS s
JOIN bronze.LoadLog AS l ON l.BatchID = s.BatchID AND l.SourceFileName = s.SourceFileName
GROUP BY s.SourceFileName, l.LoadedRowCount
ORDER BY s.SourceFileName;

SELECT COUNT(*) AS ToplamBronzeSatir FROM bronze.Sales;
GO

/* ---------- 2) ETL meta verisi: kim, ne zaman, hangi dosyadan? ---------- */
SELECT DISTINCT BatchID, LoadDateTime, SourceFileName
FROM bronze.Sales
ORDER BY SourceFileName;
GO

/* ---------- 3) "Ham veri ham kalmalı" kanıtı: kirli değerler olduğu gibi duruyor ---------- */
SELECT TOP (10) BronzeRowID, SourceFileName, SiparisTarihi, BirimFiyat, UrunMaliyeti, IndirimOrani, MusteriSehir, MusteriAdi
FROM bronze.Sales
WHERE SiparisTarihi LIKE N'%.%.%'          -- dd.MM.yyyy biçimi
   OR BirimFiyat   LIKE N'%,%'             -- virgüllü ondalık
   OR UrunMaliyeti LIKE N'%,%'
   OR LTRIM(RTRIM(MusteriAdi)) = N''       -- boş ad
ORDER BY BronzeRowID;
GO

/* ---------- 4) Genel Kültür: neden TABLO (view değil)? ----------
   Tablo : Python süreci bir kez çalışır; LoadDateTime/BatchID sabit; tekrar sorgularda disk/Python maliyeti yok.
   View  : Kaynağı her sorguda yeniden okumak gerekir (Python'u her SELECT'te tetiklemek mümkün değil/pratik değil).
   Gerçek hayatta: Bronze genelde artımlı yüklenir (yeni dosya = yeni BatchID, TRUNCATE yok). */
GO
