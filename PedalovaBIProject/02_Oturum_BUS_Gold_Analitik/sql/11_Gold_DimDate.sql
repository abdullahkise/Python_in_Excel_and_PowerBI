/* =====================================================================
   11_Gold_DimDate.sql
   Amaç      : DimDate'i ÜRETİM SCRİPTİ ile doldurur (takvim bir kaynaktan gelmez, üretilir).
   Bağımlılık: 10_Gold_Tablolar.sql
   Parametre : @StartDate / @EndDate -> TAM yıllar (Time Intelligence için kesintisiz, boşluksuz tarih tablosu şart).
   Yeniden çalıştırma: Yalnızca eksik tarihleri ekler (FactSales FK ile bağlı olduğu için TRUNCATE yapılmaz).
   Not       : Ay/gün adları dil ayarından bağımsız olsun diye CHOOSE ile Türkçe yazıldı.
               Haftanın günü DATEFIRST'ten bağımsız hesaplanır: 1900-01-01 bir PAZARTESİ'dir.
   ===================================================================== */
USE BikeRetailDW;
GO

DECLARE @StartDate DATE = '2022-01-01';
DECLARE @EndDate   DATE = '2026-12-31';

WITH D AS
(
    SELECT @StartDate AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM D WHERE d < @EndDate
)
INSERT INTO gold.DimDate
    (DateKey, FullDate, [Year], [Quarter], QuarterName, MonthNo, MonthName, MonthShort,
     YearMonth, YearMonthKey, WeekOfYear, [DayOfMonth], DayOfWeekNo, DayName, IsWeekend)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), x.d, 112))                                    AS DateKey,
    x.d                                                                         AS FullDate,
    YEAR(x.d)                                                                   AS [Year],
    DATEPART(QUARTER, x.d)                                                      AS [Quarter],
    N'Ç' + CAST(DATEPART(QUARTER, x.d) AS NVARCHAR(1))                          AS QuarterName,
    MONTH(x.d)                                                                  AS MonthNo,
    CHOOSE(MONTH(x.d), N'Ocak', N'Şubat', N'Mart', N'Nisan', N'Mayıs', N'Haziran',
                       N'Temmuz', N'Ağustos', N'Eylül', N'Ekim', N'Kasım', N'Aralık') AS MonthName,
    CHOOSE(MONTH(x.d), N'Oca', N'Şub', N'Mar', N'Nis', N'May', N'Haz',
                       N'Tem', N'Ağu', N'Eyl', N'Eki', N'Kas', N'Ara')          AS MonthShort,
    CONVERT(CHAR(7), x.d, 23)                                                   AS YearMonth,
    YEAR(x.d) * 100 + MONTH(x.d)                                                AS YearMonthKey,
    DATEPART(ISO_WEEK, x.d)                                                     AS WeekOfYear,
    DAY(x.d)                                                                    AS [DayOfMonth],
    w.dow                                                                       AS DayOfWeekNo,
    CHOOSE(w.dow, N'Pazartesi', N'Salı', N'Çarşamba', N'Perşembe', N'Cuma', N'Cumartesi', N'Pazar') AS DayName,
    CASE WHEN w.dow >= 6 THEN 1 ELSE 0 END                                      AS IsWeekend
FROM D AS x
CROSS APPLY (SELECT (DATEDIFF(DAY, '19000101', x.d) % 7) + 1 AS dow) AS w        -- 1 = Pazartesi
WHERE NOT EXISTS (SELECT 1 FROM gold.DimDate AS t WHERE t.DateKey = CONVERT(INT, CONVERT(CHAR(8), x.d, 112)))
OPTION (MAXRECURSION 0);
GO

/* ---------- Kontrol ----------
   Beklenen: 1826 satır (2022-01-01 .. 2026-12-31; 2024 artık yıl), 2023-01-01 -> Pazar (7), ISO hafta 52 (!), IsWeekend = 1. */
SELECT COUNT(*) AS SatirSayisi, MIN(FullDate) AS IlkTarih, MAX(FullDate) AS SonTarih,
       COUNT(*) - DATEDIFF(DAY, MIN(FullDate), MAX(FullDate)) AS BoslukKontrol          -- 1 olmalı (kesintisiz)
FROM gold.DimDate;

SELECT * FROM gold.DimDate WHERE DateKey IN (20230101, 20240229, 20231225) ORDER BY DateKey;
GO
