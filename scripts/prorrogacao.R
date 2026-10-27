# Votos depois das 17h no 2º turno de 2026: números e imagens do post sobre a prorrogação até as 19h.
#
# Entradas (rodar da raiz do repositório):
#   saida/logs_urna_p3221_sp.csv               todas as urnas de Itu, Salto, Cabreúva, Indaiatuba e Porto Feliz
#   saida/logs_urna_p3221_br_amostra150.csv    150 urnas sorteadas por UF
#   saida/logs_urna_p3221_ba_pb_pe_rj_se.csv   todas as urnas das 9 cidades com urnas abertas até as 19h
#   dados/validos_uf_2t_2026.csv               votos válidos por UF (resultado do TSE)
#   dados/locais_secoes_2t_2026.csv            local de votação de cada seção (eleitorado do TSE)
# Os três primeiros saem de scripts/logs_urna.py (ver README).
#
# Uso: Rscript scripts/prorrogacao.R [pasta_saida]     (padrão: posts/2026-10-prorrogacao)
# Saídas: 1_regiao_itu.png, 2_brasil.png, 3_cidades_19h.png, numeros.txt e urnas_abertas_19h.csv.
suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(scales); library(ragg) })
a <- commandArgs(TRUE)
out <- if (length(a)) a[1] else "posts/2026-10-prorrogacao"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

ler <- function(f) {
  d <- fread(f, colClasses = list(character = c("primeiro_voto", "ultimo_voto", "pronta", "encerrar")))
  d[, `:=`(zona = as.integer(zona), secao = as.integer(secao), encerrar = fifelse(is.na(encerrar), "", encerrar))][]
}
pp <- function(v, d = 1) formatC(v, format = "f", digits = d, decimal.mark = ",")
mil <- function(v) trimws(format(round(v), big.mark = ".", decimal.mark = ",", scientific = FALSE))
nome <- function(nm) gsub(" (De|Da|Do|Das|Dos|E) ", " \\L\\1 ", tools::toTitleCase(tolower(nm)), perl = TRUE)
rot_q <- function(k) paste0(substr(k, 2, 3), "h", substr(k, 4, 5))
tema <- theme_minimal(base_size = 15) + theme(plot.title = element_text(face = "bold", size = 19), plot.subtitle = element_text(colour = "grey35"),
  plot.caption = element_text(colour = "grey45", size = 10), legend.position = "bottom", panel.grid.minor = element_blank(),
  plot.background = element_rect(fill = "white", colour = NA))
salvar <- function(g, nome, w = 12, h = 7.5) ggsave(file.path(out, nome), g, width = w, height = h, dpi = 150, device = agg_png)
FONTE <- "Dados: logs das urnas do 2º turno, TSE (resultados.tse.jus.br). Horários de Brasília. Análise: Baia Hackerspace."
num <- character()

# ---- 1. biorregião de Itu: todas as urnas, votos de 15 em 15 minutos --------------------------------------------------
sp <- ler("saida/logs_urna_p3221_sp.csv")
q <- grep("^q\\d{4}$", names(sp), value = TRUE)
m <- sp[, c(list(nm = nm_mun[1], secoes = .N, votos = sum(votos, na.rm = TRUE), a17 = sum(votos_apos_17h, na.rm = TRUE),
                 s17 = sum(votos_apos_17h > 0, na.rm = TRUE), a1705 = sum(votos_apos_17h05, na.rm = TRUE),
                 ultimo = max(ultimo_voto, na.rm = TRUE), encerrar = max(encerrar, na.rm = TRUE)),
            lapply(.SD, sum, na.rm = TRUE)), by = mun, .SDcols = q][order(-votos)]
r <- melt(m[, c("nm", q), with = FALSE], id.vars = "nm", variable.name = "q", value.name = "votos", variable.factor = FALSE)[q <= "q1845"]
r[, `:=`(nm = nome(nm), h = rot_q(q))]
tot <- m[, .(secoes = sum(secoes), votos = sum(votos), a17 = sum(a17), s17 = sum(s17), a1705 = sum(a1705))]
g1 <- ggplot(r, aes(h, votos, fill = nm)) + geom_col(width = 0.85) +
  geom_vline(xintercept = 4.5, linetype = "dashed", colour = "grey20") +
  annotate("label", x = 4.6, y = max(r[, sum(votos), by = h]$V1) * 0.75, hjust = 0, size = 4.4, linewidth = 0, fill = alpha("white", 0.9),
           label = sprintf("Depois das 17h: %s votos\nem %s urnas, todos até %s.\nNenhuma urna da biorregião\nficou aberta até as 19h.",
                           tot$a17, tot$s17, sub(":", "h", substr(max(m$ultimo), 1, 5)))) +
  scale_fill_manual(values = c("#2c5bd6", "#c8102e", "#1f7a3f", "#9a6a00", "#7b3fb5"), name = NULL) +
  scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
  labs(title = "Itu e biorregião: a votação acabou às 17h",
       subtitle = sprintf("Votos registrados nas %s urnas de Itu, Salto, Cabreúva, Indaiatuba e Porto Feliz, de 15 em 15 minutos.", mil(tot$secoes)),
       x = NULL, y = "votos", caption = FONTE) + tema
salvar(g1, "1_regiao_itu.png")
num <- c(num, sprintf("Biorregião de Itu: %s urnas, %s votos; %s votos após 17h em %s urnas (%s%%); %s após 17h05; último voto %s; encerramento mais tardio %s",
                      mil(tot$secoes), mil(tot$votos), tot$a17, tot$s17, pp(100 * tot$a17 / tot$votos, 3), tot$a1705, max(m$ultimo), max(m$encerrar)))
num <- c(num, m[, sprintf("  %s: %s urnas, %s votos, %s após 17h, último %s, encerrou até %s", nome(nm), secoes, mil(votos), a17, ultimo, encerrar)])

# ---- 2. Brasil: amostra de urnas por UF -----------------------------------------------------------------------------
# Estimador de razão por UF: p = votos após 17h ÷ votos na amostra, com erro-padrão de amostra por conglomerado
# (a urna é o conglomerado). O total da UF é p × votos válidos; as UFs são sorteadas de forma independente, então as
# variâncias somam.
b <- ler("saida/logs_urna_p3221_br_amostra150.csv")[!is.na(votos) & votos > 0]
val <- fread("dados/validos_uf_2t_2026.csv")
ufs <- b[, {
  p <- sum(votos_apos_17h) / sum(votos); n <- .N
  ep <- sqrt(sum((votos_apos_17h - p * votos)^2) / (n - 1) / n) / mean(votos)
  list(urnas = n, votos = sum(votos), a17 = sum(votos_apos_17h), enc1855 = sum(encerrar >= "18:55:00"), p = p, ep = ep, ultimo = max(ultimo_voto))
}, by = uf]
ufs <- merge(ufs, val, by = "uf")[order(-p)]
t <- ufs[, .(urnas = sum(urnas), est = sum(p * validos), se = sqrt(sum((ep * validos)^2)), validos = sum(validos), lula = sum(lula), flavio = sum(flavio))]
# Os válidos por UF são da divulgação com 99,75% apurado; a diferença usa o resultado final (Lula 51,79% × Flávio 48,21%).
t[, `:=`(lo = max(0, est - 1.96 * se), hi = est + 1.96 * se, dif = (0.5179 - 0.4821) * validos)]
bb <- data.table(o = c("Diferença entre Lula e Flávio", "Todos os votos depois das 17h\n(estimativa, país inteiro)"), v = c(t$dif, t$est))
bb[, o := factor(o, levels = rev(o))]
g2 <- ggplot(bb, aes(v, o)) + geom_col(fill = c("#1f3a93", "#c8102e"), width = 0.6) +
  geom_text(aes(label = c(sprintf("%s milhões", pp(t$dif / 1e6)), sprintf("%s mil (de %s mil a %s mil)", mil(t$est / 1e3), mil(t$lo / 1e3), mil(t$hi / 1e3)))),
            hjust = -0.05, size = 5.2) +
  scale_x_continuous(labels = function(x) paste(pp(x / 1e6, 0), "mi"), expand = expansion(c(0, 0.45))) +
  labs(title = "Os votos depois das 17h não decidem nada",
       subtitle = sprintf("Mesmo que todos fossem para o mesmo candidato, a diferença seria %s vezes maior.\nEstimativa a partir de %s urnas sorteadas, %s por estado.",
                          mil(t$dif / t$est), mil(t$urnas), max(ufs$urnas)),
       x = "votos", y = NULL, caption = FONTE) + tema + theme(panel.grid.major.y = element_blank())
salvar(g2, "2_brasil.png", h = 5)
num <- c(num, sprintf("Brasil: %s urnas; estimativa %s votos após 17h (95%%: %s a %s) = %s%% de %s válidos; diferença %s = %s vezes",
                      mil(t$urnas), mil(t$est), mil(t$lo), mil(t$hi), pp(100 * t$est / t$validos, 3), mil(t$validos), mil(t$dif), mil(t$dif / t$est)))
num <- c(num, ufs[, sprintf("  %s: %s%% após 17h, %s de %s urnas encerradas a partir de 18h55, último voto %s", uf, pp(100 * p, 3), enc1855, urnas, ultimo)])

# ---- 3. cidades com urnas abertas até as 19h: todas as urnas ------------------------------------------------------
# "Aberta até as 19h" = o mesário só selecionou "Encerrar votação" a partir de 18h55.
d <- ler("saida/logs_urna_p3221_ba_pb_pe_rj_se.csv")
loc <- fread("dados/locais_secoes_2t_2026.csv")
d <- merge(d, loc[, .(uf, mun, zona, secao, nr_local, local)], by = c("uf", "mun", "zona", "secao"), all.x = TRUE)
d[, aberta := encerrar >= "18:55:00"]
q <- grep("^q\\d{4}$", names(d), value = TRUE); q30 <- q[q >= "q1730"]
C <- d[, c(list(uf = uf[1], nm = nm_mun[1], secoes = .N, votos = sum(votos, na.rm = TRUE), a17 = sum(votos_apos_17h, na.rm = TRUE),
                a1705 = sum(votos_apos_17h05, na.rm = TRUE), a1730 = sum(unlist(.SD[, q30, with = FALSE]), na.rm = TRUE),
                abertas = sum(aberta), locais = uniqueN(paste(zona, nr_local)[aberta]),   # nº do local só é único dentro da zona
                ab_a17 = sum(votos_apos_17h[aberta], na.rm = TRUE), ab_a1705 = sum(votos_apos_17h05[aberta], na.rm = TRUE),
                ab_zero = sum(aberta & votos_apos_17h == 0, na.rm = TRUE), ultimo = max(ultimo_voto, na.rm = TRUE)),
           lapply(.SD, sum, na.rm = TRUE)), by = mun, .SDcols = q][order(-abertas)]
ct <- C[, lapply(.SD, sum), .SDcols = c("secoes", "votos", "a17", "a1705", "a1730", "abertas", "locais", "ab_a17", "ab_a1705", "ab_zero")]
v <- data.table(h = rot_q(q), n = sapply(q, function(k) sum(C[[k]])))
g3 <- ggplot(v, aes(h, n, fill = h >= "17h00")) + geom_col(width = 0.85) +
  geom_text(data = v[h >= "17h00"], aes(label = mil(n)), vjust = -0.4, size = 4.2) +
  scale_fill_manual(values = c(`FALSE` = "#2c5bd6", `TRUE` = "#c8102e"), guide = "none") +
  scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
  labs(title = "Onde a votação foi até as 19h, quase ninguém votou depois das 17h",
       subtitle = sprintf("Votos de 15 em 15 minutos nas %s urnas de %s cidades (%s e outras).\n%s urnas (%s%%) ficaram abertas até as 19h. Depois das 17h15, foram %s votos no total, menos de 1 por urna aberta.",
                          mil(ct$secoes), nrow(C), paste(nome(C$nm[1:4]), collapse = ", "), mil(ct$abertas), pp(100 * ct$abertas / ct$secoes),
                          mil(sum(v[h >= "17h15"]$n))),
       x = NULL, y = "votos", caption = FONTE) + tema + theme(plot.subtitle = element_text(size = 11.5))
salvar(g3, "3_cidades_19h.png")
num <- c(num, sprintf("Cidades com urnas até 19h: %s urnas, %s votos; %s abertas até 19h (%s%%) em %s locais; nelas %s votos após 17h, %s após 17h05, %s sem nenhum voto após 17h",
                      mil(ct$secoes), mil(ct$votos), mil(ct$abertas), pp(100 * ct$abertas / ct$secoes), mil(ct$locais), mil(ct$ab_a17), mil(ct$ab_a1705), mil(ct$ab_zero)),
         sprintf("  todas as urnas das cidades: %s após 17h (%s%%), %s após 17h05, %s após 17h30", mil(ct$a17), pp(100 * ct$a17 / ct$votos, 3), mil(ct$a1705), mil(ct$a1730)))
num <- c(num, C[, sprintf("  %s (%s): %s urnas, %s abertas até 19h em %s locais, %s votos, %s após 17h05, %s após 17h30, último %s",
                          nome(nm), uf, secoes, abertas, locais, mil(votos), a1705, a1730, ultimo)])
enc <- d[, .N, by = .(faixa = fifelse(encerrar < "17:00:00", "antes das 17h", paste0(substr(encerrar, 1, 2), "h", sprintf("%02d", as.integer(substr(encerrar, 4, 5)) %/% 15 * 15))))][order(faixa)]
num <- c(num, "  horário de encerramento (faixas de 15 min):", enc[, sprintf("    %s: %s urnas", faixa, N)])

fwrite(d[(aberta)][order(uf, nm_mun, zona, secao), .(uf, cidade = nome(nm_mun), zona, secao, local, votos, votos_apos_17h, votos_apos_17h05,
                                                      ultimo_voto, encerrar, todos_votaram)], file.path(out, "urnas_abertas_19h.csv"))
writeLines(num, file.path(out, "numeros.txt")); cat(num, sep = "\n")
