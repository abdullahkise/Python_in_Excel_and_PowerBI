"""
Silver DQ kurallarinin pandas referans uygulamasi (egitmen dogrulama araci).

Amac: SQL'deki (silver.vw_Sales_Stage / usp_Load_Silver_Sales) mantigin AYNISINI Python'da
hesaplayip "beklenen sayilari" uretmek. SQL sonuclari bu cikti ile karsilastirilir.
Veri degisirse (seed/parametre) sayilar da degisir; bu script her veri seti icin yeniden calistirilir.

Bagimlilik: pandas
Kullanim:
  python hesapla_beklenen_degerler.py <SalesRawData klasoru> [--kontrol <EgitmenKontrol klasoru>] [--ilk-n-ay 3]
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KOLONLAR = [
    "KaynakAy", "SiparisID", "SiparisSatirID", "SiparisTarihi", "MusteriID", "MusteriAdi",
    "MusteriCinsiyet", "MusteriYas", "MusteriUyelikYili", "MusteriSehir", "MagazaID", "MagazaAdi",
    "MagazaBolge", "SatisKanali", "UrunID", "UrunAdi", "UrunKategori", "UrunAltKategori", "UrunMarka",
    "SiparisAdedi", "BirimFiyat", "UrunMaliyeti", "IndirimOrani", "KampanyaAdi", "OdemeTipi",
]

# silver.RefProduct / RefStore sql dosyasindaki seed ile ayni olmali (30_Silver_Referans.sql)
URUNLER = {
    "P001": ("Zirvex Dağ Bisikleti 29", "Bisiklet", "Dağ Bisikleti", "Zirvex", 18500),
    "P002": ("Rotalux Yol Bisikleti Karbon", "Bisiklet", "Yol Bisikleti", "Rotalux", 26000),
    "P003": ("Urbanta Şehir Bisikleti", "Bisiklet", "Şehir Bisikleti", "Urbanta", 12500),
    "P004": ("Voltrik Elektrikli Şehir Bisikleti", "Bisiklet", "Elektrikli Bisiklet", "Voltrik", 48000),
    "P005": ("Urbanta Katlanır Bisiklet", "Bisiklet", "Şehir Bisikleti", "Urbanta", 15500),
    "P006": ("Voltrik Elektrikli Dağ Bisikleti", "Bisiklet", "Elektrikli Bisiklet", "Voltrik", 62000),
    "P007": ("Torkpro Vites Seti 2x11", "Bileşen", "Vites", "Torkpro", 4200),
    "P008": ("Torkpro Arka Aktarıcı", "Bileşen", "Vites", "Torkpro", 1900),
    "P009": ("Frenix Disk Fren Seti", "Bileşen", "Fren", "Frenix", 2600),
    "P010": ("Frenix Fren Balatası", "Bileşen", "Fren", "Frenix", 350),
    "P011": ("Lastikor Dağ Lastiği", "Bileşen", "Lastik", "Lastikor", 900),
    "P012": ("Lastikor Yol Lastiği", "Bileşen", "Lastik", "Lastikor", 800),
    "P013": ("Lastikor İç Lastik", "Bileşen", "Lastik", "Lastikor", 180),
    "P014": ("Jantaş Alüminyum Jant Seti", "Bileşen", "Jant", "Jantaş", 5200),
    "P015": ("Zincirli Bisiklet Zinciri", "Bileşen", "Zincir", "Zincirli", 450),
    "P016": ("Konfora Jel Sele", "Bileşen", "Sele", "Konfora", 700),
    "P017": ("Gidonya Alüminyum Gidon", "Bileşen", "Gidon", "Gidonya", 1100),
    "P018": ("Pedalis Platform Pedal", "Bileşen", "Pedal", "Pedalis", 650),
    "P019": ("Kafatek Yol Kaskı", "Aksesuar", "Kask", "Kafatek", 1800),
    "P020": ("Kafatek Dağ Kaskı", "Aksesuar", "Kask", "Kafatek", 2100),
    "P021": ("Kilitrax U Kilit", "Aksesuar", "Kilit", "Kilitrax", 650),
    "P022": ("Kilitrax Zincirli Kilit", "Aksesuar", "Kilit", "Kilitrax", 480),
    "P023": ("Pompaş Ayak Pompası", "Aksesuar", "Pompa", "Pompaş", 420),
    "P024": ("Aydınlık Ön Far", "Aksesuar", "Aydınlatma", "Aydınlık", 380),
    "P025": ("Aydınlık Arka Stop", "Aksesuar", "Aydınlatma", "Aydınlık", 220),
    "P026": ("Yudumlux Suluk", "Aksesuar", "Suluk", "Yudumlux", 150),
    "P027": ("Sırtlan Bisiklet Çantası", "Aksesuar", "Çanta", "Sırtlan", 900),
    "P028": ("Sırtlan Bisiklet Eldiveni", "Aksesuar", "Eldiven", "Sırtlan", 550),
}
MAGAZALAR = {
    "S001": "İstanbul Kadıköy Mağazası", "S002": "İstanbul Beşiktaş Mağazası",
    "S003": "İstanbul Esenyurt Mağazası", "S004": "Ankara Çankaya Mağazası",
    "S005": "Ankara Keçiören Mağazası", "S006": "İzmir Karşıyaka Mağazası",
    "S007": "İzmir Bornova Mağazası", "S008": "Bursa Nilüfer Mağazası",
    "S009": "Antalya Muratpaşa Mağazası", "S010": "Adana Seyhan Mağazası",
    "S011": "Konya Selçuklu Mağazası", "S012": "Gaziantep Şahinbey Mağazası",
    "S013": "Samsun İlkadım Mağazası", "S014": "Trabzon Ortahisar Mağazası",
    "S900": "Dijital Kanal Deposu",
}
CITY_MAP = {
    "ISTANBUL": "İstanbul", "IST": "İstanbul", "ANKARA": "Ankara", "ANK": "Ankara",
    "IZMIR": "İzmir", "IZM": "İzmir", "BURSA": "Bursa", "ANTALYA": "Antalya", "ANT": "Antalya",
    "ADANA": "Adana", "KONYA": "Konya", "GAZIANTEP": "Gaziantep", "GANTEP": "Gaziantep",
    "ANTEP": "Gaziantep", "SAMSUN": "Samsun", "TRABZON": "Trabzon",
}
GENDER_MAP = {"E": "Erkek", "ERKEK": "Erkek", "M": "Erkek", "K": "Kadın", "KADIN": "Kadın", "F": "Kadın"}
PAY_MAP = {
    "KREDI KARTI": "Kredi Kartı", "KK": "Kredi Kartı", "KART": "Kredi Kartı",
    "NAKIT": "Nakit", "PESIN": "Nakit",
    "HAVALE/EFT": "Havale/EFT", "HAVALE": "Havale/EFT", "EFT": "Havale/EFT",
}
FIZIK_FOLD = str.maketrans("İıiŞşĞğÜüÖöÇç", "IIISSGGUUOOCC")

KURALLAR = {
    "DQ01": ("Tamlık", "Düzelt"), "DQ02": ("Tamlık", "Düzelt"), "DQ03": ("Tamlık", "Karantina"),
    "DQ04": ("Geçerlilik", "Karantina"), "DQ05": ("Geçerlilik", "NULL"), "DQ06": ("Geçerlilik", "Karantina"),
    "DQ07": ("Geçerlilik", "Karantina"), "DQ08": ("Geçerlilik", "Düzelt"), "DQ09": ("Geçerlilik", "Düzelt"),
    "DQ10": ("Geçerlilik", "Düzelt"), "DQ11": ("Tutarlılık", "Düzelt"), "DQ12": ("Tutarlılık", "Düzelt"),
    "DQ13": ("Tutarlılık", "Düzelt"), "DQ14": ("Tutarlılık", "Düzelt"), "DQ15": ("Tutarlılık", "Düzelt"),
    "DQ16": ("Tutarlılık", "Düzelt"), "DQ17": ("Benzersizlik", "Tekrar Elendi"),
    "DQ18": ("Bütünlük", "Karantina"), "DQ19": ("Bütünlük", "Düzelt"),
}
KARANTINA = [k for k, v in KURALLAR.items() if v[1] == "Karantina"]


def fold(s):
    return s.translate(FIZIK_FOLD).upper().replace(".", "").strip()


def tr_ci(s):
    return s.replace("İ", "i").replace("I", "ı").lower()


def parse_decimal(s):
    s = s.strip().replace(",", ".")
    try:
        return float(s) if s else None
    except ValueError:
        return None


def parse_int(s):
    try:
        return int(s.strip())
    except ValueError:
        return None


def parse_date(s):
    s = s.strip()
    try:
        if len(s) == 10 and s[4] == "-" and s[7] == "-":
            return pd.Timestamp(s)
        if len(s) == 10 and s[2] == "." and s[5] == ".":
            return pd.Timestamp(year=int(s[6:]), month=int(s[3:5]), day=int(s[:2]))
    except ValueError:
        return None
    return None


def normalize_customer(s):
    d = s.strip().replace("M", "").replace("m", "").replace("-", "")
    return "M" + d.zfill(5)[-5:] if d.isdigit() else None


def yukle(klasor, ilk_n=None):
    dosyalar = sorted(Path(klasor).glob("Satis_????_??.csv"))
    if ilk_n:
        dosyalar = dosyalar[:ilk_n]
    parcalar = []
    for f in dosyalar:
        d = pd.read_csv(f, dtype=str, keep_default_na=False, encoding="utf-8-sig")
        d["SourceFileName"] = f.name
        parcalar.append(d)
    df = pd.concat(parcalar, ignore_index=True)
    df.insert(0, "BronzeRowID", range(1, len(df) + 1))
    return df, [f.name for f in dosyalar]


def degerlendir(df):
    """Her Bronze satiri icin DQ bayraklari + temiz kolonlar (SQL: silver.vw_Sales_Stage)."""
    o = pd.DataFrame({"BronzeRowID": df.BronzeRowID, "SourceFileName": df.SourceFileName})
    t = lambda c: df[c].str.strip()

    o["KaynakAy"] = t("KaynakAy")
    o["SiparisID"] = t("SiparisID").map(parse_int)
    o["SiparisSatirID"] = t("SiparisSatirID").map(parse_int)
    o["Tarih"] = df.SiparisTarihi.map(parse_date)
    o["CustomerID"] = df.MusteriID.map(normalize_customer)
    name_t = t("MusteriAdi")
    qty = t("SiparisAdedi").map(parse_int)
    age = t("MusteriYas").map(parse_int)
    price = df.BirimFiyat.map(parse_decimal)
    disc = df.IndirimOrani.map(parse_decimal)

    # Altin musteri adi: ayni musterinin en sik (bos olmayan) adi, BIN2 (birebir) gruplama
    tmp = pd.DataFrame({"c": o.CustomerID, "n": name_t})
    tmp = tmp[tmp.n != ""]
    cnt = tmp.groupby(["c", "n"]).size().reset_index(name="k").sort_values(["c", "k", "n"], ascending=[True, False, True])
    golden = cnt.drop_duplicates("c").set_index("c")["n"]
    gold_name = o.CustomerID.map(golden)

    rp = df.UrunID.str.strip().map(lambda x: URUNLER.get(x))
    rs = df.MagazaID.str.strip().map(lambda x: MAGAZALAR.get(x))
    has_p = rp.notna()

    city_t = t("MusteriSehir")
    city_std = city_t.map(lambda x: CITY_MAP.get(fold(x)))
    gender_std = t("MusteriCinsiyet").map(lambda x: GENDER_MAP.get(fold(x)))
    pay_std = t("OdemeTipi").map(lambda x: PAY_MAP.get(fold(x)))
    kat_t, marka_t = t("UrunKategori"), t("UrunMarka")
    ws = lambda c: df[c].map(len) != df[c].str.strip().map(len)  # DATALENGTH karsilastirmasi

    f = pd.DataFrame(index=df.index)
    f["DQ01"] = name_t == ""
    f["DQ02"] = kat_t == ""
    f["DQ03"] = t("SiparisTarihi") == ""
    f["DQ04"] = qty.isna() | (qty <= 0)
    f["DQ05"] = age.isna() | (age < 18) | (age > 100)
    f["DQ06"] = [bool(p is not None and pr is not None and pr > 3 * p[4]) for p, pr in zip(rp, price)]
    f["DQ07"] = [bool(d is not None and not pd.isna(d) and (d.strftime("%Y-%m") != ka or d > pd.Timestamp.now()))
                 for d, ka in zip(o.Tarih, o.KaynakAy)]
    f["DQ08"] = disc.map(lambda x: x is not None and x > 1)
    f["DQ09"] = df.BirimFiyat.str.contains(",") | df.UrunMaliyeti.str.contains(",") | df.IndirimOrani.str.contains(",")
    f["DQ10"] = [bool(s.strip() != "" and not (len(s.strip()) == 10 and s.strip()[4] == "-" and s.strip()[7] == "-"))
                 for s in df.SiparisTarihi]
    f["DQ11"] = [bool(c != s) for c, s in zip(city_t, city_std)]
    gold_eq_ci = [bool(g is not None and not pd.isna(g) and n != "" and tr_ci(n) == tr_ci(g)) for n, g in zip(name_t, gold_name)]
    gold_eq_bin = [bool(g is not None and not pd.isna(g) and n == g) for n, g in zip(name_t, gold_name)]
    marka_ci = [bool(p is not None and tr_ci(m) == tr_ci(p[3]) and m != p[3]) for m, p in zip(marka_t, rp)]
    kat_ci = [bool(p is not None and k != "" and tr_ci(k) == tr_ci(p[1]) and k != p[1]) for k, p in zip(kat_t, rp)]
    f["DQ12"] = (ws("MusteriAdi") | ws("MusteriSehir") | ws("UrunAdi") | ws("MagazaAdi")
                 | pd.Series([a and not b for a, b in zip(gold_eq_ci, gold_eq_bin)], index=df.index)
                 | pd.Series(marka_ci, index=df.index) | pd.Series(kat_ci, index=df.index))
    f["DQ13"] = [bool(p is not None and k != "" and tr_ci(k) != tr_ci(p[1])) for k, p in zip(kat_t, rp)]
    f["DQ14"] = [bool(g != s) or bool(p != s2) for g, s, p, s2 in zip(t("MusteriCinsiyet"), gender_std, t("OdemeTipi"), pay_std)]
    f["DQ15"] = [bool(n != "" and g is not None and not pd.isna(g) and tr_ci(n) != tr_ci(g)) for n, g in zip(name_t, gold_name)]
    f["DQ16"] = [not (len(m) == 6 and m[0] == "M" and m[1:].isdigit() and m[1:].isascii()) for m in df.MusteriID]
    f["DQ17"] = pd.Series(list(zip(o.SiparisID, o.SiparisSatirID)), index=df.index).duplicated(keep="first")
    f["DQ18"] = ~has_p
    f["DQ19"] = [bool(s is not None and a.strip() != s) for a, s in zip(df.MagazaAdi, rs)]

    o = pd.concat([o, f], axis=1)
    return o, f


def rapor(klasor, kontrol, ilk_n):
    df, dosyalar = yukle(klasor, ilk_n)
    o, f = degerlendir(df)
    n = len(df)
    ihlal_var = f.any(axis=1)

    print(f"# Referans hesap: {klasor}")
    print(f"Dosya: {len(dosyalar)} ({dosyalar[0]} … {dosyalar[-1]}), Bronze satır: {n:,}")
    print(f"Benzersiz müşteri: {df.MusteriID.str.strip().map(normalize_customer).nunique():,}")

    print("\n## Dosya bazlı satır sayıları")
    print(df.groupby("SourceFileName").size().to_string())

    print("\n## Kural bazlı ihlal eden satır sayısı")
    kural = f.sum().astype(int)
    print(pd.DataFrame({"Boyut": [KURALLAR[k][0] for k in kural.index], "Aksiyon": [KURALLAR[k][1] for k in kural.index],
                        "Satir": kural.values}, index=kural.index).to_string())

    dup = f["DQ17"]
    karan = f[KARANTINA].any(axis=1) & ~dup
    silver = ~dup & ~karan
    print("\n## Özet")
    print(f"Bronze: {n:,} | ihlalli satır: {int(ihlal_var.sum()):,} | temiz satır: {int((~ihlal_var).sum()):,}")
    print(f"DQ Skoru: %{100 * (~ihlal_var).sum() / n:.2f}")
    print(f"Duplicate elenen: {int(dup.sum()):,} | karantina: {int(karan.sum()):,} | Silver: {int(silver.sum()):,} "
          f"(kabul %{100 * silver.sum() / n:.2f}, karantina %{100 * karan.sum() / n:.2f})")
    for boyut in ["Tamlık", "Geçerlilik", "Tutarlılık", "Benzersizlik", "Bütünlük"]:
        cols = [k for k, v in KURALLAR.items() if v[0] == boyut]
        print(f"Boyut skoru {boyut}: %{100 * (1 - f[cols].any(axis=1).sum() / n):.2f} (ihlalli satır {int(f[cols].any(axis=1).sum()):,})")

    print("\n## Silver tabloları için beklenen")
    s = o[silver]
    print(f"silver.Sales satır: {len(s):,}, benzersiz sipariş: {s.SiparisID.nunique():,}, benzersiz müşteri: {s.CustomerID.nunique():,}")
    print(f"Silver'da düzeltilen (IsCorrected) satır: {int(f.drop(columns=KARANTINA + ['DQ17'])[silver].any(axis=1).sum()):,}")
    sd = df[silver.values]
    print("Silver'da distinct (önce -> sonra): "
          f"şehir {df.MusteriSehir.str.rstrip(' ').nunique()} -> {sd.MusteriSehir.str.strip().map(lambda x: CITY_MAP.get(fold(x))).nunique()}, "
          f"cinsiyet {df.MusteriCinsiyet.nunique()} -> {sd.MusteriCinsiyet.str.strip().map(lambda x: GENDER_MAP.get(fold(x))).nunique()}, "
          f"ödeme {df.OdemeTipi.nunique()} -> {sd.OdemeTipi.str.strip().map(lambda x: PAY_MAP.get(fold(x))).nunique()}, "
          f"kategori {df.UrunKategori.nunique()} -> {sd.UrunID.str.strip().map(lambda x: URUNLER[x][1]).nunique()}, "
          f"müşteri adı {df.MusteriAdi.nunique()} -> {o[silver].CustomerID.nunique()} (müşteri başına tek ad)")
    print(f"Silver'da NULL yaş: {int((f['DQ05'] & silver).sum())}; yapısal hata (CustomerID/UyelikYili çözülemeyen): "
          f"{int(o[silver].CustomerID.isna().sum())}")

    print("\n## Profiling (Bronze, ham metin üzerinden)")
    prof = []
    for c in KOLONLAR:
        v = df[c]
        prof.append((c, n, int((v.str.strip() == "").sum()), v.str.rstrip(" ").nunique()))
    print("(DistinctCount: SQL'de BIN2 ile -> büyük/küçük harf ayrı, sondaki boşluk yok sayılır)")
    print(pd.DataFrame(prof, columns=["Kolon", "Kayit", "Bos", "Distinct"]).to_string(index=False))
    sayi = lambda c: df[c].map(parse_decimal)
    print(f"\nSayısal min/max: Adet {sayi('SiparisAdedi').min()}..{sayi('SiparisAdedi').max()}, "
          f"Fiyat {sayi('BirimFiyat').min()}..{sayi('BirimFiyat').max()}, Yaş {sayi('MusteriYas').min()}..{sayi('MusteriYas').max()}")
    print(f"Tarih biçimi ISO olmayan: {int(f['DQ10'].sum()):,}; Sayısal olmayan BirimFiyat (virgüllü): {int((df.BirimFiyat.str.contains(',')).sum()):,}")
    print(f"Şehir varyantı: distinct MusteriSehir = {df.MusteriSehir.nunique()} (standart 10)")
    print(f"Tam duplicate (25 kolon) satır: {int(df.duplicated(subset=KOLONLAR).sum()):,}")

    print("\n## bronze.vw_DirtyDataMetrics beklentisi (20_Profiling.sql ile aynı tanımlar)")
    tr = lambda c: df[c].str.strip()
    adet = tr("SiparisAdedi").map(parse_int)
    yas = tr("MusteriYas").map(parse_int)
    ind = pd.to_numeric(tr("IndirimOrani").str.replace(",", "x"), errors="coerce")  # virgüllü -> geçersiz (SQL TRY_CAST NULL)
    iso_re = r"\d{4}-\d{2}-\d{2}"
    tarih = tr("SiparisTarihi")
    standart = {"İstanbul", "Ankara", "İzmir", "Bursa", "Antalya", "Adana", "Konya", "Gaziantep", "Samsun", "Trabzon"}
    urun_no = tr("UrunID").str[1:].map(parse_int)
    metrik = [
        ("Boş müşteri adı", tr("MusteriAdi") == ""),
        ("Boş ürün kategorisi", tr("UrunKategori") == ""),
        ("Boş sipariş tarihi", tarih == ""),
        ("Adet sıfır/negatif", adet.isna() | (adet <= 0)),
        ("Yaş 18-100 dışında", yas.isna() | (yas < 18) | (yas > 100)),
        ("Virgüllü ondalık", df.BirimFiyat.str.contains(",") | df.UrunMaliyeti.str.contains(",") | df.IndirimOrani.str.contains(",")),
        ("Tarih ISO değil", (tarih != "") & ~tarih.str.fullmatch(iso_re)),
        ("İndirim >1", ind > 1),
        ("Tarih dosya ayı dışı", tarih.str.fullmatch(iso_re) & (tarih.str[:7] != tr("KaynakAy"))),
        ("MusteriID biçimi bozuk", ~df.MusteriID.str.fullmatch(r"M\d{5}")),
        ("UrunID katalog dışı", urun_no.isna() | (urun_no < 1) | (urun_no > 28)),
        ("Şehir standart dışı", ~df.MusteriSehir.str.rstrip(" ").isin(standart)),
        ("Tekrar satır", pd.Series(list(zip(df.SiparisID.str.strip(), df.SiparisSatirID.str.strip()))).duplicated()),
    ]
    for ad, seri in metrik:
        print(f"{ad:28s} {int(seri.sum()):>6,}  (%{100 * seri.sum() / n:.2f})")

    print("\n## SQL vw_DataProfiling 'tipli' min/max beklentisi (TRY_CAST DECIMAL; virgüllü değerler geçersiz sayılır)")
    for c in ["MusteriYas", "MusteriUyelikYili", "SiparisAdedi", "BirimFiyat", "UrunMaliyeti", "IndirimOrani"]:
        v = pd.to_numeric(df[c].str.strip().replace("", pd.NA), errors="coerce")
        gecersiz = int((df[c].str.strip().ne("") & v.isna()).sum())
        print(f"{c:18s} min={v.min()} max={v.max()} geçersiz_tip={gecersiz}")
    iso = df.SiparisTarihi.str.strip().str.fullmatch(r"\d{4}-\d{2}-\d{2}")
    gecerli = pd.to_datetime(df.SiparisTarihi.where(iso), errors="coerce")
    print(f"{'SiparisTarihi':18s} min={gecerli.min().date()} max={gecerli.max().date()} "
          f"geçersiz_tip={int((df.SiparisTarihi.str.strip().ne('') & gecerli.isna()).sum())}")

    gm = o.CustomerID.map(
        df.assign(c=o.CustomerID, n=df.MusteriAdi.str.strip()).query("n != ''")
          .groupby(["c", "n"]).size().reset_index(name="k").sort_values(["c", "k", "n"], ascending=[True, False, True])
          .drop_duplicates("c").set_index("c")["n"])
    if kontrol and (Path(kontrol) / "musteri_ana_veri.csv").exists():
        mv = pd.read_csv(Path(kontrol) / "musteri_ana_veri.csv", dtype=str, encoding="utf-8-sig").set_index("MusteriID")["MusteriAdi"]
        dogru = (gm == o.CustomerID.map(mv))
        print(f"\nAltın müşteri adı = ana veri adı: {int(dogru.sum()):,}/{len(dogru):,} satır "
              f"(yanlış: {int((~dogru).sum())})")

    if kontrol:
        logs = [pd.read_csv(p, dtype=str, keep_default_na=False, encoding="utf-8-sig")
                for p in sorted(Path(kontrol).glob("Satis_????_??_dq_log.csv")) if p.name.replace("_dq_log.csv", ".csv") in dosyalar]
        if logs:
            lg = pd.concat(logs)
            print(f"\n## Üretici logu ile karşılaştırma: logdaki kusurlu satır {len(lg):,} (kusur kodu bazında)")
            print(lg.KusurKodu.value_counts().sort_index().to_string())
    return o, f


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("klasor")
    ap.add_argument("--kontrol", default=None)
    ap.add_argument("--ilk-n-ay", type=int, default=None)
    a = ap.parse_args()
    rapor(a.klasor, a.kontrol, a.ilk_n_ay)
