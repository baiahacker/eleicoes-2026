#!/usr/bin/env python3
"""Baixa os logs das urnas (log.jez) de municípios escolhidos e resume o horário dos votos por seção.

Fonte: arquivos de urna da divulgação do TSE (resultados.tse.jus.br/oficial/<ciclo>/arquivo-urna/<pleito>/...).
O log registra cada evento da urna com data e hora, inclusive "O voto do eleitor foi computado". A mesma urna
pode guardar eventos de mais de um dia (1º e 2º turno), então só entram os eventos da data pedida.

Uso:  python3 logs_urna.py <ciclo> <pleito> <uf|uf,uf|br> <data dd/mm/aaaa> <cd_mun ...|todos> [--amostra=N] [--fios=6]
Ex.:  python3 logs_urna.py ele2026 3221 sp 25/10/2026 65790 70050 62693 65110 69132
      python3 logs_urna.py ele2026 3221 br 25/10/2026 todos --amostra=100

Saídas:
  brutos/<ano>/logs_urna/p<pleito>/<uf>/<mun>/<zona>-<secao>-<n>.jez   (logs originais, retomável)
  saida/logs_urna_p<pleito>_<rótulo>.csv: uma linha por seção, horários em Brasília e votos por hora.
"""
import csv, io, json, os, random, subprocess, sys, tempfile, time, urllib.request, zipfile
from concurrent.futures import ThreadPoolExecutor

ACERVO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = "https://resultados.tse.jus.br/oficial/{ciclo}/arquivo-urna/{pleito}"


def baixar(url, tentativas=4):
    for t in range(tentativas):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return r.read()
        except Exception as e:  # 404 não muda com nova tentativa
            if getattr(e, "code", None) == 404:
                return None
            time.sleep(2 * (t + 1))
    raise RuntimeError("falhou: " + url)


def ler_jez(dados):
    """log.jez é um zip (às vezes 7z) com logd.dat em latin1. Urna que já foi trocada ou reaproveitada traz o log
    anterior como outro .jez dentro do zip; junta todos."""
    try:
        with zipfile.ZipFile(io.BytesIO(dados)) as z:
            partes = []
            for n in z.namelist():
                b = z.read(n)
                partes.append(ler_jez(b) if b[:2] == b"PK" or n.endswith(".jez") else b.decode("latin1"))
            return "\n".join(partes)
    except zipfile.BadZipFile:
        with tempfile.TemporaryDirectory() as d:
            arq = os.path.join(d, "log.jez")
            open(arq, "wb").write(dados)
            subprocess.run(["7z", "x", "-y", "-o" + d, arq], capture_output=True, check=True)
            nomes = [n for n in os.listdir(d) if n != "log.jez"]
            return open(os.path.join(d, nomes[0]), encoding="latin1").read()


FUSO = {"ac": -2, "am": -1, "ro": -1, "rr": -1, "mt": -1, "ms": -1}   # horas atrás de Brasília; o resto é 0


def resumir(textos, data, uf=""):
    ev = set()
    for t in textos:  # urna substituída gera mais de um log; eventos repetidos contam uma vez
        for l in t.splitlines():
            c = l.split("\t")
            if len(c) >= 5 and c[0].startswith(data):
                ev.add((c[0][11:19], c[4]))
    # O relógio da urna está no horário local; tudo sai em Brasília. O fuso vem da UF. No Amazonas, o oeste do
    # estado fica 2 horas atrás: lá a urna fica pronta perto das 6h locais (a votação abre às 8h de Brasília).
    seg = lambda h: int(h[:2]) * 3600 + int(h[3:5]) * 60 + int(h[6:8])
    pronta = next((h for h, m in ev if m.startswith("Urna pronta para receber votos")), "")
    fuso = FUSO.get(uf, 0)
    if uf == "am" and pronta and seg(pronta) < 6.75 * 3600:
        fuso = -2
    hms = lambda s: f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}"
    ev = sorted((hms(seg(h) - fuso * 3600), m) for h, m in ev if seg(h) - fuso * 3600 >= 0)
    votos = [h for h, m in ev if m == "O voto do eleitor foi computado"]
    achar = lambda txt: next((h for h, m in reversed(ev) if m.startswith(txt)), "")   # o último registro vale
    por_hora = {f"v{h:02d}": sum(1 for v in votos if int(v[:2]) == h) for h in range(7, 22)}
    # de 16h às 20h, de 15 em 15 minutos (q1600 = 16:00–16:14)
    por_hora.update({f"q{h:02d}{m:02d}": sum(1 for v in votos if v[:2] == f"{h:02d}" and m <= int(v[3:5]) < m + 15)
                     for h in range(16, 20) for m in (0, 15, 30, 45)})
    return {"votos": len(votos), "primeiro_voto": votos[0] if votos else "", "ultimo_voto": votos[-1] if votos else "",
            "votos_apos_17h": sum(1 for v in votos if v >= "17:00:00"),
            "votos_apos_17h05": sum(1 for v in votos if v >= "17:05:00"),
            "fuso": fuso, "pronta": achar("Urna pronta para receber votos"), "encerrar": achar("Operador selecionou: Encerrar votação"),
            "todos_votaram": next((m.split("?")[-1].strip() for h, m in ev if m.startswith("Todas as pessoas presentes")), ""),
            "logs": len(textos), **por_hora}


def secao(args):
    cfg, uf, mun, zona, sec, data, pasta = args
    url = f"{cfg}/dados/{uf}/{mun}/{zona}/{sec}/p{cfg.rsplit('/', 1)[1].zfill(6)}-{uf}-m{mun}-z{zona}-s{sec}-aux.json"
    aux = baixar(url)
    if aux is None:
        return {"mun": mun, "zona": zona, "secao": sec, "status": "sem aux"}
    aux = json.loads(aux)
    textos = []
    for i, h in enumerate(aux.get("hashes", [])):
        log = next((a["nm"] for a in h.get("arq", []) if a["tp"] == "log"), None)
        if not log:
            continue
        local = os.path.join(pasta, f"{zona}-{sec}-{i}.jez")
        if not os.path.exists(local):
            d = baixar(url.rsplit("/", 1)[0] + f"/{h['hash']}/{log}")
            if d is None:
                continue
            open(local + ".tmp", "wb").write(d); os.replace(local + ".tmp", local)
        textos.append(ler_jez(open(local, "rb").read()))
    r = resumir(textos, data, uf) if textos else {}
    return {"mun": mun, "zona": zona, "secao": sec, "status": aux.get("st", ""), **r}


UFS = "ac al am ap ba ce df es go ma mg ms mt pa pb pe pi pr rj rn ro rr rs sc se sp to".split()


def main():
    """<uf> pode ser uma UF, várias separadas por vírgula ou "br". <cd_mun> pode ser "todos".
    --amostra=N sorteia N seções por UF (semente fixa, reprodutível) em vez de pegar todas."""
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    amostra = next((int(a.split("=")[1]) for a in sys.argv[1:] if a.startswith("--amostra=")), 0)
    ciclo, pleito, ufs, data, muns = args[0], args[1], args[2].lower(), args[3], args[4:]
    ufs = UFS if ufs == "br" else ufs.split(",")
    cfg = BASE.format(ciclo=ciclo, pleito=pleito)
    tarefas, nomes = [], {}
    for uf in ufs:
        cs = json.loads(baixar(f"{cfg}/config/{uf}/{uf}-p{pleito.zfill(6)}-cs.json"))
        da_uf = []
        for m in cs["abr"][0]["mu"]:
            if muns != ["todos"] and m["cd"] not in muns:
                continue
            nomes[m["cd"]] = m["nm"]
            pasta = os.path.join(ACERVO, "brutos", ciclo[3:], "logs_urna", f"p{pleito}", uf, m["cd"])
            for z in m["zon"]:
                for s in z["sec"]:
                    if "nsp" not in s:  # seção agregada: os votos estão na urna da seção principal (nsp)
                        da_uf.append((cfg, uf, m["cd"], z["cd"], s["ns"], data, pasta))
        if amostra:
            da_uf = random.Random(f"{pleito}-{uf}").sample(da_uf, min(amostra, len(da_uf)))
        tarefas += da_uf
    for t in tarefas:
        os.makedirs(t[-1], exist_ok=True)
    print(f"{len(tarefas)} seções em {len(ufs)} UF(s)", flush=True)
    linhas = []
    fios = next((int(a.split("=")[1]) for a in sys.argv[1:] if a.startswith("--fios=")), 6)
    with ThreadPoolExecutor(fios) as ex:
        for i, (t, r) in enumerate(zip(tarefas, ex.map(secao, tarefas)), 1):
            r["uf"], r["nm_mun"] = t[1].upper(), nomes[r["mun"]]
            linhas.append(r)
            if i % 100 == 0:
                print(f"{i}/{len(tarefas)}", flush=True)
    os.makedirs(os.path.join(ACERVO, "saida"), exist_ok=True)
    rotulo = ("br" if len(ufs) == 27 else "_".join(ufs)) + (f"_amostra{amostra}" if amostra else "")
    saida = os.path.join(ACERVO, "saida", f"logs_urna_p{pleito}_{rotulo}.csv")
    campos = sorted({k for l in linhas for k in l}, key=lambda k: (k[0] in "vq" and k[1:].isdigit(), k))
    with open(saida, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos); w.writeheader(); w.writerows(linhas)
    print("ok:", saida, flush=True)


if __name__ == "__main__":
    main()
