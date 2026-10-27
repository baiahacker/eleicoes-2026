# Eleições 2026 · Baia Hackerspace

Dados e análises da Baia Hackerspace sobre as eleições de 2026, feitos a partir de arquivos públicos do TSE.
Cada análise vira um post no blog, e aqui ficam o código e os dados para qualquer pessoa conferir ou refazer.

## Votos depois das 17h no 2º turno

No 2º turno, em 25/10/2026, a votação foi prorrogada até as 19h em alguns lugares. A pergunta era se isso pesou no
resultado. Para responder, contamos a hora de cada voto nos logs das urnas.

Post publicado: [O mito do impacto da prorrogação das Eleições 2026](https://baiahacker.space/o-mito-do-impacto-da-prorrogacao-das-eleicoes-2026/)
(texto em [`posts/2026-10-prorrogacao/post.md`](posts/2026-10-prorrogacao/post.md))

Os principais números:

| recorte | urnas | votos depois das 17h | % dos votos |
|---|---:|---:|---:|
| Itu, Salto, Cabreúva, Indaiatuba e Porto Feliz (todas as urnas) | 1.439 | 62 | 0,015% |
| Brasil (estimativa por amostra de 150 urnas por UF) | 4.050 | cerca de 28 mil (22 mil a 34 mil) | 0,023% |
| 9 cidades com urnas abertas até as 19h (todas as urnas) | 25.639 | 4.778 | 0,061% |

Nas 9 cidades, 3.496 urnas ficaram abertas até as 19h. Elas receberam 2.001 votos depois das 17h05, e mais da
metade delas não recebeu nenhum voto depois das 17h. A diferença entre Lula e Flávio foi de 4,4 milhões de votos.

## O que há aqui

```
scripts/logs_urna.py         baixa os logs das urnas do TSE e resume a hora dos votos por seção
scripts/prorrogacao.R        números e imagens do post sobre a prorrogação
saida/                       resultado do logs_urna.py, uma linha por seção (CSV)
dados/                       tabelas auxiliares do TSE (votos válidos por UF, local de votação de cada seção)
posts/                       os posts, com imagens e números
```

## Os logs das urnas

Toda urna eletrônica grava um log com cada evento do dia, com data e hora. O TSE publica esse log por seção, junto
com o boletim de urna, em
`https://resultados.tse.jus.br/oficial/ele2026/arquivo-urna/<pleito>/`.
No 2º turno de 2026 o pleito é o 3221; no 1º turno, o 3220.

O log registra cada voto como "O voto do eleitor foi computado", mas não registra em quem o voto foi, porque o voto
é secreto. Por isso dá para saber **a que horas** se votou, mas não **em quem**.

O `logs_urna.py`:

- lê a lista de seções da UF (`config/<uf>/<uf>-p<pleito>-cs.json`);
- para cada seção, baixa o índice (`...-aux.json`) e o arquivo `log.jez` de cada urna usada;
- abre o `log.jez`, que é um zip com o `logd.dat` em latin1. Às vezes ele traz dentro o log de uma urna anterior, e
  todos os logs entram na conta;
- fica só com os eventos da data pedida, porque a mesma urna guarda o 1º e o 2º turno;
- converte a hora para Brasília. AC fica 2 horas atrás; AM, RO, RR, MT e MS ficam 1 hora atrás. No oeste do
  Amazonas, a urna fica pronta perto das 6h locais, e o script usa 2 horas de diferença;
- pula as seções agregadas, que votam na urna da seção principal.

Uso:

```bash
python3 scripts/logs_urna.py ele2026 3221 sp 25/10/2026 65790 70050 62693 65110 69132
python3 scripts/logs_urna.py ele2026 3221 br 25/10/2026 todos --amostra=150
python3 scripts/logs_urna.py ele2026 3221 ba,pb,pe,rj,se 25/10/2026 38490 20516 23574 23817 24139 25313 60011 31054 31330 --fios=12
```

Os argumentos são o ciclo, o pleito, a UF (ou várias separadas por vírgula, ou `br`), a data e os códigos TSE dos
municípios (ou `todos`).

- `--amostra=N` sorteia N seções por UF. A semente é fixa, então o mesmo comando sorteia as mesmas seções.
- `--fios=N` define quantos downloads rodam ao mesmo tempo. O padrão é 6. O TSE bloqueia por alguns minutos quem
  passa de 100 pedidos por segundo, então não vale aumentar muito.

Os logs baixados ficam em `brutos/`, que não vai para o repositório. Se o download parar, rodar de novo aproveita o
que já foi baixado. O resumo sai em `saida/logs_urna_p<pleito>_<rótulo>.csv`.

As colunas do CSV:

| coluna | o que é |
|---|---|
| `uf`, `mun`, `nm_mun`, `zona`, `secao` | identificação da seção (código TSE do município) |
| `status` | situação da seção na divulgação (`Totalizada`, `Recebida`) |
| `votos` | votos computados no dia |
| `primeiro_voto`, `ultimo_voto` | hora do primeiro e do último voto |
| `votos_apos_17h`, `votos_apos_17h05` | votos a partir das 17h00 e das 17h05 |
| `pronta` | hora em que a urna ficou pronta para receber votos |
| `encerrar` | hora em que o mesário encerrou a votação (o último registro, se houver mais de um) |
| `todos_votaram` | resposta do mesário à pergunta "Todas as pessoas presentes já votaram?" |
| `fuso` | horas de diferença para Brasília usadas na conversão |
| `logs` | quantos logs a seção teve (mais de 1 quando a urna foi trocada) |
| `v07` … `v21` | votos em cada hora (v17 = das 17h00 às 17h59) |
| `q1600` … `q1945` | votos de 15 em 15 minutos, das 16h às 20h (q1700 = das 17h00 às 17h14) |

Todos os horários estão no horário de Brasília.

## Como refazer o post

Requer Python 3.8+ (só biblioteca padrão; o `7z` é usado se algum log vier em 7z) e R com os pacotes `data.table`,
`ggplot2`, `scales` e `ragg`.

```bash
python3 scripts/logs_urna.py ...                 # os três comandos acima (ou use os CSVs que já estão em saida/)
Rscript scripts/prorrogacao.R                    # imagens, numeros.txt e urnas_abertas_19h.csv
```

A estimativa nacional usa um estimador de razão por UF: a fração de votos depois das 17h na amostra, multiplicada
pelos votos válidos da UF. O erro-padrão trata cada urna como um conglomerado. Como as UFs são sorteadas de forma
independente, as variâncias somam no total do país.

## De onde vêm os dados

- `saida/`: logs das urnas do 2º turno, baixados de resultados.tse.jus.br em 26/10/2026.
- `dados/validos_uf_2t_2026.csv`: votos de Lula e Flávio por UF, da divulgação oficial do TSE com 99,75% das
  seções apuradas (21h13 de 25/10/2026). A diferença entre os candidatos usa o resultado final, de 51,79% a 48,21%.
- `dados/locais_secoes_2t_2026.csv`: local de votação, coordenadas e eleitorado de cada seção das cidades estudadas,
  do arquivo de eleitorado por local de votação de 2026 do TSE (dadosabertos.tse.jus.br).

## Limites

- O log diz a hora do voto, não em quem se votou.
- "Urna aberta até as 19h" quer dizer que o mesário só encerrou a votação a partir de 18h55.
- O número nacional é uma estimativa por amostra, com faixa de 95% de confiança. As cidades da biorregião de Itu e as
  9 cidades com urnas até as 19h foram contadas urna por urna, sem amostra.
- As 9 cidades são as que apareceram na amostra nacional. Pode haver outras cidades com urnas abertas até as 19h
  que o sorteio não pegou; os votos delas já estão dentro da estimativa nacional.

## Licença

Os textos e as imagens em [`posts/`](posts/) estão sob a licença
[Creative Commons Atribuição 4.0 Internacional (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/deed.pt-br),
com o texto completo em [`posts/LICENSE`](posts/LICENSE). Você pode copiar, adaptar e republicar, inclusive para fins
comerciais, desde que dê o crédito: "Baia Hackerspace", com link para o post original ou para este repositório.

Os dados de `saida/` e `dados/` vêm de arquivos públicos do TSE.
