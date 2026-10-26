"""
kmeans_python_in_excel.py hücre bloklarını Excel OLMADAN yerelde sınar.

Nasıl çalışır?
  - xl("Musteri_RFM[#All]", headers=True) çağrısını, Gold müşteri özelliklerini (pandas ile üretilmiş) döndüren bir
    taklit (shim) ile değiştirir.
  - Bloklar "# %% HÜCRE n" işaretlerinden ayrılır; her biri ortak bir ad alanında sırayla çalıştırılır;
    son ifade (Excel'deki hücre çıktısı gibi) ekrana yazdırılır.
Bağımlılık: numpy, pandas, scikit-learn, matplotlib
Kullanım  : python kmeans_yerel_test.py <SalesRawData klasörü> [--kontrol <EgitmenKontrol klasörü>] [--csv-yaz <Musteri_Segmentleri.csv>]
            (--csv-yaz: Python in Excel çalışmazsa PLAN B olarak segment CSV'sini doğrudan üretir.)
"""

import argparse
import ast
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import pandas as pd  # noqa: E402

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import o2_hesapla as o2  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ap = argparse.ArgumentParser()
ap.add_argument("klasor")
ap.add_argument("--kontrol", default=None)
ap.add_argument("--csv-yaz", default=None, help="PLAN B: Musteri_Segmentleri.csv'yi (UTF-8 BOM) bu yola yaz")
a = ap.parse_args()

s, _ = o2.silver_olustur(a.klasor)
fact, _ = o2.gold_olustur(s)
rfm = o2.musteri_ozellikleri(fact)
ozet = fact.groupby("CustomerID").size().reset_index(name="n")
gv = rfm[["CustomerID", "TotalSpend", "OrderCount", "AvgBasket"]].copy()   # gold.vw_Analytics_Customer'ın ilk 4 kolonu
gv[["TotalSpend", "AvgBasket"]] = gv[["TotalSpend", "AvgBasket"]].round(2)  # SQL view DECIMAL(14,2) döndürür


def xl(ad, headers=False):
    assert ad == "Musteri_RFM[#All]" and headers, "Beklenmeyen xl() çağrısı: " + ad
    return gv.copy()


kod = (Path(__file__).parent / "kmeans_python_in_excel.py").read_text(encoding="utf-8")
bloklar = re.split(r"^# %% (HÜCRE \d+.*)$", kod, flags=re.M)
ns = {"xl": xl}
sonuclar = {}
for baslik, icerik in zip(bloklar[1::2], bloklar[2::2]):
    agac = ast.parse(icerik)
    son = agac.body[-1]
    if isinstance(son, ast.Expr):
        govde = ast.Module(body=agac.body[:-1], type_ignores=[])
        exec(compile(govde, baslik, "exec"), ns)
        deger = eval(compile(ast.Expression(son.value), baslik, "eval"), ns)
    else:
        exec(compile(agac, baslik, "exec"), ns)
        deger = None
    sonuclar[baslik.split()[1] + " " + baslik.split()[2]] = deger
    ad = baslik.split("(")[0].strip()
    tur = type(deger).__name__
    print(f"\n=== {ad} -> {tur}" + (f" {deger.shape}" if hasattr(deger, "shape") else ""))
    if isinstance(deger, pd.DataFrame):
        print(deger.head(12).to_string())

seg = ns["seg"]
print("\n=== Segment dağılımı (müşteri sayısı):", seg["Segment"].value_counts().to_dict())
print("Çıktı tablosu kolonları:", list(ns["cikti"].columns), "| satır:", len(ns["cikti"]))
if a.csv_yaz:
    Path(a.csv_yaz).parent.mkdir(parents=True, exist_ok=True)
    ns["cikti"].to_csv(a.csv_yaz, index=False, encoding="utf-8-sig")
    print("PLAN B CSV yazıldı:", a.csv_yaz)

# determinizm: aynı random_state ile ikinci çalıştırma aynı etiketleri vermeli
from sklearn.cluster import KMeans  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402
X = StandardScaler().fit_transform(gv[["TotalSpend", "OrderCount", "AvgBasket"]])
l1 = KMeans(n_clusters=4, n_init=10, random_state=42).fit(X).labels_
l2 = KMeans(n_clusters=4, n_init=10, random_state=42).fit(X).labels_
print("Aynı seed -> aynı etiket:", bool((l1 == l2).all()))

if a.kontrol and (Path(a.kontrol) / "musteri_ana_veri.csv").exists():
    from sklearn.metrics import adjusted_rand_score
    mv = pd.read_csv(Path(a.kontrol) / "musteri_ana_veri.csv", dtype=str, encoding="utf-8-sig").set_index("MusteriID")["GizliSegment"]
    seg2 = seg.assign(Gizli=seg.CustomerID.map(mv))
    print("Gizli grup uyumu (ARI):", round(adjusted_rand_score(seg2.Gizli, seg2.Segment), 3))
    print(pd.crosstab(seg2.Segment, seg2.Gizli).to_string())
