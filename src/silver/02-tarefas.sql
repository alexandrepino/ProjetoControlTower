-- silver.tarefas: AS TRÊS FERRAMENTAS VIRAM UMA.
-- Cada ferramenta vira uma visão temporária com as MESMAS colunas (o contrato):
--   projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
--   inicio_baseline, fim_baseline, inicio_real, fim_real, pct_como_veio, horas,
--   status_na_ferramenta
-- e as três são empilhadas com UNION ALL. A ferramenta nova de amanhã é só mais uma visão.
-- O projeto vem do cadastro do PMO (silver.projetos.codigo_ferramenta), não de código.


-- ── Excel: 20 planilhas, tudo texto ─────────────────────────────────────────────
CREATE TEMPORARY VIEW tarefas_excel AS
WITH de_para AS (
  SELECT projeto_id, codigo_ferramenta FROM projetos WHERE ferramenta = 'excel'
),
limpo AS (
  SELECT
    -- De-para pelo nome do arquivo; se o código estiver vazio ou o arquivo chegou
    -- sem acento ('Core bancario' x 'Core bancário'), o PRJ-xxx do próprio nome.
    coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
    e.*
  FROM lakehouse_vertice.bronze.excel_tarefas e
  LEFT JOIN de_para p ON p.codigo_ferramenta = e.arquivo
  WHERE e.tarefa <> 'TOTAL'   -- a linha de TOTAL dobraria as horas da planilha
)
SELECT
  projeto_id,
  'excel'                                           AS ferramenta,
  CAST(id AS STRING)                                AS id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  -- Data em texto dd/MM/yyyy OU número de série do Excel (dias desde 30/12/1899).
  CASE WHEN inicio_previsto  LIKE '%/%' THEN to_date(inicio_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(inicio_previsto AS DOUBLE) AS INT)) END  AS inicio_baseline,
  CASE WHEN termino_previsto LIKE '%/%' THEN to_date(termino_previsto, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(termino_previsto AS DOUBLE) AS INT)) END AS fim_baseline,
  CASE WHEN inicio_real      LIKE '%/%' THEN to_date(inicio_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(inicio_real AS DOUBLE) AS INT)) END      AS inicio_real,
  CASE WHEN termino_real     LIKE '%/%' THEN to_date(termino_real, 'dd/MM/yyyy')
       ELSE date_add(DATE'1899-12-30', CAST(CAST(termino_real AS DOUBLE) AS INT)) END     AS fim_real,
  -- '45%' / '10,5%' viram 45 / 10.5; sem '%' é fração (0.45 -> 45).
  CASE WHEN contains(pct_concluido, '%')
       THEN CAST(replace(replace(pct_concluido, '%', ''), ',', '.') AS DOUBLE)
       ELSE CAST(pct_concluido AS DOUBLE) * 100 END                                       AS pct_como_veio,
  CAST(replace(horas_previstas, 'h', '') AS DOUBLE)                                       AS horas,
  CAST(NULL AS STRING)                                                                    AS status_na_ferramenta
FROM limpo;


-- ── ClickUp: 25 listas, datas em milissegundos, % e baseline em custom_fields ──
CREATE TEMPORARY VIEW tarefas_clickup AS
WITH de_para AS (
  SELECT projeto_id, codigo_ferramenta, nome_projeto FROM projetos WHERE ferramenta = 'clickup'
),
campos AS (
  SELECT
    c.*,
    filter(c.custom_fields, f -> f.name = 'Fase')[0].value             AS cf_fase,
    filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value    AS cf_pct,
    filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value  AS cf_inicio_baseline,
    filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value     AS cf_fim_baseline
  FROM lakehouse_vertice.bronze.clickup_tarefas c
)
SELECT
  -- De-para pelo list_id; se o código faltar no cadastro, pelo nome da lista.
  coalesce(por_codigo.projeto_id, por_nome.projeto_id)                    AS projeto_id,
  'clickup'                                                               AS ferramenta,
  c.id                                                                    AS id_na_ferramenta,
  c.cf_fase                                                               AS fase,
  c.name                                                                  AS tarefa,
  c.assignees[0].username                                                 AS responsavel,
  to_date(timestamp_millis(CAST(c.cf_inicio_baseline AS BIGINT)))         AS inicio_baseline,
  to_date(timestamp_millis(CAST(c.cf_fim_baseline    AS BIGINT)))         AS fim_baseline,
  to_date(timestamp_millis(CAST(c.start_date         AS BIGINT)))         AS inicio_real,
  to_date(timestamp_millis(CAST(c.date_done          AS BIGINT)))         AS fim_real,
  CAST(c.cf_pct AS DOUBLE)                                                AS pct_como_veio,
  c.time_estimate / 3600000.0                                             AS horas,
  -- Status escrito de 12 jeitos.
  CASE
    WHEN lower(c.status.status) IN ('done', 'closed') OR lower(c.status.status) LIKE 'conclu%' THEN 'concluida'
    WHEN lower(c.status.status) IN ('to do', 'backlog', 'a fazer')                             THEN 'a_fazer'
    WHEN lower(c.status.status) IN ('in progress', 'em andamento', 'review', 'doing')          THEN 'em_andamento'
  END                                                                     AS status_na_ferramenta
FROM campos c
LEFT JOIN de_para por_codigo ON por_codigo.codigo_ferramenta = c.list_id
LEFT JOIN de_para por_nome   ON por_nome.codigo_ferramenta IS NULL AND por_nome.nome_projeto = c.list_name;


-- ── MS Project: 15 XML, tarefas-resumo e a fase escondida na hierarquia ─────────
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH com_fase AS (
  -- A fase é a última tarefa-resumo de nível 1 antes da tarefa (na ordem do UID).
  -- A janela roda ANTES do filtro Summary = 0, senão as fases somem.
  SELECT
    m.*,
    last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
      OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase
  FROM lakehouse_vertice.bronze.msproject_tarefas m
)
SELECT
  p.projeto_id,
  'msproject'                                                  AS ferramenta,
  CAST(t.UID AS STRING)                                        AS id_na_ferramenta,
  t.fase,
  t.Name                                                       AS tarefa,
  CAST(NULL AS STRING)                                         AS responsavel,
  to_date(t.Baseline.Start)                                    AS inicio_baseline,
  to_date(t.Baseline.Finish)                                   AS fim_baseline,
  to_date(t.ActualStart)                                       AS inicio_real,
  to_date(t.ActualFinish)                                      AS fim_real,
  CAST(t.PercentComplete AS DOUBLE)                            AS pct_como_veio,
  CAST(regexp_extract(t.Work, 'PT([0-9]+)H', 1) AS DOUBLE)     AS horas,   -- 'PT40H0M0S' -> 40
  CAST(NULL AS STRING)                                         AS status_na_ferramenta
FROM com_fase t
LEFT JOIN projetos p ON p.ferramenta = 'msproject' AND p.codigo_ferramenta = t.arquivo
WHERE t.Summary = 0;   -- as tarefas-resumo somam as de baixo: contariam em dobro


-- ── A tabela integrada ─────────────────────────────────────────────────────────
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto   EXPECT (projeto_id IS NOT NULL)            ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100)   ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas   EXPECT (horas > 0)                         ON VIOLATION FAIL UPDATE
)
COMMENT 'Tarefas de todos os projetos num modelo só: integra as planilhas Excel (20 projetos), as listas do ClickUp (25) e os cronogramas do MS Project (15). Uma linha por tarefa de verdade (sem linha de TOTAL e sem tarefas-resumo), com fase, responsável, datas baseline e reais, % concluído (0 a 100) e horas previstas.'
AS
WITH todas AS (
  SELECT * FROM tarefas_excel
  UNION ALL
  SELECT * FROM tarefas_clickup
  UNION ALL
  SELECT * FROM tarefas_msproject
)
SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
  projeto_id,
  ferramenta,
  id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  inicio_baseline,
  fim_baseline,
  inicio_real,
  fim_real,
  least(pct_como_veio, 100)                                 AS pct_concluido,
  pct_como_veio > 100                                       AS pct_veio_acima_de_100,
  pct_como_veio,
  horas,
  status_na_ferramenta
FROM todas;
