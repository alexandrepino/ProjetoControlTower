-- gold.fato_projeto_semana: "está piorando?"
-- Uma linha por projeto e semana (sexta-feira), do início do projeto até hoje (16/10/2026).
-- O histórico do avanço vem do STATUS SEMANAL: Excel, ClickUp e Project só guardam o % de hoje.
-- PV, EV e AC são ACUMULADOS: nunca some semanas diferentes do mesmo projeto.

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
  CONSTRAINT pv_nao_negativo       EXPECT (pv >= 0)          ON VIOLATION FAIL UPDATE,
  CONSTRAINT ev_ate_o_orcamento    EXPECT (ev <= orcamento)  ON VIOLATION FAIL UPDATE
)
COMMENT 'Evolução semanal de cada projeto (uma linha por projeto e sexta-feira, do início até 16/10/2026): valor planejado (pv), valor agregado (ev, pelo % do status semanal), custo real acumulado (ac), SPI, CPI, EAC, farol do gerente e as horas disponíveis, apontadas e ociosas da semana. Responde se um projeto está melhorando ou piorando.'
AS
WITH projeto AS (
  SELECT
    projeto_id,
    CAST(orcamento_custo AS DOUBLE)                AS orcamento,
    date_add(date_trunc('WEEK', data_inicio), 4)   AS primeira_sexta
  FROM projetos
),

-- O calendário: todas as sextas do início do projeto até hoje.
calendario AS (
  SELECT
    projeto_id,
    orcamento,
    explode(sequence(CAST(primeira_sexta AS DATE), DATE'2026-10-16', INTERVAL 1 WEEK)) AS semana
  FROM projeto
),

-- PV: quanto do baseline de cada tarefa já deveria ter passado naquela sexta,
-- ponderado pelas horas da tarefa.
pv_semana AS (
  SELECT
    c.projeto_id,
    c.semana,
    SUM(t.horas * CASE
          WHEN t.fim_baseline <= t.inicio_baseline THEN IF(c.semana >= t.fim_baseline, 1, 0)
          ELSE greatest(0, least(1, datediff(c.semana, t.inicio_baseline) / datediff(t.fim_baseline, t.inicio_baseline)))
        END) / SUM(t.horas)                        AS fracao_planejada
  FROM calendario c
  JOIN tarefas t ON t.projeto_id = c.projeto_id
  GROUP BY c.projeto_id, c.semana
),

-- O status da sexta. Projeto concluído para de publicar: o último % (e farol) vale
-- para as semanas seguintes. A janela fica neste CTE, a conta no próximo.
status_preenchido AS (
  SELECT
    c.projeto_id,
    c.semana,
    last_value(s.pct_concluido, true) OVER janela AS pct_status,
    last_value(s.farol, true)         OVER janela AS farol_do_gerente
  FROM calendario c
  LEFT JOIN status_semanal s
    ON s.projeto_id = c.projeto_id AND s.data_status = c.semana
  WINDOW janela AS (PARTITION BY c.projeto_id ORDER BY c.semana
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),

-- AC: custo real acumulado de tudo que foi lançado até aquela sexta.
custo_dia AS (
  SELECT projeto_id, data, SUM(valor) AS valor
  FROM custos
  GROUP BY projeto_id, data
),
ac_semana AS (
  SELECT c.projeto_id, c.semana, SUM(d.valor) AS ac
  FROM calendario c
  JOIN custo_dia d ON d.projeto_id = c.projeto_id AND d.data <= c.semana
  GROUP BY c.projeto_id, c.semana
),

-- As horas do timesheet na semana (não acumuladas).
horas_semana AS (
  SELECT
    projeto_id,
    semana,
    SUM(horas_disponiveis)                                  AS horas_disponiveis,
    SUM(horas_apontadas)                                    AS horas_apontadas,
    SUM(greatest(horas_disponiveis - horas_apontadas, 0))   AS horas_ociosas
  FROM apontamentos
  GROUP BY projeto_id, semana
),

base AS (
  SELECT
    c.projeto_id,
    c.semana,
    c.orcamento,
    round(c.orcamento * coalesce(pv.fracao_planejada, 0), 2)   AS pv,
    round(c.orcamento * coalesce(st.pct_status, 0) / 100, 2)   AS ev,
    round(coalesce(ac.ac, 0), 2)                               AS ac,
    st.farol_do_gerente,
    coalesce(h.horas_disponiveis, 0)                           AS horas_disponiveis,
    coalesce(h.horas_apontadas, 0)                             AS horas_apontadas,
    coalesce(h.horas_ociosas, 0)                               AS horas_ociosas
  FROM calendario c
  LEFT JOIN pv_semana pv         USING (projeto_id, semana)
  LEFT JOIN status_preenchido st USING (projeto_id, semana)
  LEFT JOIN ac_semana ac         USING (projeto_id, semana)
  LEFT JOIN horas_semana h       USING (projeto_id, semana)
)
SELECT
  projeto_id,
  semana,
  orcamento,
  pv,
  ev,
  ac,
  round(try_divide(ev, pv), 4)                                  AS spi,
  round(try_divide(ev, ac), 4)                                  AS cpi,
  round(try_divide(orcamento, try_divide(ev, ac)), 2)           AS eac,
  farol_do_gerente,
  horas_disponiveis,
  horas_apontadas,
  horas_ociosas
FROM base;
