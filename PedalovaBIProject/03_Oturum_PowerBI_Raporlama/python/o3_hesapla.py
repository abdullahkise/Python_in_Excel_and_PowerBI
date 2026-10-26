"""
O3 doğrulama aracı: Power BI rapor sayfalarının ve DAX ölçülerinin BEKLENEN sayılarını CSV'lerden hesaplar.

Amaç : Power BI'da yazılan DAX ölçülerinin sonuçlarını karşılaştırmak için referans üretmek
       (Silver/Gold mantığı O2'deki o2_hesapla.py'dan, segmentler Excel çıktısı CSV'den gelir).
Veri değişirse sayılar da değişir; bu aracı her veri seti için yeniden çalıştırın.
Bağımlılık: numpy, pandas, scipy, scikit-learn, networkx
Kullanım  : python o3_hesapla.py <SalesRawData klasörü> [--segment <Musteri_Segmentleri.csv>] [--kontrol <EgitmenKontrol>]
"""

import argparse
import sys
from collections import Counter
from itertools import combinations
from pathlib import Path

import numpy as np
import pandas as pd

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
O2_PY = HERE.parents[1] / "02_Oturum_BUS_Gold_Analitik" / "python"
O1_PY = HERE.parents[1] / "01_Oturum_Excel_Bronze_Silver" / "python"
sys.path.insert(0, str(O2_PY))
sys.path.insert(0, str(O1_PY))
import hesapla_beklenen_degerler as h  # noqa: E402
import o2_hesapla as o2  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

VARSAYILAN_SEGMENT = HERE.parents[1] / "02_Oturum_BUS_Gold_Analitik" / "Musteri_Segmentleri_PlanB.csv"


def fakt_olustur(klasor):
    s, df = o2.silver_olustur(klasor)
    fact, cust = o2.gold_olustur(s)
    fact["ProductName"] = fact.ProductID.map(lambda p: h.URUNLER[p][0])
    fact["Brand"] = fact.ProductID.map(lambda p: h.URUNLER[p][3])
    fact["YearMonth"] = fact.OrderDate.dt.strftime("%Y-%m")
    return fact, cust, df


def birliktelik(fact, min_birlikte=1):
    """Sipariş sepetlerinden ürün çifti sayıları ve lift (NetworkX girdisi)."""
    sepet = fact.groupby("OrderID").ProductName.apply(lambda x: sorted(set(x)))
    n = len(sepet)
    urun, cift = Counter(), Counter()
    for s in sepet:
        urun.update(s)
        cift.update(combinations(s, 2))
    satirlar = []
    for (a, b), c in cift.items():
        if c >= min_birlikte:
            lift = (c / n) / ((urun[a] / n) * (urun[b] / n))
            satirlar.append((a, b, c, lift, c / urun[a], c / urun[b]))
    return pd.DataFrame(satirlar, columns=["A", "B", "Birlikte", "Lift", "P_B_given_A", "P_A_given_B"]), urun, n


def rapor(klasor, segment_csv, kontrol):
    fact, cust, df = fakt_olustur(klasor)
    pd.set_option("display.width", 220, "display.max_columns", 30, "display.float_format", lambda v: f"{v:,.4f}")
    net = fact.NetAmount.sum()
    orders = fact.OrderID.nunique()
    print(f"# O3 referans hesap: {klasor}")
    print(f"Fakt satır {len(fact):,} | sipariş {orders:,} | müşteri {fact.CustomerID.nunique()} | tarih {fact.OrderDate.min().date()} .. {fact.OrderDate.max().date()}")

    # ---------- Sayfa 1: Yönetici özeti ----------
    gross, disc, prof = fact.GrossAmount.sum(), fact.DiscountAmount.sum(), fact.GrossProfit.sum()
    print("\n## Sayfa 1 – KPI (filtre yok)")
    print(f"Net {net:,.2f} | Brüt {gross:,.2f} | Kâr {prof:,.2f} | Marj %{100 * prof / net:.2f} | Adet {int(fact.Quantity.sum()):,} | "
          f"Sipariş {orders:,} | Müşteri {fact.CustomerID.nunique()} | AOV {net / orders:,.2f} | UPT {fact.Quantity.sum() / orders:.3f} | "
          f"Ort. indirim %{100 * disc / gross:.2f}")

    # ---------- Sayfa 2: Zaman analizi ----------
    ay = fact.groupby("YearMonth").agg(Net=("NetAmount", "sum"), Siparis=("OrderID", "nunique"), Adet=("Quantity", "sum")).sort_index()
    pidx = pd.PeriodIndex(ay.index, freq="M")
    ay["YTD"] = ay.groupby(pidx.year).Net.cumsum().values
    ay["QTD"] = ay.groupby([pidx.year, pidx.quarter]).Net.cumsum().values
    ay["MTD (ay sonu)"] = ay.Net
    ay["MoM %"] = 100 * ay.Net.pct_change()
    ay["LY (2022)"] = np.nan
    print("\n## Sayfa 2 – Ay bazlı zaman ölçüleri (ay sonu görünümü; 2023 ayları için LY = 2022 verisi YOK -> BOŞ; 2024 YoY aşağıdaki DAX bölümünde)")
    print(ay.to_string())
    ref = fact.OrderDate.max()
    print(f"Son satış tarihi (kart referansı): {ref.date()} | YTD {ay.YTD.iloc[-1]:,.2f} | QTD {ay.QTD.iloc[-1]:,.2f} | MTD {ay.Net.iloc[-1]:,.2f}")
    gun = fact.groupby("OrderDate").NetAmount.sum()
    mart = gun[gun.index >= "2023-03-01"]
    mart = mart[mart.index < "2023-04-01"]
    print(f"Mart ayı günlük MTD örneği: 2023-03-15 itibarıyla MTD = {mart[mart.index <= '2023-03-15'].sum():,.2f}")
    hafta = fact.assign(Hafta=fact.OrderDate.dt.dayofweek).groupby("Hafta").NetAmount.sum().round(2)
    print("Haftanın gününe göre Net (0=Pzt):", hafta.to_dict())

    # ---------- Sayfa 3: Ürün + pay oranı ----------
    kat = fact.groupby("Category").NetAmount.sum().sort_values(ascending=False)
    print("\n## Sayfa 3 – Kategori payı (toplam içinde %)")
    print(pd.DataFrame({"Net": kat, "Pay%": 100 * kat / net}).to_string())
    alt = fact.groupby(["Category", "SubCategory"]).NetAmount.sum()
    alt = alt.to_frame("Net").assign(**{"Pay% (toplam)": 100 * alt / net, "Pay% (kategori içi)": 100 * alt / alt.groupby(level=0).transform("sum")})
    print("\nAlt kategori (ilk 8, Net'e göre):"); print(alt.sort_values("Net", ascending=False).head(8).to_string())
    marka = fact.groupby("Brand").NetAmount.sum().sort_values(ascending=False)
    print("\nMarka (ilk 6):"); print(pd.DataFrame({"Net": marka, "Pay%": 100 * marka / net}).head(6).to_string())
    urun = fact.groupby("ProductName").agg(Net=("NetAmount", "sum"), Adet=("Quantity", "sum"), Kar=("GrossProfit", "sum")).sort_values("Net", ascending=False)
    print("\nÜrün (ilk 5 Net):"); print(urun.head(5).to_string())
    cagr = fact.groupby("ChannelName").NetAmount.sum()
    print("\nKanal payı %:", (100 * cagr / net).round(2).to_dict())
    print("Ödeme payı %:", (100 * fact.groupby("PaymentType").NetAmount.sum() / net).round(2).to_dict())

    # ---------- Sayfa 4: Müşteri / segment ----------
    print("\n## Sayfa 4 – Müşteri")
    seg = pd.read_csv(segment_csv, encoding="utf-8-sig")
    f2 = fact.merge(seg[["CustomerID", "Segment"]], on="CustomerID", how="left")
    g = f2.groupby("Segment").agg(Musteri=("CustomerID", "nunique"), Siparis=("OrderID", "nunique"), Net=("NetAmount", "sum"),
                                  Kar=("GrossProfit", "sum"), Brut=("GrossAmount", "sum"), Indirim=("DiscountAmount", "sum"))
    g["AOV"] = g.Net / g.Siparis
    g["Pay%"] = 100 * g.Net / net
    g["Marj%"] = 100 * g.Kar / g.Net
    g["OrtIndirim%"] = 100 * g.Indirim / g.Brut
    print(g.drop(columns=["Kar", "Brut", "Indirim"]).sort_values("Net", ascending=False).to_string())
    print("Segmenti olmayan fakt satırı:", int(f2.Segment.isna().sum()))
    sehir = fact.groupby("City").agg(Musteri=("CustomerID", "nunique"), Net=("NetAmount", "sum")).sort_values("Net", ascending=False)
    print("\nŞehir (ilk 5, Net):"); print(sehir.head(5).to_string())
    yg = fact.assign(AgeGroup=fact.CustomerID.map(cust.set_index("CustomerID").AgeGroup)).groupby("AgeGroup").agg(
        Musteri=("CustomerID", "nunique"), Net=("NetAmount", "sum"), Siparis=("OrderID", "nunique"))
    yg["AOV"] = yg.Net / yg.Siparis
    print("\nYaş grubu:"); print(yg.to_string())
    bolge = fact.assign(Region=fact.CustomerID.map(cust.set_index("CustomerID").Region)).groupby("Region").NetAmount.sum().sort_values(ascending=False)
    print("\nBölge Net:", bolge.round(2).to_dict())
    cinsiyet = fact.groupby("Gender").agg(Musteri=("CustomerID", "nunique"), Net=("NetAmount", "sum"))
    print("Cinsiyet:", cinsiyet.round(2).to_dict("index"))

    # ---------- Kampanya karşılaştırması (aylık ortalama mantığı) ----------
    camp = fact.groupby("CampaignName").agg(Net=("NetAmount", "sum"), Ay=("YearMonth", "nunique"))
    camp["Ay başına Net"] = camp.Net / camp.Ay
    print("\n## Kampanya (Ay başına Net = Net / satış olan ay sayısı)"); print(camp.to_string())

    # ---------- Sayfa 5: Veri kalitesi ----------
    print("\n## Sayfa 5 – Veri kalitesi (O1 çıktısı; Power BI dq.* view'larından)")
    df2, flags = df, None
    o, f = h.degerlendir(df)
    n = len(df)
    viol = f.any(axis=1)
    print(f"DQ Skoru {100 * (~viol).sum() / n:.2f} | Bronze {n:,} | ihlalli {int(viol.sum())} | tekrar {int(f.DQ17.sum())} | karantina "
          f"{int((f[h.KARANTINA].any(axis=1) & ~f.DQ17).sum())} | Silver {len(fact):,}")
    for b in ["Tamlık", "Geçerlilik", "Tutarlılık", "Benzersizlik", "Bütünlük"]:
        cols = [k for k, v in h.KURALLAR.items() if v[0] == b]
        print(f"  {b:13s} ihlalli {int(f[cols].any(axis=1).sum()):3d}  skor {100 * (1 - f[cols].any(axis=1).sum() / n):.3f}")

    # ---------- Sayfa 6: İleri analitik ----------
    print("\n## Sayfa 6 – Korelasyon (Power BI SUMX ölçüsü; yaşı geçerli satırlar, n=%d)" % fact.CustomerAgeAtOrder.notna().sum())
    cm = o2.korelasyon(fact)
    cm.index = cm.columns = ["Adet", "İndirim Oranı", "Müşteri Yaşı", "Net Satış", "Brüt Kâr"]
    print(cm.to_string())
    pm = fact.groupby("CustomerID").agg(Net=("NetAmount", "sum"), Brut=("GrossAmount", "sum"), Ind=("DiscountAmount", "sum"),
                                         Adet=("Quantity", "sum"), Sip=("OrderID", "nunique"))
    pm["OrtInd"] = pm.Ind / pm.Brut
    pm["UPT"] = pm.Adet / pm.Sip
    pm["AOV"] = pm.Net / pm.Sip
    print(f"\nQuick measure örneği (kategori = müşteri, n={len(pm)}): corr([Ort. İndirim %], [UPT]) = {pm.OrtInd.corr(pm.UPT):.4f} | "
          f"corr([Ort. İndirim %], [AOV]) = {pm.OrtInd.corr(pm.AOV):.4f} | corr([UPT], [AOV]) = {pm.UPT.corr(pm.AOV):.4f}")
    od = o2.siparis_duzeyi(fact)
    coef, oz = o2.regresyon(od)
    print("\nRegresyon özeti (Excel ToolPak ile aynı):"); print(coef.round(4).to_string())
    print(f"R² {oz['r2']:.4f} | düz. R² {oz['adj_r2']:.4f} | n {oz['n']:,} | F {oz['f']:.2f}")

    bl, urun_say, nsip = birliktelik(fact)
    print(f"\n## Bonus – ürün birliktelik ağı (sipariş {nsip:,}; ürün {len(urun_say)}; gözlenen çift {len(bl)})")
    for esik in (20, 50, 100, 200):
        k = bl[bl.Birlikte >= esik]
        print(f"  Birlikte >= {esik:4d}: {len(k):3d} kenar")
    print("\nEn yüksek lift (Birlikte >= 50):")
    print(bl[bl.Birlikte >= 50].sort_values("Lift", ascending=False).head(10).to_string(index=False))
    print("\nEn çok birlikte satılan çiftler:")
    print(bl.sort_values("Birlikte", ascending=False).head(8).to_string(index=False))
    import networkx as nx
    G = nx.Graph()
    for _, r in bl[(bl.Birlikte >= 50) & (bl.Lift >= 1.5)].iterrows():
        G.add_edge(r.A, r.B, weight=int(r.Birlikte), lift=float(r.Lift))
    print(f"\nAğ (Birlikte >= 50 ve Lift >= 1,5): düğüm {G.number_of_nodes()}, kenar {G.number_of_edges()}, bağlı bileşen {nx.number_connected_components(G)}")
    topluluk = nx.algorithms.community.greedy_modularity_communities(G, weight="weight")
    for i, t in enumerate(sorted(topluluk, key=len, reverse=True), 1):
        print(f"  Topluluk {i} ({len(t)}):", ", ".join(sorted(t)))
    dc = nx.degree_centrality(G)
    print("Derece merkeziliği (ilk 5):", sorted(((round(v, 3), k) for k, v in dc.items()), reverse=True)[:5])
    dax_beklenenler(fact, o, f, n)
    return fact


def dax_beklenenler(fact, ozet, bayrak, bronze_n):
    """01_Olculer.dax yorumlarındaki 'Beklenen' değerlerin tamamı (YoY dahil)."""
    net, orders = fact.NetAmount.sum(), fact.OrderID.nunique()
    print("\n## DAX – Temel ölçüler")
    print(f"Brüt {fact.GrossAmount.sum():,.2f} | İndirim {fact.DiscountAmount.sum():,.2f} | Net {net:,.2f} | Maliyet {fact.CostAmount.sum():,.2f} | "
          f"Kâr {fact.GrossProfit.sum():,.2f} | Adet {int(fact.Quantity.sum()):,} | Sipariş {orders:,}")
    print(f"Bisiklet Net {fact[fact.Category == 'Bisiklet'].NetAmount.sum():,.2f} | Kampanyalı Net "
          f"{fact[fact.CampaignName != 'Kampanya Yok'].NetAmount.sum():,.2f} | İndirim>=%10 satır {(fact.DiscountRate >= 0.1).sum():,} | "
          f"Bisikletli sipariş {fact[fact.Category == 'Bisiklet'].OrderID.nunique():,}")
    kat = fact.groupby("Category").NetAmount.sum()
    bilesen_aks = kat[["Bileşen", "Aksesuar"]]
    print("Pay % (Görünür) Bileşen+Aksesuar seçiliyken:", (100 * bilesen_aks / bilesen_aks.sum()).round(2).to_dict())

    print("\n## DAX – Kampanya (Net / pay / ay sayısı / ay başına / tutar ağırlıklı indirim %)")
    c = fact.groupby("CampaignName").agg(Net=("NetAmount", "sum"), Brut=("GrossAmount", "sum"), Ind=("DiscountAmount", "sum"),
                                         Ay=("YearMonth", "nunique"))
    c["Pay%"] = 100 * c.Net / net
    c["AyBasina"] = c.Net / c.Ay
    c["Indirim%"] = 100 * c.Ind / c.Brut
    print(c.drop(columns=["Brut", "Ind"]).sort_values("Net", ascending=False).to_string())
    print("Kampanya x ay:", {k: sorted(v) for k, v in fact.groupby("CampaignName").YearMonth.unique().items()})

    print("\n## DAX – Time Intelligence (YoY: 2024 ↔ 2023)")
    ay = fact.groupby("YearMonth").NetAmount.sum()
    t = pd.DataFrame({"Net": ay})
    t["LY"] = [ay.get(f"{int(m[:4]) - 1}-{m[5:]}", np.nan) for m in t.index]
    t["YoY%"] = 100 * (t.Net - t.LY) / t.LY
    t["OncekiAy"] = t.Net.shift(1)
    t["MoM%"] = 100 * (t.Net - t.OncekiAy) / t.OncekiAy
    t["Son3Ay"] = t.Net.rolling(3).sum()
    print(t.to_string())
    yil = fact.groupby(fact.OrderDate.dt.year).NetAmount.sum()
    print(f"Yıl Net: 2023 {yil[2023]:,.2f} | 2024 {yil[2024]:,.2f} | YTD YoY % (kart, 2024-12-31) {100 * (yil[2024] / yil[2023] - 1):.2f}")
    gun = fact.groupby("OrderDate").NetAmount.sum()
    for d in ("2024-03-15", "2024-06-15"):
        d0 = pd.Timestamp(d)
        mtd = gun[(gun.index.year == d0.year) & (gun.index.month == d0.month) & (gun.index <= d0)].sum()
        ytd = gun[(gun.index.year == d0.year) & (gun.index <= d0)].sum()
        print(f"{d}: MTD {mtd:,.2f} | YTD {ytd:,.2f}")
    print("Çeyrek Net (YearQuarter):", fact.groupby(fact.OrderDate.dt.to_period("Q").astype(str)).NetAmount.sum().round(2).to_dict())

    print("\n## DAX – DQ kartları")
    print(f"Bronze {bronze_n:,} | Silver {len(fact):,} | Silver Kabul % {100 * len(fact) / bronze_n:.2f} | Karantina %"
          f" {100 * int((bayrak[h.KARANTINA].any(axis=1) & ~bayrak.DQ17).sum()) / bronze_n:.2f} | Tamlık ihlali {int(bayrak[[k for k, v in h.KURALLAR.items() if v[0] == 'Tamlık']].any(axis=1).sum())}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("klasor")
    ap.add_argument("--segment", default=str(VARSAYILAN_SEGMENT))
    ap.add_argument("--kontrol", default=None)
    a = ap.parse_args()
    rapor(a.klasor, a.segment, a.kontrol)
