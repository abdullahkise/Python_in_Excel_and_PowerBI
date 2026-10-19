// =====================================================================
// 01_Klasorden_Baglanti.m  -  Excel Power Query: klasördeki aylık CSV'leri tek tabloda birleştir (KEŞİF)
//
// Nasıl kullanılır?
//   1) Veri > Veri Al > Diğer Kaynaklardan > Boş Sorgu > Gelişmiş Düzenleyici > bu kodu yapıştır.
//      (Daha hızlı GUI yolu: Veri > Veri Al > Dosyadan > Klasörden > Birleştir ve Dönüştür. Aşağıdaki kod,
//       GUI'nin arkada ürettiğinin sadeleştirilmiş ve PARAMETRELİ halidir.)
//   2) Önce iki parametre oluştur (Sorgu Yönet > Parametreleri Yönet > Yeni):
//        KlasorYolu  : Metin  = C:\PedalovaBIProject\SalesRawData
//        IlkAySayisi : Sayı   = 3        (Excel keşfinde ilk 3 ay; SQL tüm dosyaları okur)
//   3) Sorguya "Satis_Ham" adını ver. Yükle: "Yalnızca bağlantı oluştur" + "Bu verileri Veri Modeline ekle".
//      (Sayfaya yüklemek yerine Power Pivot'a alıyoruz: sayfa 1.048.576 satırla sınırlı, model değil.)
//
// ÖNEMLİ: Tüm kolonlar METİN kalır. Tür algılamayı kapat:
//   Dosya > Seçenekler > Veri > Power Query Düzenleyici > Tür algılama = "Hiçbir zaman" (veya her sorgu için kapalı).
//   Neden? "720,42", "15.03.2023", "" gibi kirli değerler tür dönüşümünde hataya düşer veya SESSİZCE yanlış okunur
//   (bölgesel ayara göre virgül/nokta farklı yorumlanır). Keşifte amaç düzeltmek değil, KUSURU GÖRMEK.
// =====================================================================
let
    Kaynak      = Folder.Files(KlasorYolu),
    SadeceCsv   = Table.SelectRows(Kaynak, each Text.StartsWith([Name], "Satis_") and Text.EndsWith([Name], ".csv")),
    Sirali      = Table.Sort(SadeceCsv, {{"Name", Order.Ascending}}),
    IlkN        = Table.FirstN(Sirali, IlkAySayisi),

    // Her dosyayı oku: UTF-8 (65001), 25 kolon, tırnaklı alanlara saygı, ilk satır başlık
    Oku         = Table.AddColumn(
                    IlkN, "Veri",
                    each Table.PromoteHeaders(
                            Csv.Document([Content], [Delimiter = ",", Columns = 25, Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
                            [PromoteAllScalars = true])),
    Secili      = Table.SelectColumns(Oku, {"Name", "Veri"}),
    Genislet    = Table.ExpandTableColumn(Secili, "Veri", Table.ColumnNames(Secili{0}[Veri])),
    Adlandir    = Table.RenameColumns(Genislet, {{"Name", "SourceFileName"}}),   // SQL'deki Bronze ile aynı meta kolon adı

    // Her kolonu açıkça METİN yap (tür algılama kapalı olsa da güvence)
    TumMetin    = Table.TransformColumnTypes(Adlandir, List.Transform(Table.ColumnNames(Adlandir), each {_, type text}))
in
    TumMetin
