// =====================================================================
// 02_Musteri_Segmentleri.m  -  Excel'in ürettiği Musteri_Segmentleri.csv'yi Power BI'a al
//
// Parametre (Parametreleri Yönet): SegmentCsvYolu : Metin = C:\PedalovaBIProject\Musteri_Segmentleri.csv
// Sorguyu "Boş Sorgu" olarak ekle, adını "Musteri_Segmentleri" yap.
//
// TÜRKÇE EXCEL TUZAĞI: Türkçe bölgesel ayarlarda Excel "CSV UTF-8 (virgülle ayrılmış)" dosyasını çoğu zaman
// AYRAÇ = ";" ve ONDALIK = "," ile kaydeder. Bu kod ayracı ilk satırdan algılar ve sayıları ona göre okur.
// (Plan B dosyası Musteri_Segmentleri_PlanB.csv ayraç "," ve ondalık "." kullanır.)
// =====================================================================
let
    Kaynak   = File.Contents(SegmentCsvYolu),
    IlkSatir = Lines.FromBinary(Kaynak, null, null, 65001){0},
    Ayirac   = if Text.Contains(IlkSatir, ";") then ";" else ",",
    Kultur   = if Ayirac = ";" then "tr-TR" else "en-US",
    Csv      = Csv.Document(Kaynak, [Delimiter = Ayirac, Columns = 5, Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Baslik   = Table.PromoteHeaders(Csv, [PromoteAllScalars = true]),
    Tipli    = Table.TransformColumnTypes(Baslik, {
                   {"CustomerID", type text}, {"Segment", type text},
                   {"TotalSpend", type number}, {"OrderCount", Int64.Type}, {"AvgBasket", type number}}, Kultur)
in
    Tipli

// Model: Musteri_Segmentleri[CustomerID]  1:1  DimCustomer[CustomerID]  (tek yönlü: DimCustomer -> Musteri_Segmentleri değil,
// Segment sütunuyla FactSales'i filtrelemek için ÇİFT YÖNLÜ gerekir; 1:1 ilişkilerde Power BI çift yönü kendisi kurar).
// Beklenen: 2.996 satır; Segment dağılımı: Düşük Hacimli 1.349 · Sık Küçük Alıcı 668 · Düzenli Orta 628 · Nadir Büyük Sepet 351.
// Kontrol: toplam TotalSpend = 493.432.732,75 (FactSales Net Satış toplamıyla aynı).
