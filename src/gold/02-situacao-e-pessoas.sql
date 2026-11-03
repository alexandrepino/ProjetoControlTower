-- gold.projeto_situacao_atual e gold.utilizacao_pessoa_semana.


-- "Quais projetos estão atrasados, de quais clientes, e quanto vai custar?"
-- A fotografia de hoje (16/10/2026): KPIs sobre o % de HOJE das ferramentas (silver.tarefas).
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual
COMMENT 'Fotografia de cada um dos 60 projetos em 16/10/2026: cadastro (cliente, segmento, tipo, ferramenta, gerente, contrato, orçamento, prazo) e os KPIs de hoje calculados sobre as tarefas das ferramentas: pv, ev, ac, SPI, CPI, EAC, estouro previsto, margem projetada, atraso e término projetados, situação (concluído, crítico, atenção, ok), farol do gerente, farol calculado pelo SPI e melancia (farol verde com SPI < 0,9).'
AS
WITH progresso AS (
  -- Frações de hoje ponderadas pelas horas das tarefas.
  SELECT
    projeto_id,
    SUM(horas * pct_concluido / 100) / SUM(horas)  AS fracao_agregada,
    SUM(horas * CASE
          WHEN fim_baseline <= inicio_baseline THEN IF(DATE'2026-10-16' >= fim_baseline, 1, 0)
          ELSE greatest(0, least(1, datediff(DATE'2026-10-16', inicio_baseline) / datediff(fim_baseline, inicio_baseline)))
        END) / SUM(horas)                          AS fracao_planejada
  FROM tarefas
  GROUP BY projeto_id
),
custo_real AS (
  SELECT projeto_id, SUM(valor) AS ac
  FROM custos
  WHERE data <= DATE'2026-10-16'
  GROUP BY projeto_id
),
farol_hoje AS (
  -- Um status por projeto em 16/10: quem já concluiu não publica (fica nulo).
  SELECT projeto_id, farol
  FROM status_semanal
  WHERE data_status = DATE'2026-10-16'
),
kpis AS (
  SELECT
    p.*,
    CAST(p.orcamento_custo AS DOUBLE)                                 AS orcamento,
    datediff(p.data_fim_baseline, p.data_inicio)                      AS duracao_baseline_dias,
    round(CAST(p.orcamento_custo AS DOUBLE) * g.fracao_planejada, 2)  AS pv,
    round(CAST(p.orcamento_custo AS DOUBLE) * g.fracao_agregada, 2)   AS ev,
    round(coalesce(c.ac, 0), 2)                                       AS ac,
    f.farol                                                           AS farol_do_gerente
  FROM projetos p
  LEFT JOIN progresso  g USING (projeto_id)
  LEFT JOIN custo_real c USING (projeto_id)
  LEFT JOIN farol_hoje f USING (projeto_id)
),
indices AS (
  SELECT
    *,
    round(try_divide(ev, pv), 4)                         AS spi,
    round(try_divide(ev, ac), 4)                         AS cpi,
    round(try_divide(orcamento, try_divide(ev, ac)), 2)  AS eac
  FROM kpis
)
SELECT
  concat(projeto_id, ' · ', nome_projeto)                               AS projeto,
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  CAST(valor_contrato AS DOUBLE)                                        AS valor_contrato,
  orcamento,
  data_inicio,
  data_fim_baseline,
  duracao_baseline_dias,
  status,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  round(greatest(eac - orcamento, 0), 2)                                AS estouro_previsto,
  round(try_divide(valor_contrato - eac, valor_contrato), 4)            AS margem_projetada,
  round(try_divide(duracao_baseline_dias, spi) - duracao_baseline_dias) AS atraso_projetado_dias,
  date_add(data_inicio, CAST(round(try_divide(duracao_baseline_dias, spi)) AS INT)) AS termino_projetado,
  -- Regra de corte da Vértice: < 0,9 atenção, < 0,8 crítico.
  CASE
    WHEN status <> 'em_andamento'  THEN 'concluído'
    WHEN spi < 0.8 OR cpi < 0.8    THEN 'crítico'
    WHEN spi < 0.9 OR cpi < 0.9    THEN 'atenção'
    ELSE 'ok'
  END                                                                   AS situacao,
  farol_do_gerente,
  -- Farol pelo número (manual da Vértice), lado a lado com o do gerente.
  CASE
    WHEN spi >= 0.95 THEN 'verde'
    WHEN spi >= 0.90 THEN 'amarelo'
    ELSE 'vermelho'
  END                                                                   AS farol_calculado,
  coalesce(status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9, false) AS melancia
FROM indices;


-- "Tenho gente parada enquanto outro projeto pede gente?"
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Utilização do timesheet por pessoa, projeto e semana (sexta-feira): nome, papel, senioridade, horas disponíveis, apontadas e ociosas, utilização (apontadas ÷ disponíveis), custo das horas ociosas e o SPI do projeto naquela semana.'
AS
SELECT
  a.colaborador_id,
  c.nome,
  c.papel,
  c.senioridade,
  a.projeto_id,
  a.semana,
  a.horas_disponiveis,
  a.horas_apontadas,
  greatest(a.horas_disponiveis - a.horas_apontadas, 0)                         AS horas_ociosas,
  round(try_divide(a.horas_apontadas, a.horas_disponiveis), 4)                 AS utilizacao,
  round(greatest(a.horas_disponiveis - a.horas_apontadas, 0) * c.custo_hora, 2) AS custo_ocioso,
  f.spi                                                                        AS spi_do_projeto
FROM apontamentos a
LEFT JOIN colaboradores c USING (colaborador_id)
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
  ON f.projeto_id = a.projeto_id AND f.semana = a.semana;
