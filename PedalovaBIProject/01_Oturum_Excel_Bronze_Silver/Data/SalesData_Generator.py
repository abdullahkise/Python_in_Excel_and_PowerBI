#!/usr/bin/env python3
"""
Pedalova Bisiklet A.S. - Satis Verisi Simulatoru (v2)

Aylik CSV dosyalari uretir (Satis_YYYY_MM.csv, UTF-8 BOM, 25 kolon).
Kasitli veri kusurlari eklenir; kusurlar egitmen icin ayri bir klasorde
(EgitmenKontrol) etiketli olarak saklanir. Bu klasor SalesRawData ICINE YAZILMAZ,
cunku Excel Power Query "Klasorden" baglantisi tum dosyalari okur.

Bagimlilik: yalnizca Python 3.9+ standart kutuphanesi.

Kullanim:
  python SalesData_Generator.py                      -> interaktif (Enter = varsayilan)
  python SalesData_Generator.py --ay-sayisi 3        -> argumanlarla
  python SalesData_Generator.py --yardim-ornek       -> ornek komutlari goster
"""

import argparse
import calendar
import csv
import math
import random
import sys
import time
from collections import Counter
from datetime import date, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KOLONLAR = [
    "KaynakAy", "SiparisID", "SiparisSatirID", "SiparisTarihi", "MusteriID",
    "MusteriAdi", "MusteriCinsiyet", "MusteriYas", "MusteriUyelikYili",
    "MusteriSehir", "MagazaID", "MagazaAdi", "MagazaBolge", "SatisKanali",
    "UrunID", "UrunAdi", "UrunKategori", "UrunAltKategori", "UrunMarka",
    "SiparisAdedi", "BirimFiyat", "UrunMaliyeti", "IndirimOrani",
    "KampanyaAdi", "OdemeTipi",
]

# ==================================================
# REFERANS VERI
# ==================================================

# sehir: (bolge, musteri dagilim agirligi)
SEHIRLER = {
    "İstanbul": ("Marmara", 30),
    "Ankara": ("İç Anadolu", 14),
    "İzmir": ("Ege", 12),
    "Bursa": ("Marmara", 9),
    "Antalya": ("Akdeniz", 8),
    "Adana": ("Akdeniz", 6),
    "Konya": ("İç Anadolu", 6),
    "Gaziantep": ("Güneydoğu Anadolu", 5),
    "Samsun": ("Karadeniz", 5),
    "Trabzon": ("Karadeniz", 5),
}

# Fiziksel magazalar: (MagazaID, MagazaAdi, Sehir)
MAGAZALAR = [
    ("S001", "İstanbul Kadıköy Mağazası", "İstanbul"),
    ("S002", "İstanbul Beşiktaş Mağazası", "İstanbul"),
    ("S003", "İstanbul Esenyurt Mağazası", "İstanbul"),
    ("S004", "Ankara Çankaya Mağazası", "Ankara"),
    ("S005", "Ankara Keçiören Mağazası", "Ankara"),
    ("S006", "İzmir Karşıyaka Mağazası", "İzmir"),
    ("S007", "İzmir Bornova Mağazası", "İzmir"),
    ("S008", "Bursa Nilüfer Mağazası", "Bursa"),
    ("S009", "Antalya Muratpaşa Mağazası", "Antalya"),
    ("S010", "Adana Seyhan Mağazası", "Adana"),
    ("S011", "Konya Selçuklu Mağazası", "Konya"),
    ("S012", "Gaziantep Şahinbey Mağazası", "Gaziantep"),
    ("S013", "Samsun İlkadım Mağazası", "Samsun"),
    ("S014", "Trabzon Ortahisar Mağazası", "Trabzon"),
]
DIJITAL_MAGAZA = ("S900", "Dijital Kanal Deposu", "Dijital")  # web + mobil siparisleri

KAMPANYALAR = {
    1: "Yılbaşı Kampanyası",
    3: "Ramazan Kampanyası",
    4: "Ramazan Kampanyası",
    6: "Kurban Bayramı Kampanyası",
    7: "Yaz Kampanyası",
    8: "Yaz Kampanyası",
    9: "Okula Dönüş Kampanyası",
    11: "Kasım Kampanyası",
    12: "Yılbaşı Kampanyası",
}
KAMPANYA_YOK = "Kampanya Yok"
# KampanyaAdi: (KampanyaTuru, Sezon)
KAMPANYA_META = {
    "Yılbaşı Kampanyası": ("Yılbaşı", "Kış"),
    "Ramazan Kampanyası": ("Dini Bayram", "İlkbahar"),
    "Kurban Bayramı Kampanyası": ("Dini Bayram", "Yaz"),
    "Yaz Kampanyası": ("Mevsimsel", "Yaz"),
    "Okula Dönüş Kampanyası": ("Mevsimsel", "Sonbahar"),
    "Kasım Kampanyası": ("Alışveriş Festivali", "Sonbahar"),
    KAMPANYA_YOK: ("Yok", "Tüm Yıl"),
}

SEZON_ORANI = {1: .75, 2: .80, 3: 1.05, 4: 1.25, 5: 1.40, 6: 1.35,
               7: 1.20, 8: 1.05, 9: 1.00, 10: .85, 11: 1.20, 12: 1.00}
BISIKLET_SEZON = {1: .6, 2: .65, 3: 1.0, 4: 1.3, 5: 1.5, 6: 1.4,
                  7: 1.2, 8: 1.0, 9: .9, 10: .7, 11: .9, 12: .8}
KAMPANYA_SIPARIS_CARPANI = 1.15

# (UrunID, UrunAdi, Kategori, AltKategori, Marka, BazFiyat(TL, baslangic ayi), MaliyetOrani)
URUNLER = [
    ("P001", "Zirvex Dağ Bisikleti 29", "Bisiklet", "Dağ Bisikleti", "Zirvex", 18500, .68),
    ("P002", "Rotalux Yol Bisikleti Karbon", "Bisiklet", "Yol Bisikleti", "Rotalux", 26000, .70),
    ("P003", "Urbanta Şehir Bisikleti", "Bisiklet", "Şehir Bisikleti", "Urbanta", 12500, .66),
    ("P004", "Voltrik Elektrikli Şehir Bisikleti", "Bisiklet", "Elektrikli Bisiklet", "Voltrik", 48000, .74),
    ("P005", "Urbanta Katlanır Bisiklet", "Bisiklet", "Şehir Bisikleti", "Urbanta", 15500, .67),
    ("P006", "Voltrik Elektrikli Dağ Bisikleti", "Bisiklet", "Elektrikli Bisiklet", "Voltrik", 62000, .75),
    ("P007", "Torkpro Vites Seti 2x11", "Bileşen", "Vites", "Torkpro", 4200, .62),
    ("P008", "Torkpro Arka Aktarıcı", "Bileşen", "Vites", "Torkpro", 1900, .60),
    ("P009", "Frenix Disk Fren Seti", "Bileşen", "Fren", "Frenix", 2600, .60),
    ("P010", "Frenix Fren Balatası", "Bileşen", "Fren", "Frenix", 350, .52),
    ("P011", "Lastikor Dağ Lastiği", "Bileşen", "Lastik", "Lastikor", 900, .58),
    ("P012", "Lastikor Yol Lastiği", "Bileşen", "Lastik", "Lastikor", 800, .58),
    ("P013", "Lastikor İç Lastik", "Bileşen", "Lastik", "Lastikor", 180, .50),
    ("P014", "Jantaş Alüminyum Jant Seti", "Bileşen", "Jant", "Jantaş", 5200, .63),
    ("P015", "Zincirli Bisiklet Zinciri", "Bileşen", "Zincir", "Zincirli", 450, .55),
    ("P016", "Konfora Jel Sele", "Bileşen", "Sele", "Konfora", 700, .55),
    ("P017", "Gidonya Alüminyum Gidon", "Bileşen", "Gidon", "Gidonya", 1100, .58),
    ("P018", "Pedalis Platform Pedal", "Bileşen", "Pedal", "Pedalis", 650, .56),
    ("P019", "Kafatek Yol Kaskı", "Aksesuar", "Kask", "Kafatek", 1800, .55),
    ("P020", "Kafatek Dağ Kaskı", "Aksesuar", "Kask", "Kafatek", 2100, .55),
    ("P021", "Kilitrax U Kilit", "Aksesuar", "Kilit", "Kilitrax", 650, .50),
    ("P022", "Kilitrax Zincirli Kilit", "Aksesuar", "Kilit", "Kilitrax", 480, .50),
    ("P023", "Pompaş Ayak Pompası", "Aksesuar", "Pompa", "Pompaş", 420, .52),
    ("P024", "Aydınlık Ön Far", "Aksesuar", "Aydınlatma", "Aydınlık", 380, .50),
    ("P025", "Aydınlık Arka Stop", "Aksesuar", "Aydınlatma", "Aydınlık", 220, .48),
    ("P026", "Yudumlux Suluk", "Aksesuar", "Suluk", "Yudumlux", 150, .45),
    ("P027", "Sırtlan Bisiklet Çantası", "Aksesuar", "Çanta", "Sırtlan", 900, .54),
    ("P028", "Sırtlan Bisiklet Eldiveni", "Aksesuar", "Eldiven", "Sırtlan", 550, .52),
]
URUN = {u[0]: u for u in URUNLER}
BISIKLETLER = ["P001", "P002", "P003", "P004", "P005", "P006"]
DAG_BISIKLETLERI = {"P001", "P006"}

# Birlikte satis kaliplari (NetworkX icin). comp: (urun | grup, olasilik)
ARKETIPLER = {
    "bisiklet": {"anchor": None, "comp": [("KASK", .70), ("P021", .55), ("P024", .40),
                                          ("P025", .35), ("P026", .30), ("P023", .25)]},
    "lastik": {"anchor": [("P011", 1), ("P012", 1)], "comp": [("P013", .85), ("P023", .50)]},
    "fren": {"anchor": [("P009", 1), ("P010", 1.4)], "comp": [("P009", .30), ("P010", .45), ("P015", .12)]},
    "vites": {"anchor": [("P007", 1), ("P008", 1)], "comp": [("P015", .65), ("P008", .40), ("P007", .25)]},
    "yukseltme": {"anchor": [("P014", 1)], "comp": [("LASTIK", .60), ("P013", .80), ("P009", .20)]},
    "sehir_paketi": {"anchor": [("KASK", 1)], "comp": [("P021", .75), ("P024", .70), ("P025", .60), ("P022", .20)]},
    "yol_kiti": {"anchor": [("P026", 1.2), ("P028", 1), ("P027", .7), ("P023", .7)],
                 "comp": [("P026", .40), ("P028", .40), ("P027", .25), ("P023", .30), ("P013", .20)]},
    "konfor": {"anchor": [("P016", 1), ("P017", 1), ("P018", 1)],
               "comp": [("P016", .30), ("P017", .30), ("P018", .35)]},
}
ARKETIP_SIRASI = list(ARKETIPLER)
RASTGELE_EK_URUN_OLASILIGI = .12

# Musteri davranis gruplari (gizli): oran, siparis sikligi, kampanya ayinda/disinda agirlik, arketip agirliklari
SEGMENTLER = {
    "Düzenli Orta": dict(oran=.40, siklik=1.0, kamp=1.1, normal=1.0,
                         arketip=[.14, .14, .10, .12, .06, .16, .18, .10]),
    "Sık Küçük Alıcı": dict(oran=.25, siklik=2.5, kamp=1.0, normal=1.0,
                            arketip=[.02, .18, .12, .10, .02, .18, .30, .08]),
    "Nadir Büyük Sepet": dict(oran=.20, siklik=.35, kamp=1.0, normal=1.0,
                              arketip=[.55, .05, .05, .08, .15, .06, .02, .04]),
    "Kampanya Avcısı": dict(oran=.15, siklik=.55, kamp=1.5, normal=.1,
                            arketip=[.25, .10, .06, .08, .14, .12, .15, .10]),
}
INDIRIMLER = [0, .05, .10, .15, .20]
INDIRIM_AGIRLIK = {
    ("normal", False): [70, 15, 10, 4, 1],
    ("normal", True): [35, 20, 22, 15, 8],
    ("avci", False): [45, 20, 20, 10, 5],
    ("avci", True): [8, 15, 27, 30, 20],
}

ERKEK_AD = ["Ahmet", "Mehmet", "Ali", "Mustafa", "Murat", "Kemal", "Engin", "Hasan",
            "Emre", "Burak", "Serkan", "Volkan", "Onur", "Tolga", "Cem", "Barış"]
KADIN_AD = ["Ayşe", "Fatma", "Zeynep", "Elif", "Merve", "Esra", "Selin", "Cansu",
            "Derya", "Burcu", "Gizem", "Pınar", "Seda", "Ebru", "Naz", "Dilara"]
SOYAD = ["Yılmaz", "Kaya", "Demir", "Şahin", "Çelik", "Koç", "Aydın", "Öztürk",
         "Arslan", "Doğan", "Kılıç", "Aksoy", "Polat", "Erdem", "Güneş", "Tekin"]

SEHIR_VARYANTLARI = {
    "İstanbul": ["İSTANBUL", "istanbul", "İst.", "Istanbul", "ISTANBUL"],
    "Ankara": ["ANKARA", "ankara", "Ank."],
    "İzmir": ["İZMİR", "izmir", "Izmir", "İzm."],
    "Bursa": ["BURSA", "bursa"],
    "Antalya": ["ANTALYA", "antalya", "Ant."],
    "Adana": ["ADANA", "adana"],
    "Konya": ["KONYA", "konya"],
    "Gaziantep": ["GAZİANTEP", "gaziantep", "G.Antep", "Antep"],
    "Samsun": ["SAMSUN", "samsun"],
    "Trabzon": ["TRABZON", "trabzon"],
}
KATEGORI_YAZIM = {
    "Bisiklet": ["Bisiklt", "Bisklet", "Bisiklet."],
    "Bileşen": ["Bilesen", "Bileşn"],
    "Aksesuar": ["Aksesuvar", "Aksesuarr", "Aksesur"],
}
CINSIYET_VARYANT = {
    "Erkek": ["E", "erkek", "ERKEK", "M"],
    "Kadın": ["K", "kadın", "KADIN", "Kadin", "F"],
}
ODEME_VARYANT = {
    "Kredi Kartı": ["kredi kartı", "KK", "Kredi Karti", "Kart"],
    "Nakit": ["nakit", "NAKİT", "Peşin"],
    "Havale/EFT": ["Havale", "EFT", "havale/eft"],
}

# Kusur kodu: (aile, agirlik)
KUSURLAR = {
    "T01": ("Metin", 8), "T02": ("Metin", 7), "T03": ("Metin", 9), "T04": ("Metin", 4),
    "T05": ("Metin", 4), "T06": ("Metin", 4), "T07": ("Metin", 4), "T08": ("Metin", 5),
    "T09": ("Metin", 4),
    "N01": ("Sayısal", 6), "N02": ("Sayısal", 4), "N03": ("Sayısal", 4), "N04": ("Sayısal", 5),
    "D01": ("Tarih", 3), "D02": ("Tarih", 6), "D03": ("Tarih", 3),
    "K01": ("Kimlik", 0), "K02": ("Kimlik", 5), "K03": ("Kimlik", 3), "K04": ("Kimlik", 4),
    "Y01": ("Yaş", 5),
}
KUSUR_KODLARI = [k for k, v in KUSURLAR.items() if v[1] > 0]
KUSUR_AGIRLIKLARI = [KUSURLAR[k][1] for k in KUSUR_KODLARI]


# ==================================================
# YARDIMCILAR
# ==================================================

def tr_upper(s):
    return s.replace("i", "İ").replace("ı", "I").upper()


def tr_lower(s):
    return s.replace("İ", "i").replace("I", "ı").lower()


def agirlikli(rng, secenekler):
    return rng.choices([s[0] for s in secenekler], weights=[s[1] for s in secenekler])[0]


def sigmoid(x):
    return 1 / (1 + math.exp(-x))


def bisiklet_agirliklari(yas):
    s = sigmoid((yas - 42) / 5)
    return [("P001", 1.6 - 1.2 * s), ("P002", .5 + 1.0 * s), ("P003", 1.2 - .8 * s),
            ("P004", .10 + 2.4 * s), ("P005", .6 - .3 * s), ("P006", .05 + 1.2 * s)]


def fiyat_tablosu(enflasyon, ay_sayisi):
    """Urun x ay icin sabit fiyat/maliyet (satir ici rastgelelik yok)."""
    tablo = {}
    for i in range(ay_sayisi):
        carpan = (1 + enflasyon) ** i
        for pid, _, _, _, _, baz, oran in URUNLER:
            ham = baz * carpan
            adim = 10 if ham >= 1000 else 5
            fiyat = int(round(ham / adim) * adim)
            tablo[(pid, i)] = (fiyat, round(fiyat * oran, 2))
    return tablo


def musteri_havuzu(rng, adet, baslangic_yili, bitis_yili):
    sehirler = list(SEHIRLER)
    sehir_agirlik = [SEHIRLER[s][1] for s in sehirler]
    seg_adlari = list(SEGMENTLER)
    seg_oranlari = [SEGMENTLER[s]["oran"] for s in seg_adlari]
    havuz = []
    for i in range(1, adet + 1):
        cinsiyet = rng.choice(["Kadın", "Erkek"])
        ad = rng.choice(KADIN_AD if cinsiyet == "Kadın" else ERKEK_AD)
        yas0 = int(min(70, max(18, rng.gauss(38, 11))))
        dogum = baslangic_yili - yas0
        if rng.random() < .60:
            uyelik = rng.randint(max(2015, baslangic_yili - 6), baslangic_yili - 1)
        else:
            uyelik = rng.choices(range(baslangic_yili, bitis_yili + 1),
                                 weights=[1 / (k + 1) for k in range(bitis_yili - baslangic_yili + 1)])[0]
        uyelik = max(uyelik, dogum + 18)
        havuz.append({
            "id": f"M{i:05d}",
            "ad": f"{ad} {rng.choice(SOYAD)}",
            "cinsiyet": cinsiyet,
            "dogum": dogum,
            "uyelik": uyelik,
            "sehir": rng.choices(sehirler, weights=sehir_agirlik)[0],
            "segment": rng.choices(seg_adlari, weights=seg_oranlari)[0],
        })
    return havuz


def kanal_sec(rng, yas, segment):
    if segment == "Kampanya Avcısı":
        w = [.25, .50, .25]
    elif yas < 30:
        w = [.35, .30, .35]
    elif yas >= 50:
        w = [.65, .25, .10]
    else:
        w = [.50, .30, .20]
    return rng.choices(["Mağaza", "Web", "Mobil"], weights=w)[0]


def odeme_sec(rng, kanal):
    if kanal == "Mağaza":
        return agirlikli(rng, [("Kredi Kartı", .60), ("Nakit", .30), ("Havale/EFT", .10)])
    return agirlikli(rng, [("Kredi Kartı", .75), ("Havale/EFT", .25)])


def sepet_urunleri(rng, musteri, yas, ay):
    seg = SEGMENTLER[musteri["segment"]]
    agirliklar = list(seg["arketip"])
    agirliklar[0] *= BISIKLET_SEZON[ay]
    ad = rng.choices(ARKETIP_SIRASI, weights=agirliklar)[0]
    ark = ARKETIPLER[ad]

    if ad == "bisiklet":
        anchor = agirlikli(rng, bisiklet_agirliklari(yas))
    else:
        anchor = agirlikli(rng, ark["anchor"])
    urunler = []

    def coz(ref, bisiklet=None):
        if ref == "KASK":
            return "P020" if bisiklet in DAG_BISIKLETLERI else rng.choice(["P019", "P020"])
        if ref == "LASTIK":
            return rng.choice(["P011", "P012"])
        return ref

    anchor = coz(anchor, None)
    urunler.append(anchor)
    for ref, p in ark["comp"]:
        if rng.random() < p:
            pid = coz(ref, anchor if ad == "bisiklet" else None)
            if pid not in urunler:
                urunler.append(pid)
    if rng.random() < RASTGELE_EK_URUN_OLASILIGI:
        pid = rng.choice(URUNLER)[0]
        if pid not in urunler:
            urunler.append(pid)
    return urunler[:6]


def adet_sec(rng, pid, indirim):
    if pid in BISIKLETLER:
        return 2 if rng.random() < .04 else 1
    adet = 1
    p_ek = .12 + 1.8 * indirim
    while adet < 6 and rng.random() < p_ek:
        adet += 1
    return adet


# ==================================================
# KUSUR ENJEKSIYONU
# ==================================================

def kusur_uygula(rng, kod, satir, ctx):
    """Satiri yerinde bozar; (alan, orijinal, bozuk) doner. Uygulanamazsa None."""
    def degistir(alan, yeni):
        eski = satir[alan]
        satir[alan] = yeni
        return alan, eski, yeni

    if kod == "T01":
        alan = rng.choice(["MusteriAdi", "MusteriSehir", "UrunAdi", "MagazaAdi"])
        v = str(satir[alan])
        return degistir(alan, rng.choice([" " + v, v + " ", "  " + v + " "]))
    if kod == "T02":
        alan = rng.choice(["MusteriAdi", "UrunMarka", "UrunKategori"])
        v = str(satir[alan])
        return degistir(alan, tr_lower(v) if alan == "UrunMarka" else tr_upper(v))
    if kod == "T03":
        return degistir("MusteriSehir", rng.choice(SEHIR_VARYANTLARI[satir["MusteriSehir"]]))
    if kod == "T04":
        return degistir("UrunKategori", "")
    if kod == "T05":
        return degistir("UrunKategori", rng.choice(KATEGORI_YAZIM[satir["UrunKategori"]]))
    if kod == "T06":
        return degistir("MusteriAdi", "")
    if kod == "T07":
        ad, soyad = satir["MusteriAdi"].split(" ", 1)
        return degistir("MusteriAdi", rng.choice([f"{soyad} {ad}", f"{soyad}, {ad}"]))
    if kod == "T08":
        return degistir("MusteriCinsiyet", rng.choice(CINSIYET_VARYANT[satir["MusteriCinsiyet"]]))
    if kod == "T09":
        return degistir("OdemeTipi", rng.choice(ODEME_VARYANT[satir["OdemeTipi"]]))
    if kod == "N01":
        return degistir("SiparisAdedi", rng.choice([-1, -2, 0, 0, -1]))
    if kod == "N02":
        return degistir("BirimFiyat", int(satir["BirimFiyat"] * rng.choice([20, 50, 100])))
    if kod == "N03":
        if satir["IndirimOrani"] <= 0:
            return None
        return degistir("IndirimOrani", int(round(satir["IndirimOrani"] * 100)))
    if kod == "N04":
        alan = rng.choice(["UrunMaliyeti", "BirimFiyat"])
        return degistir(alan, f"{float(satir[alan]):.2f}".replace(".", ","))
    if kod == "D01":
        gelecek = ctx["tarih"] + timedelta(days=rng.randint(400, 2000))
        return degistir("SiparisTarihi", gelecek.isoformat())
    if kod == "D02":
        return degistir("SiparisTarihi", ctx["tarih"].strftime("%d.%m.%Y"))
    if kod == "D03":
        return degistir("SiparisTarihi", "")
    if kod == "K02":
        sayi = int(satir["MusteriID"][1:])
        return degistir("MusteriID", rng.choice([f"m{sayi:05d}", f"M-{sayi:05d}", f"M{sayi}"]))
    if kod == "K03":
        return degistir("UrunID", f"P{rng.randint(900, 999)}")
    if kod == "K04":
        digerleri = [m[1] for m in MAGAZALAR + [DIJITAL_MAGAZA] if m[1] != satir["MagazaAdi"]]
        return degistir("MagazaAdi", rng.choice(digerleri))
    if kod == "Y01":
        return degistir("MusteriYas", rng.choice([5, 12, 17, 101, 120, 150]))
    return None


# ==================================================
# URETIM
# ==================================================

def uret(a):
    rng = random.Random(a.seed)
    cikis = Path(a.cikis).resolve()
    kontrol = Path(a.kontrol_klasoru).resolve() if a.kontrol_klasoru else cikis.parent / "EgitmenKontrol"
    cikis.mkdir(parents=True, exist_ok=True)
    kontrol.mkdir(parents=True, exist_ok=True)

    if a.temizle:
        for eski in list(cikis.glob("Satis_????_??.csv")) + list(kontrol.glob("Satis_????_??_dq_log.csv")):
            eski.unlink()

    enflasyon = a.enflasyon / 100
    buyume = a.buyume / 100
    dq_orani = a.dq_hata_orani / 100
    dup_orani = a.duplicate_orani / 100
    bitis_toplam = (a.baslangic_ay - 1) + a.ay_sayisi - 1
    bitis_yili = a.baslangic_yili + bitis_toplam // 12

    fiyatlar = fiyat_tablosu(enflasyon, a.ay_sayisi)
    musteriler = musteri_havuzu(rng, a.musteri_sayisi, a.baslangic_yili, bitis_yili)
    magaza_sehir = {}
    for m in MAGAZALAR:
        magaza_sehir.setdefault(m[2], []).append(m)

    uretilen = []
    toplam_kusur = Counter()
    ozet_satirlari = []

    for i in range(a.ay_sayisi):
        toplam = (a.baslangic_ay - 1) + i
        yil, ay = a.baslangic_yili + toplam // 12, toplam % 12 + 1
        kampanya = KAMPANYALAR.get(ay, KAMPANYA_YOK)
        kampanyali = kampanya != KAMPANYA_YOK
        gun_sayisi = calendar.monthrange(yil, ay)[1]
        gun_agirlik = [1.4 if date(yil, ay, g).weekday() >= 5 else 1.0 for g in range(1, gun_sayisi + 1)]

        n_siparis = round(a.aylik_siparis * SEZON_ORANI[ay] * (1 + buyume) ** (i / 12)
                          * (KAMPANYA_SIPARIS_CARPANI if kampanyali else 1.0) * rng.uniform(.97, 1.03))
        if n_siparis >= 100000:
            sys.exit("Hata: ay basina sipariş sayısı 100.000'i aşamaz (SiparisID aralığı).")
        siparis_taban = (i + 1) * 100000

        agirliklar = []
        for c in musteriler:
            seg = SEGMENTLER[c["segment"]]
            w = seg["siklik"] * (seg["kamp"] if kampanyali else seg["normal"])
            agirliklar.append(w if yil >= c["uyelik"] else 0.0)
        kum, t = [], 0.0
        for w in agirliklar:
            t += w
            kum.append(t)

        satirlar, log = [], []
        siparis_sayisi_ay = 0
        kaynak_ay = f"{yil}-{ay:02d}"
        dosya = f"Satis_{yil}_{ay:02d}.csv"

        for s in range(n_siparis):
            siparis_id = siparis_taban + s
            c = musteriler[rng.choices(range(len(musteriler)), cum_weights=kum)[0]]
            yas = yil - c["dogum"]
            tarih = date(yil, ay, rng.choices(range(1, gun_sayisi + 1), weights=gun_agirlik)[0])
            kanal = kanal_sec(rng, yas, c["segment"])
            if kanal == "Mağaza":
                magaza = rng.choice(magaza_sehir[c["sehir"]])
                bolge = SEHIRLER[c["sehir"]][0]
            else:
                magaza, bolge = DIJITAL_MAGAZA, "Dijital"
            odeme = odeme_sec(rng, kanal)
            avci = "avci" if c["segment"] == "Kampanya Avcısı" else "normal"

            for satir_id, pid in enumerate(sepet_urunleri(rng, c, yas, ay), start=1):
                urun = URUN[pid]
                fiyat, maliyet = fiyatlar[(pid, i)]
                indirim = rng.choices(INDIRIMLER, weights=INDIRIM_AGIRLIK[(avci, kampanyali)])[0]
                satir = {
                    "KaynakAy": kaynak_ay, "SiparisID": siparis_id, "SiparisSatirID": satir_id,
                    "SiparisTarihi": tarih.isoformat(), "MusteriID": c["id"], "MusteriAdi": c["ad"],
                    "MusteriCinsiyet": c["cinsiyet"], "MusteriYas": yas, "MusteriUyelikYili": c["uyelik"],
                    "MusteriSehir": c["sehir"], "MagazaID": magaza[0], "MagazaAdi": magaza[1],
                    "MagazaBolge": bolge, "SatisKanali": kanal, "UrunID": pid, "UrunAdi": urun[1],
                    "UrunKategori": urun[2], "UrunAltKategori": urun[3], "UrunMarka": urun[4],
                    "SiparisAdedi": adet_sec(rng, pid, indirim), "BirimFiyat": fiyat,
                    "UrunMaliyeti": maliyet, "IndirimOrani": indirim, "KampanyaAdi": kampanya,
                    "OdemeTipi": odeme,
                }

                if rng.random() < dq_orani:
                    for _ in range(10):
                        kod = rng.choices(KUSUR_KODLARI, weights=KUSUR_AGIRLIKLARI)[0]
                        sonuc = kusur_uygula(rng, kod, satir, {"tarih": tarih})
                        if sonuc:
                            satirlar.append(satir)
                            log.append((len(satirlar), siparis_id, satir_id, kod, *sonuc))
                            break
                    else:
                        satirlar.append(satir)
                else:
                    satirlar.append(satir)

                if rng.random() < dup_orani:
                    satirlar.append(dict(satir))
                    log.append((len(satirlar), siparis_id, satir_id, "K01", "(tüm satır)", "", ""))
            siparis_sayisi_ay += 1

        with open(cikis / dosya, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=KOLONLAR)
            w.writeheader()
            w.writerows(satirlar)

        with open(kontrol / dosya.replace(".csv", "_dq_log.csv"), "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["Dosya", "SatirNo", "SiparisID", "SiparisSatirID", "KusurKodu", "KusurAilesi",
                        "Alan", "OrijinalDeger", "BozukDeger"])
            for satir_no, sid, slid, kod, alan, eski, yeni in log:
                w.writerow([dosya, satir_no, sid, slid, kod, KUSURLAR[kod][0], alan, eski, yeni])

        kusur_ay = Counter(k[3] for k in log)
        toplam_kusur.update(kusur_ay)
        ozet_satirlari.append([dosya, kaynak_ay, kampanya, siparis_sayisi_ay, len(satirlar), len(log),
                               kusur_ay.get("K01", 0)])
        uretilen.append(dosya)
        print(f"{dosya} oluşturuldu ({len(satirlar):,} satır, {siparis_sayisi_ay:,} sipariş, "
              f"{len(log):,} kusurlu satır)")
        if a.bekleme > 0 and i < a.ay_sayisi - 1:
            time.sleep(a.bekleme)

    kalan = sorted(set(p.name for p in cikis.glob("Satis_????_??.csv")) - set(uretilen))
    if kalan:
        print(f"\nUYARI: Çıkış klasöründe bu çalıştırmada üretilmeyen eski dosyalar var: {', '.join(kalan)}"
              "\n       (--temizle ile önce silebilirsin)")

    yaz_kontrol_dosyalari(kontrol, musteriler, ozet_satirlari, toplam_kusur, a)
    top_satir = sum(r[4] for r in ozet_satirlari)
    top_kusur = sum(r[5] for r in ozet_satirlari)
    print(f"\nToplam {top_satir:,} satır; kusurlu satır {top_kusur:,} (%{100 * top_kusur / top_satir:.2f}). "
          f"Eğitmen kontrol dosyaları: {kontrol}")
    print("Tüm dosyalar üretildi.")


def yaz_kontrol_dosyalari(kontrol, musteriler, ozet, kusur_toplam, a):
    def yaz(ad, baslik, satirlar):
        with open(kontrol / ad, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(baslik)
            w.writerows(satirlar)

    yaz("musteri_ana_veri.csv",
        ["MusteriID", "MusteriAdi", "Cinsiyet", "DogumYili", "UyelikYili", "Sehir", "GizliSegment"],
        [[c["id"], c["ad"], c["cinsiyet"], c["dogum"], c["uyelik"], c["sehir"], c["segment"]] for c in musteriler])
    yaz("urun_katalogu.csv",
        ["UrunID", "UrunAdi", "Kategori", "AltKategori", "Marka", "BazFiyat", "MaliyetOrani"],
        [list(u) for u in URUNLER])
    yaz("magaza_ana_veri.csv", ["MagazaID", "MagazaAdi", "Sehir", "Bolge", "MagazaTuru"],
        [[m[0], m[1], m[2], SEHIRLER[m[2]][0], "Fiziksel"] for m in MAGAZALAR]
        + [[DIJITAL_MAGAZA[0], DIJITAL_MAGAZA[1], "İstanbul", "Dijital", "Dijital"]])
    yaz("kampanya_takvimi.csv", ["Ay", "KampanyaAdi", "KampanyaTuru", "Sezon"],
        [[ay, KAMPANYALAR.get(ay, KAMPANYA_YOK), *KAMPANYA_META[KAMPANYALAR.get(ay, KAMPANYA_YOK)]]
         for ay in range(1, 13)])
    yaz("uretim_ozeti.csv",
        ["Dosya", "KaynakAy", "KampanyaAdi", "SiparisSayisi", "SatirSayisi", "KusurluSatir", "DuplicateSatir"],
        ozet)
    yaz("kusur_ozeti.csv", ["KusurKodu", "KusurAilesi", "SatirSayisi"],
        [[k, KUSURLAR[k][0], kusur_toplam.get(k, 0)] for k in KUSURLAR])
    parametreler = {k: v for k, v in vars(a).items()}
    yaz("parametreler.csv", ["Parametre", "Deger"], [[k, v] for k, v in parametreler.items()])


# ==================================================
# CLI
# ==================================================

VARSAYILANLAR = [
    # (arguman, tip, varsayilan, interaktif soru)
    ("baslangic_yili", int, 2023, "Başlangıç yılı"),
    ("baslangic_ay", int, 1, "Başlangıç ayı (1-12)"),
    ("ay_sayisi", int, 24, "Kaç aylık veri üretilecek (12'yi aşarsa yıl devreder)"),
    ("aylik_siparis", int, 2000, "Ay başına ortalama sipariş sayısı"),
    ("musteri_sayisi", int, 3000, "Müşteri havuzu büyüklüğü"),
    ("dq_hata_orani", float, 4.0, "Veri kalitesi hata oranı (% satır)"),
    ("duplicate_orani", float, 1.0, "Duplicate oranı (% satır)"),
    ("enflasyon", float, 1.2, "Aylık fiyat artışı (%)"),
    ("buyume", float, 12.0, "Yıllık sipariş büyümesi (%)"),
    ("bekleme", float, 0.0, "Dosyalar arası bekleme (sn)"),
    ("seed", int, 42, "Rastgelelik tohumu (seed)"),
]


def argumanlari_al():
    varsayilan_cikis = str(Path(__file__).resolve().parent / "SalesRawData")
    p = argparse.ArgumentParser(description="Pedalova Bisiklet A.Ş. satış verisi simülatörü")
    for ad, tip, varsayilan, _ in VARSAYILANLAR:
        p.add_argument("--" + ad.replace("_", "-"), dest=ad, type=tip, default=varsayilan)
    p.add_argument("--cikis", default=varsayilan_cikis, help="CSV çıkış klasörü")
    p.add_argument("--kontrol-klasoru", default=None,
                   help="Eğitmen kontrol dosyaları (varsayılan: çıkış klasörünün yanında EgitmenKontrol)")
    p.add_argument("--temizle", action="store_true", help="Önce eski Satis_*.csv ve dq_log dosyalarını sil")
    p.add_argument("--interaktif", action="store_true", help="Parametreleri sorarak al")
    p.add_argument("--yardim-ornek", action="store_true")
    a = p.parse_args()

    if a.yardim_ornek:
        print("Örnekler:\n"
              "  python SalesData_Generator.py --temizle                      # 24 ay (2023-01..2024-12)\n"
              "  python SalesData_Generator.py --ay-sayisi 14 --aylik-siparis 500 --cikis .\\test --temizle   # hızlı test\n"
              "  python SalesData_Generator.py --seed 7 --dq-hata-orani 6 --temizle   # farklı veri / daha kirli")
        sys.exit(0)

    if a.interaktif or len(sys.argv) == 1:
        print("\n=== Pedalova Bisiklet - Veri Simülatörü (Enter = varsayılan) ===\n")
        for ad, tip, _, soru in VARSAYILANLAR:
            mevcut = getattr(a, ad)
            girdi = input(f"{soru} [{mevcut}] : ").strip()
            if girdi:
                setattr(a, ad, tip(girdi.replace(",", ".")))
        girdi = input(f"Çıkış klasörü [{a.cikis}] : ").strip()
        if girdi:
            a.cikis = girdi

    if not 1 <= a.baslangic_ay <= 12:
        sys.exit("Hata: baslangic-ay 1-12 olmalı.")
    if a.ay_sayisi < 1 or a.aylik_siparis < 1 or a.musteri_sayisi < 1:
        sys.exit("Hata: ay sayısı, sipariş ve müşteri sayısı pozitif olmalı.")
    return a


if __name__ == "__main__":
    uret(argumanlari_al())
