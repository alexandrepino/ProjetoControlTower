-- Conferência da bronze: a primeira tarefa do job vertice_farol.
-- Antes de construir a silver, confere se as 9 tabelas da bronze chegaram inteiras
-- (contagens do seed 42). bronze.feriados fica de fora: cresce a cada execução.
-- Uma linha por tabela com o esperado e o obtido. Se alguma divergir, a tarefa
-- falha com raise_error() e o medalhão nem começa.

WITH esperado (tabela, esperado) AS (
  VALUES
    ('projetos',             60),
    ('status_semanal',       3911),
    ('excel_tarefas',        1663),
    ('clickup_tarefas',      2119),
    ('msproject_tarefas',    1260),
    ('colaboradores',        523),
    ('apontamentos',         30883),
    ('custos',               23640),
    ('entregas_fornecedor',  640)
),
obtido AS (
  SELECT 'projetos'            AS tabela, COUNT(*) AS obtido FROM lakehouse_vertice.bronze.projetos
  UNION ALL SELECT 'status_semanal',      COUNT(*) FROM lakehouse_vertice.bronze.status_semanal
  UNION ALL SELECT 'excel_tarefas',       COUNT(*) FROM lakehouse_vertice.bronze.excel_tarefas
  UNION ALL SELECT 'clickup_tarefas',     COUNT(*) FROM lakehouse_vertice.bronze.clickup_tarefas
  UNION ALL SELECT 'msproject_tarefas',   COUNT(*) FROM lakehouse_vertice.bronze.msproject_tarefas
  UNION ALL SELECT 'colaboradores',       COUNT(*) FROM lakehouse_vertice.bronze.colaboradores
  UNION ALL SELECT 'apontamentos',        COUNT(*) FROM lakehouse_vertice.bronze.apontamentos
  UNION ALL SELECT 'custos',              COUNT(*) FROM lakehouse_vertice.bronze.custos
  UNION ALL SELECT 'entregas_fornecedor', COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  e.tabela,
  e.esperado,
  o.obtido,
  CASE
    WHEN o.obtido = e.esperado THEN 'ok'
    ELSE raise_error(concat(
      'Conferência da bronze falhou: lakehouse_vertice.bronze.', e.tabela,
      ' tem ', coalesce(CAST(o.obtido AS STRING), 'nenhuma'), ' linhas, esperado ', e.esperado,
      '. Olhe a saída da ingestão (tarefa ingestao_data_lake; hoje, o notebook imersao_claude/ingestao_s3).'
    ))
  END AS resultado
FROM esperado e
LEFT JOIN obtido o USING (tabela)
ORDER BY e.tabela
