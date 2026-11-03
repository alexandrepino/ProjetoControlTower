-- Testes de qualidade: rodam depois do medalhão e QUEBRAM o job se algo estiver errado.
-- Cada teste devolve 'ok' ou chama raise_error() dizendo o que falhou.


-- 1 · os 60 projetos têm cronograma na silver.tarefas
SELECT 'teste 1: 60 projetos com cronograma' AS teste,
  CASE WHEN (SELECT COUNT(DISTINCT projeto_id) FROM lakehouse_vertice.silver.tarefas) = 60 THEN 'ok'
       ELSE raise_error('teste 1 falhou: nem todos os 60 projetos têm tarefas na silver.tarefas') END AS resultado;


-- 2 · cada projeto veio de UMA ferramenta, a do cadastro do PMO
SELECT 'teste 2: uma ferramenta por projeto, a do cadastro' AS teste,
  CASE WHEN (
    SELECT COUNT(*)
    FROM (SELECT projeto_id, COUNT(DISTINCT ferramenta) AS n, MAX(ferramenta) AS ferramenta
          FROM lakehouse_vertice.silver.tarefas GROUP BY projeto_id) t
    JOIN lakehouse_vertice.silver.projetos p USING (projeto_id)
    WHERE t.n <> 1 OR t.ferramenta <> p.ferramenta
  ) = 0 THEN 'ok'
  ELSE raise_error('teste 2 falhou: há projeto com tarefas de mais de uma ferramenta ou de ferramenta diferente da do cadastro') END AS resultado;


-- 3 · as horas do Excel na silver = a soma das linhas de TOTAL das planilhas
SELECT 'teste 3: horas do Excel = linhas de TOTAL' AS teste,
  CASE WHEN abs(
    (SELECT SUM(horas) FROM lakehouse_vertice.silver.tarefas WHERE ferramenta = 'excel')
    - (SELECT SUM(CAST(replace(horas_previstas, 'h', '') AS DOUBLE))
       FROM lakehouse_vertice.bronze.excel_tarefas WHERE tarefa = 'TOTAL')
  ) < 0.01 THEN 'ok'
  ELSE raise_error('teste 3 falhou: as horas do Excel na silver não batem com as linhas de TOTAL (a linha de TOTAL entrou ou alguma hora não converteu)') END AS resultado;


-- 4 · uma linha por pessoa na silver
SELECT 'teste 4: uma linha por pessoa' AS teste,
  CASE WHEN (SELECT COUNT(*) = COUNT(DISTINCT colaborador_id) FROM lakehouse_vertice.silver.colaboradores) THEN 'ok'
       ELSE raise_error('teste 4 falhou: há colaborador duplicado na silver.colaboradores') END AS resultado;


-- 5 · a CodeForge virou um fornecedor só
SELECT 'teste 5: CodeForge é um fornecedor só' AS teste,
  CASE WHEN (SELECT COUNT(DISTINCT fornecedor) FROM lakehouse_vertice.silver.entregas_fornecedor
             WHERE replace(lower(fornecedor), ' ', '') LIKE '%codeforge%') = 1 THEN 'ok'
       ELSE raise_error('teste 5 falhou: a CodeForge aparece com mais de um nome na silver.entregas_fornecedor') END AS resultado;


-- 6 · a limpeza não mudou o custo total (bronze com replace = silver)
SELECT 'teste 6: custo total igual na bronze e na silver' AS teste,
  CASE WHEN (SELECT SUM(CAST(replace(valor, ',', '.') AS DECIMAL(18,2))) FROM lakehouse_vertice.bronze.custos)
          = (SELECT SUM(valor) FROM lakehouse_vertice.silver.custos) THEN 'ok'
       ELSE raise_error('teste 6 falhou: a soma dos custos mudou entre a bronze e a silver') END AS resultado;


-- 7 · os 60 projetos têm fotografia de hoje
SELECT 'teste 7: 60 projetos na fotografia de hoje' AS teste,
  CASE WHEN (SELECT COUNT(*) = 60 AND COUNT(DISTINCT projeto_id) = 60 FROM lakehouse_vertice.gold.projeto_situacao_atual) THEN 'ok'
       ELSE raise_error('teste 7 falhou: a gold.projeto_situacao_atual não tem exatamente uma linha para cada um dos 60 projetos') END AS resultado;


-- 8 · todo projeto em andamento tem SPI e CPI
SELECT 'teste 8: SPI e CPI em todo projeto em andamento' AS teste,
  CASE WHEN (SELECT COUNT(*) FROM lakehouse_vertice.gold.projeto_situacao_atual
             WHERE status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL)) = 0 THEN 'ok'
       ELSE raise_error('teste 8 falhou: há projeto em andamento sem SPI ou sem CPI') END AS resultado;


-- 9 · o EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)
SELECT 'teste 9: EV de hoje (status x ferramentas)' AS teste,
  CASE WHEN abs(
    (SELECT SUM(ev) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16')
    / (SELECT SUM(ev) FROM lakehouse_vertice.gold.projeto_situacao_atual) - 1
  ) < 0.01 THEN 'ok'
  ELSE raise_error('teste 9 falhou: o EV de hoje pelo status semanal difere mais de 1% do EV pelas ferramentas') END AS resultado;


-- 10 · AC de hoje no fato = soma dos lançamentos até hoje
SELECT 'teste 10: AC de hoje = lançamentos até hoje' AS teste,
  CASE WHEN abs(
    (SELECT SUM(ac) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16')
    - (SELECT SUM(valor) FROM lakehouse_vertice.silver.custos WHERE data <= DATE'2026-10-16')
  ) < 1 THEN 'ok'
  ELSE raise_error('teste 10 falhou: o AC de hoje no fato não bate com a soma dos lançamentos até 16/10/2026') END AS resultado;
