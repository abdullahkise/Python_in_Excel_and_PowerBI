"""
O2 doğrulama aracı: Silver -> Gold -> Excel analitik adımlarının BEKLENEN sayılarını CSV'lerden hesaplar.

Amaç : SQL (gold.*) ve Excel (ToolPak / Python in Excel) sonuçlarını karşılaştırmak için referans üretmek.
       Silver temizliği O1'deki referans uygulamayı (hesapla_beklenen_degerler.py) kullanır.
Veri değişirse sayılar da değişir; bu aracı her veri seti için yeniden çalıştırın.
Bağımlılık: numpy, pandas, scipy, scikit-learn
Kullanım  : python o2_hesapla.py <SalesRawData klasörü> [--kontrol <EgitmenKontrol klasörü>]
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

sys.dont_write_bytecode = True
O1_PY = Path(__file__).resolve().parents[2] / "01_Oturum_Excel_Bronze_Silver" / "python"
sys.path.insert(0, str(O1_PY))
import hesapla_beklenen_degerler as h  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# silver.RefStore / RefCampaign ile aynı (30_Silver_Referans.sql)
MAGAZA_BILGI = {
    "S001": ("İstanbul Kadıköy Mağazası", "İstanbul", "Marmara", "Fiziksel"),
    "S002": ("İstanbul Beşiktaş Mağazası", "İstanbul", "Marmara", "Fiziksel"),
    "S003": ("İstanbul Esenyurt Mağazası", "İstanbul", "Marmara", "Fiziksel"),
    "S004": ("Ankara Çankaya Mağazası", "Ankara", "İç Anadolu", "Fiziksel"),
    "S005": ("Ankara Keçiören Mağazası", "Ankara", "İç Anadolu", "Fiziksel"),
    "S006": ("İzmir Karşıyaka Mağazası", "İzmir", "Ege", "Fiziksel"),
    "S007": ("İzmir Bornova Mağazası", "İzmir", "Ege", "Fiziksel"),
    "S008": ("Bursa Nilüfer Mağazası", "Bursa", "Marmara", "Fiziksel"),
    "S009": ("Antalya Muratpaşa Mağazası", "Antalya", "Akdeniz", "Fiziksel"),
    "S010": ("Adana Seyhan Mağazası", "Adana", "Akdeniz", "Fiziksel"),
    "S011": ("Konya Selçuklu Mağazası", "Konya", "İç Anadolu", "Fiziksel"),
    "S012": ("Gaziantep Şahinbey Mağazası", "Gaziantep", "Güneydoğu Anadolu", "Fiziksel"),
    "S013": ("Samsun İlkadım Mağazası", "Samsun", "Karadeniz", "Fiziksel"),
    "S014": ("Trabzon Ortahisar Mağazası", "Trabzon", "Karadeniz", "Fiziksel"),
    "S900": ("Dijital Kanal Deposu", "İstanbul", "Dijital", "Dijital"),
}
SEHIR_BOLGE = {v[1]: v[2] for k, v in MAGAZA_BILGI.items() if v[3] == "Fiziksel"}
KAMPANYA_SAYISI = 7  # silver.RefCampaign
KANAL_GRUBU = {"Mağaza": "Fiziksel", "Web": "Dijital", "Mobil": "Dijital"}
ODEME_GRUBU = {"Kredi Kartı": "Kart", "Nakit": "Nakit", "Havale/EFT": "Banka Transferi"}
GUN_ADLARI = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]


def yas_grubu(a):
    if pd.isna(a):
        return "Bilinmiyor"
    a = int(a)
    return "18-24" if a <= 24 else "25-34" if a <= 34 else "35-44" if a <= 44 else "45-54" if a <= 54 else "55+"


def silver_olustur(klasor, ilk_n=None):
    """O1 Silver mantığının pandas karşılığı: temiz satırlar (silver.Sales)."""
    df, _ = h.yukle(klasor, ilk_n)
    o, f = h.degerlendir(df)
    silver = ~f["DQ17"] & ~f[h.KARANTINA].any(axis=1)

    nm = df.MusteriAdi.str.strip()
    tmp = pd.DataFrame({"c": o.CustomerID, "n": nm})
    tmp = tmp[tmp.n != ""]
    cnt = (tmp.groupby(["c", "n"]).size().reset_index(name="k")
           .sort_values(["c", "k", "n"], ascending=[True, False, True]))
    golden = cnt.drop_duplicates("c").set_index("c")["n"]

    d = df[silver.values]
    oo = o[silver.values]
    age = d.MusteriYas.str.strip().map(h.parse_int)
    disc = d.IndirimOrani.map(h.parse_decimal)
    s = pd.DataFrame({
        "OrderID": oo.SiparisID.astype("int64"),
        "OrderLineID": oo.SiparisSatirID.astype("int64"),
        "OrderDate": oo.Tarih,
        "CustomerID": oo.CustomerID,
        "CustomerName": oo.CustomerID.map(golden),
        "Gender": d.MusteriCinsiyet.str.strip().map(lambda x: h.GENDER_MAP.get(h.fold(x))),
        "City": d.MusteriSehir.str.strip().map(lambda x: h.CITY_MAP.get(h.fold(x))),
        "MembershipYear": d.MusteriUyelikYili.str.strip().astype(int),
        "Age": age.where((age >= 18) & (age <= 100)),
        "StoreID": d.MagazaID.str.strip(),
        "ChannelName": d.SatisKanali.str.strip(),
        "ProductID": d.UrunID.str.strip(),
        "PaymentType": d.OdemeTipi.str.strip().map(lambda x: h.PAY_MAP.get(h.fold(x))),
        "CampaignName": d.KampanyaAdi.str.strip(),
        "Quantity": d.SiparisAdedi.str.strip().map(h.parse_int),
        "UnitPrice": d.BirimFiyat.map(h.parse_decimal),
        "UnitCost": d.UrunMaliyeti.map(h.parse_decimal),
        "DiscountRate": disc.where(disc <= 1, disc / 100.0),
        "SourceFileName": d.SourceFileName,
    }).reset_index(drop=True)
    return s, df


def gold_olustur(s):
    """silver.Sales -> Gold (FactSales ve boyutlar)."""
    fact = s.copy()
    fact["GrossAmount"] = (fact.Quantity * fact.UnitPrice).round(2)
    fact["DiscountAmount"] = (fact.GrossAmount * fact.DiscountRate).round(2)
    fact["NetAmount"] = (fact.GrossAmount - fact.DiscountAmount).round(2)
    fact["CostAmount"] = (fact.Quantity * fact.UnitCost).round(2)
    fact["GrossProfit"] = (fact.NetAmount - fact.CostAmount).round(2)
    fact["CustomerAgeAtOrder"] = fact.Age
    fact["DateKey"] = fact.OrderDate.dt.strftime("%Y%m%d").astype(int)
    fact["Category"] = fact.ProductID.map(lambda p: h.URUNLER[p][1])
    fact["SubCategory"] = fact.ProductID.map(lambda p: h.URUNLER[p][2])

    # DimCustomer: son siparişteki (yaşı geçerli) yaş
    srt = fact.sort_values(["CustomerID", "OrderDate", "OrderID"], ascending=[True, False, False])
    latest_age = srt[srt.Age.notna()].drop_duplicates("CustomerID").set_index("CustomerID")["Age"]
    cust = (fact.groupby("CustomerID")
            .agg(CustomerName=("CustomerName", "first"), Gender=("Gender", "first"), City=("City", "first"),
                 MembershipYear=("MembershipYear", "first")).reset_index())
    cust["Region"] = cust.City.map(SEHIR_BOLGE)
    cust["LatestAge"] = cust.CustomerID.map(latest_age)
    cust["AgeGroup"] = cust.LatestAge.map(yas_grubu)
    return fact, cust


def betimsel(fact):
    """Excel'e giden gold.vw_Analytics_SalesLine ile aynı küme: yaşı NULL olan satırlar hariç."""
    fact = fact.dropna(subset=["CustomerAgeAtOrder"])
    cols = ["Quantity", "DiscountRate", "CustomerAgeAtOrder", "NetAmount", "GrossProfit", "UnitPrice"]
    rows = []
    for c in cols:
        v = fact[c].dropna().astype(float)
        rows.append([c, len(v), v.mean(), v.median(), v.std(ddof=1), v.skew(), v.kurt(), v.min(), v.max()])
    return pd.DataFrame(rows, columns=["Degisken", "Count", "Mean", "Median", "StdDev", "Skew", "Kurt", "Min", "Max"])


def korelasyon(fact):
    cols = ["Quantity", "DiscountRate", "CustomerAgeAtOrder", "NetAmount", "GrossProfit"]
    return fact[cols].dropna().astype(float).corr()


def siparis_duzeyi(fact):
    g = (fact.groupby("OrderID")
         .agg(NetAmount=("NetAmount", "sum"), OrderQty=("Quantity", "sum"), AvgDiscountRate=("DiscountRate", "mean"),
              CustomerAge=("CustomerAgeAtOrder", "first"), CustomerID=("CustomerID", "first")).reset_index())
    return g.dropna(subset=["CustomerAge"])


def regresyon(o):
    X = np.column_stack([np.ones(len(o)), o.OrderQty, o.AvgDiscountRate, o.CustomerAge]).astype(float)
    y = o.NetAmount.values.astype(float)
    n, k = X.shape
    beta = np.linalg.solve(X.T @ X, X.T @ y)
    res = y - X @ beta
    sse = float(res @ res)
    sst = float(((y - y.mean()) ** 2).sum())
    r2 = 1 - sse / sst
    df_res = n - k
    sigma2 = sse / df_res
    se = np.sqrt(np.diag(sigma2 * np.linalg.inv(X.T @ X)))
    t = beta / se
    p = 2 * stats.t.sf(np.abs(t), df_res)
    ci = stats.t.ppf(0.975, df_res) * se
    f = ((sst - sse) / (k - 1)) / sigma2
    pf = stats.f.sf(f, k - 1, df_res)
    adj = 1 - (1 - r2) * (n - 1) / df_res
    names = ["Kesişim", "OrderQty", "AvgDiscountRate", "CustomerAge"]
    coef = pd.DataFrame({"Katsayi": beta, "StdHata": se, "t": t, "p": p, "Alt95": beta - ci, "Ust95": beta + ci}, index=names)
    return coef, dict(n=n, r2=r2, adj_r2=adj, se_reg=float(np.sqrt(sigma2)), f=float(f), p_f=float(pf), df_res=df_res)


def musteri_ozellikleri(fact):
    g = fact.groupby("CustomerID").agg(TotalSpend=("NetAmount", "sum"), OrderCount=("OrderID", "nunique")).reset_index()
    g["AvgBasket"] = g.TotalSpend / g.OrderCount
    return g


def kmeans_analiz(rfm, k_aralik=range(2, 9), secilen_k=None):
    from sklearn.cluster import KMeans
    from sklearn.metrics import silhouette_score
    from sklearn.preprocessing import StandardScaler
    X = StandardScaler().fit_transform(rfm[["TotalSpend", "OrderCount", "AvgBasket"]])
    tablo = []
    for k in k_aralik:
        km = KMeans(n_clusters=k, n_init=10, random_state=42).fit(X)
        tablo.append((k, km.inertia_, silhouette_score(X, km.labels_)))
    tablo = pd.DataFrame(tablo, columns=["k", "Inertia", "Silhouette"])
    k = secilen_k or int(tablo.loc[tablo.Silhouette.idxmax(), "k"])
    km = KMeans(n_clusters=k, n_init=10, random_state=42).fit(X)
    out = rfm.copy()
    out["Cluster"] = km.labels_
    return tablo, k, out


def rapor(klasor, kontrol, ilk_n):
    s, df = silver_olustur(klasor, ilk_n)
    fact, cust = gold_olustur(s)
    pd.set_option("display.width", 200, "display.max_columns", 30, "display.float_format", lambda v: f"{v:,.4f}")

    print(f"# O2 referans hesap: {klasor}")
    print(f"Silver satır (silver.Sales): {len(s):,} | benzersiz sipariş {s.OrderID.nunique():,} | müşteri {s.CustomerID.nunique():,}")
    print("\n## Gold boyut ve fakt satır sayıları (bilinmeyen üye -1 dahil)")
    print(f"DimDate {1826:,} (2022-01-01..2026-12-31) | DimCustomer {len(cust) + 1} | DimProduct {len(h.URUNLER) + 1} | "
          f"DimStore {len(MAGAZA_BILGI) + 1} | DimChannel {fact.ChannelName.nunique() + 1} | DimPayment {fact.PaymentType.nunique() + 1} | "
          f"DimCampaign {KAMPANYA_SAYISI + 1} | FactSales {len(fact):,}")
    print(f"Fakt'ta bilinmeyen üye (-1) kullanımı: 0 beklenir. Tarih aralığı: {fact.OrderDate.min().date()} .. {fact.OrderDate.max().date()}")
    print(f"Yaşı NULL olan fakt satırı: {int(fact.Age.isna().sum())} | LatestAge NULL müşteri: {int(cust.LatestAge.isna().sum())}")

    tg = lambda c: float(fact[c].sum())
    gross, disc, net, cost, prof = tg("GrossAmount"), tg("DiscountAmount"), tg("NetAmount"), tg("CostAmount"), tg("GrossProfit")
    orders = fact.OrderID.nunique()
    print("\n## KPI toplamları (FactSales)")
    print(f"Brüt {gross:,.2f} | İndirim {disc:,.2f} | Net {net:,.2f} | Maliyet {cost:,.2f} | Brüt Kâr {prof:,.2f}")
    print(f"Kâr Marjı %{100 * prof / net:.2f} | Satış Adedi {int(fact.Quantity.sum()):,} | Sipariş {orders:,} | "
          f"AOV {net / orders:,.2f} | UPT {fact.Quantity.sum() / orders:.3f} | Ort. indirim (ağırlıklı) %{100 * disc / gross:.2f}")
    print(f"Net = Brüt − İndirim: {abs(net - (gross - disc)) < 0.01} | Kâr = Net − Maliyet: {abs(prof - (net - cost)) < 0.01}")

    def grup(c):
        g = fact.groupby(c).agg(Satir=("OrderID", "size"), Siparis=("OrderID", "nunique"), Net=("NetAmount", "sum"),
                                Brut=("GrossAmount", "sum"), Indirim=("DiscountAmount", "sum"), Kar=("GrossProfit", "sum"))
        g["OrtIndirimPct"] = 100 * g.Indirim / g.Brut
        g["MarjPct"] = 100 * g.Kar / g.Net
        return g.drop(columns=["Brut", "Indirim"])
    print("\n## Kampanya bazlı"); print(grup("CampaignName").to_string())
    print("\n## Ay bazlı (KaynakAy)"); print(grup(fact.OrderDate.dt.strftime("%Y-%m")).to_string())
    print("\n## Kategori bazlı"); print(grup("Category").to_string())
    print("\n## Kanal bazlı"); print(grup("ChannelName").to_string())
    print("\n## Ödeme bazlı"); print(grup("PaymentType").to_string())
    print("\n## DimCustomer yaş grubu dağılımı"); print(cust.AgeGroup.value_counts().sort_index().to_string())
    print("Şehir (top 5):", cust.City.value_counts().head(5).to_dict())

    print("\n## Betimsel istatistik (FactSales satır düzeyi; Excel ToolPak Descriptive Statistics karşılığı)")
    print(betimsel(fact).to_string(index=False))

    print("\n## Korelasyon matrisi (satır düzeyi, yaşı olan satırlar)")
    cm = korelasyon(fact)
    print(cm.to_string())
    nb = fact[fact.Category != "Bisiklet"]
    print(f"Bisiklet dışı: corr(DiscountRate, Quantity) = {nb.DiscountRate.corr(nb.Quantity):.4f}; tüm satırlar: {fact.DiscountRate.corr(fact.Quantity):.4f}")

    od = siparis_duzeyi(fact)
    coef, ozet = regresyon(od)
    print(f"\n## Regresyon (sipariş düzeyi): NetAmount = f(OrderQty, AvgDiscountRate, CustomerAge)  n={ozet['n']:,}")
    print(coef.to_string())
    print(f"R² {ozet['r2']:.4f} | Düzeltilmiş R² {ozet['adj_r2']:.4f} | Standart hata {ozet['se_reg']:,.2f} | F {ozet['f']:,.2f} (p={ozet['p_f']:.3g}) | gözlem {ozet['n']:,}")
    print("Sipariş düzeyi özet:", od[["NetAmount", "OrderQty", "AvgDiscountRate", "CustomerAge"]].describe().loc[["mean", "min", "max"]].round(3).to_dict())
    print(f"Multiple R {np.sqrt(ozet['r2']):.4f} | corr(OrderQty, NetAmount) {od.OrderQty.corr(od.NetAmount):.4f} "
          f"(trendline R² {od.OrderQty.corr(od.NetAmount) ** 2:.4f}) | corr(AvgDiscountRate, NetAmount) {od.AvgDiscountRate.corr(od.NetAmount):.4f}")
    ssr = ozet['r2'] * float(((od.NetAmount - od.NetAmount.mean()) ** 2).sum())
    print(f"ANOVA: df reg 3, df artık {ozet['df_res']}, toplam {ozet['n'] - 1} | SS reg {ssr:,.0f} | SS artık {(1 - ozet['r2']) * ssr / ozet['r2']:,.0f}")
    print("\nBisiklet dışı satırlarda indirim düzeyine göre ortalama adet (grafik için):")
    print(nb.groupby("DiscountRate").agg(Satir=("Quantity", "size"), OrtAdet=("Quantity", "mean")).round(3).to_string())

    rfm = musteri_ozellikleri(fact)
    tablo, k, seg = kmeans_analiz(rfm)
    print(f"\n## K-Means: müşteri özellikleri (n={len(rfm)}): TotalSpend, OrderCount, AvgBasket")
    print(rfm[["TotalSpend", "OrderCount", "AvgBasket"]].describe().loc[["mean", "min", "50%", "max"]].round(2).to_string())
    print("\nk seçimi (StandardScaler, n_init=10, random_state=42):")
    print(tablo.to_string(index=False))
    print(f"En yüksek silhouette k = {k}")
    for kk in (3, 4):
        _, _, sg = kmeans_analiz(rfm, secilen_k=kk)
        prof_k = sg.groupby("Cluster").agg(Musteri=("CustomerID", "size"), Harcama=("TotalSpend", "mean"),
                                           Siparis=("OrderCount", "mean"), Sepet=("AvgBasket", "mean")).round(1)
        print(f"\nk={kk} segment profili:"); print(prof_k.to_string())
        if kontrol and (Path(kontrol) / "musteri_ana_veri.csv").exists():
            from sklearn.metrics import adjusted_rand_score
            mv = pd.read_csv(Path(kontrol) / "musteri_ana_veri.csv", dtype=str, encoding="utf-8-sig").set_index("MusteriID")["GizliSegment"]
            sg["Gizli"] = sg.CustomerID.map(mv)
            print(f"Gizli gruplarla uyum (ARI) k={kk}: {adjusted_rand_score(sg.Gizli, sg.Cluster):.3f}")
            print(pd.crosstab(sg.Cluster, sg.Gizli).to_string())
    return fact, cust, rfm


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("klasor")
    ap.add_argument("--kontrol", default=None)
    ap.add_argument("--ilk-n-ay", type=int, default=None)
    a = ap.parse_args()
    rapor(a.klasor, a.kontrol, a.ilk_n_ay)
