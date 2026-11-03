-- silver.projetos: o cadastro do PMO, limpo e tipado.
-- É também o DE-PARA da integração: quem diz que a lista 901200023757 do ClickUp
-- é o PRJ-003 é a coluna codigo_ferramenta deste cadastro.

CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida   EXPECT (data_inicio IS NOT NULL)                          ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_conhecida EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos da Vértice (PMO): cliente, segmento, contrato, orçamento, datas, gerente e a ferramenta onde o projeto é controlado (excel, clickup ou msproject) com o código nela (de-para da integração das tarefas).'
AS
SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,

  -- A ferramenta vem escrita de 8 jeitos ('MS Project', 'Project', 'Planilha', 'Clickup'...).
  CASE
    WHEN lower(ferramenta) LIKE '%click%'                                   THEN 'clickup'
    WHEN lower(ferramenta) LIKE '%project%'                                 THEN 'msproject'
    WHEN lower(ferramenta) LIKE '%excel%' OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
  END                                               AS ferramenta,
  ferramenta                                        AS ferramenta_como_veio,
  nullif(trim(codigo_ferramenta), '')               AS codigo_ferramenta,

  CAST(valor_contrato  AS DECIMAL(18,2))            AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(18,2))            AS orcamento_custo,

  -- Datas em yyyy-MM-dd e dd/MM/yyyy na mesma coluna.
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'),       try_to_date(data_inicio, 'dd/MM/yyyy'))       AS data_inicio,
  coalesce(try_to_date(data_fim_baseline, 'yyyy-MM-dd'), try_to_date(data_fim_baseline, 'dd/MM/yyyy')) AS data_fim_baseline,

  status,
  gerente_projeto
FROM lakehouse_vertice.bronze.projetos;
