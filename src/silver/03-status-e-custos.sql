-- silver.status_semanal e silver.custos.

-- O status que o gerente manda toda sexta. É dele que sai o histórico do avanço.
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_conhecido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal (toda sexta) de cada projeto: % concluído declarado pelo gerente, farol do gerente (verde, amarelo, vermelho) e o texto livre com entregas e bloqueios. status_vazio marca os textos sem conteúdo ('''', N/A, ver ata da reunião), que são mantidos.'
AS
SELECT
  projeto_id,
  to_date(data_status, 'yyyy-MM-dd')                  AS data_status,
  gerente,
  lower(trim(farol))                                  AS farol,          -- 'Verde', 'VERDE' -> 'verde'
  CAST(pct_concluido AS INT)                          AS pct_concluido,
  texto_status,
  -- Status sem conteúdo: NÃO descarta, sinaliza.
  coalesce(lower(trim(texto_status)) IN ('', 'n/a', 'ver ata da reunião'), true) AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;


-- Os lançamentos de custo real. O teste: a soma continua R$ 193,35 mi.
CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo real por projeto (pessoal, consultoria, cloud, licenças, despesas). valor é líquido: estornos ficam como valor negativo, marcados em estorno. semana é a sexta-feira da semana do lançamento, para cruzar com o status semanal.'
AS
SELECT
  lancamento_id,
  projeto_id,
  to_date(data, 'yyyy-MM-dd')                                 AS data,
  date_add(date_trunc('WEEK', to_date(data, 'yyyy-MM-dd')), 4) AS semana,   -- a sexta da semana
  categoria,
  descricao,
  -- 671 valores com vírgula decimal: replace ANTES do CAST. Nunca try_cast:
  -- ele devolveria NULL e jogaria R$ 5,4 mi fora sem erro nenhum.
  CAST(replace(valor, ',', '.') AS DECIMAL(18,2))             AS valor,
  CAST(replace(valor, ',', '.') AS DECIMAL(18,2)) < 0         AS estorno,
  centro_custo
FROM lakehouse_vertice.bronze.custos;
