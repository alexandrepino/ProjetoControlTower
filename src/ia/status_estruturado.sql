-- gold.status_estruturado: o texto livre do status semanal vira coluna.
-- "Por que o projeto está atrasado, quem destrava e quanto custa em dias?"
--
-- A tabela ACUMULA: cada execução só classifica os status que ainda não estão nela
-- (a IA leva ~5 s por texto e não pode ser refeita toda segunda).
-- Três métodos, do mais barato ao mais caro:
--   regra         status vazio ou "sem bloqueios": não precisa ler o texto
--   ia            últimos 90 dias (desde 18/07/2026): ai_classify + ai_extract (versão 2.0)
--   palavra_chave o histórico mais antigo: RLIKE no trecho de bloqueios
-- Atenção: a sql_task corta o arquivo em todo ponto e vírgula, então não use esse
-- caractere dentro de textos ou comentários.


-- a · a tabela (CREATE TABLE IF NOT EXISTS, nunca CREATE OR REPLACE: ela acumula)
CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
  projeto_id        STRING    COMMENT 'Projeto (PRJ-xxx), chave do cadastro em gold.projeto_situacao_atual',
  data_status       DATE      COMMENT 'Sexta-feira do status semanal',
  farol             STRING    COMMENT 'Farol informado pelo gerente: verde, amarelo ou vermelho',
  causa_bloqueio    STRING    COMMENT 'Causa do bloqueio: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio, nao_reportado (status vazio) ou outro (palavra-chave sem correspondência)',
  bloqueio          STRING    COMMENT 'O bloqueio descrito pelo gerente, extraído pela IA (só no método ia)',
  quem_destrava     STRING    COMMENT 'Quem pode destravar o bloqueio, extraído pela IA (só no método ia, nulo quando o texto não diz)',
  dias_impacto      DOUBLE    COMMENT 'Dias de impacto no cronograma declarados no status (1 semana = 7). IA no método ia, regex nos demais',
  metodo            STRING    COMMENT 'Como a linha foi classificada: regra, ia ou palavra_chave',
  texto_status      STRING    COMMENT 'Texto livre original do status semanal',
  _classificado_em  TIMESTAMP COMMENT 'Quando a linha foi classificada (controle do MERGE incremental)'
)
COMMENT 'Status semanal estruturado: a causa do bloqueio, o que bloqueia, quem destrava e os dias de impacto de cada status de sexta. IA (ai_classify + ai_extract) nos últimos 90 dias, regra nos status sem bloqueio e palavra-chave no histórico. Tabela incremental: cada execução só acrescenta status novos.';


-- b · só os status novos (LEFT ANTI JOIN), cada um pelo seu método
MERGE INTO lakehouse_vertice.gold.status_estruturado AS destino
USING (
  WITH novos AS (
    SELECT s.*
    FROM lakehouse_vertice.silver.status_semanal s
    LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado e
      ON e.projeto_id = s.projeto_id AND e.data_status = s.data_status
  ),
  com_metodo AS (
    SELECT
      *,
      lower(texto_status)                                                AS texto,
      lower(regexp_extract(texto_status, '(?i)bloqueios?:(.*)', 1))      AS trecho_bloqueio,
      CASE
        WHEN status_vazio
          OR lower(texto_status) LIKE '%bloqueios: nenhum%'
          OR lower(texto_status) LIKE '%sem bloqueios%'
          OR lower(texto_status) LIKE '%nada relevante%'  THEN 'regra'
        WHEN data_status >= DATE'2026-07-18'              THEN 'ia'
        ELSE 'palavra_chave'
      END                                                                AS metodo
    FROM novos
  ),
  -- A IA roda SÓ nas linhas do método ia (~160 textos).
  ia AS (
    SELECT
      projeto_id,
      data_status,
      ai_classify(
        texto_status,
        '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
        map('version', '2.0')
      ) AS classificacao,
      ai_extract(
        texto_status,
        '{"bloqueio":{"type":"string","description":"o bloqueio que atrasa o projeto"},"quem_destrava":{"type":"string","description":"pessoa, área ou empresa que pode destravar o bloqueio"},"dias_impacto":{"type":"number","description":"dias de impacto no cronograma, 1 semana = 7"}}',
        map('version', '2.0')
      ) AS extracao
    FROM com_metodo
    WHERE metodo = 'ia'
  )
  SELECT
    m.projeto_id,
    m.data_status,
    m.farol,
    CASE
      WHEN m.status_vazio        THEN 'nao_reportado'
      WHEN m.metodo = 'regra'    THEN 'sem_bloqueio'
      WHEN m.metodo = 'ia'       THEN ia.classificacao:response[0]::STRING
      WHEN m.trecho_bloqueio RLIKE 'freeze|congelamento|janela de deploy'                   THEN 'change_freeze'
      WHEN m.trecho_bloqueio RLIKE 'sre|infraestrutura|ambiente de homologação'             THEN 'falta_sre'
      WHEN m.trecho_bloqueio RLIKE 'forge|consultoria|fornecedor'                           THEN 'dependencia_fornecedor'
      WHEN m.trecho_bloqueio RLIKE 'saída de|rotatividade|onboarding'                       THEN 'rotatividade'
      WHEN m.trecho_bloqueio RLIKE 'escopo|change request|regra de negócio'                 THEN 'mudanca_escopo'
      WHEN m.trecho_bloqueio RLIKE 'bugs|regressão|refazendo'                               THEN 'bug_retrabalho'
      WHEN m.trecho_bloqueio RLIKE 'aprovação do cliente|homologação do cliente'            THEN 'aprovacao_cliente'
      ELSE 'outro'
    END                                                              AS causa_bloqueio,
    CASE WHEN m.metodo = 'ia' THEN ia.extracao:response:bloqueio::STRING END       AS bloqueio,
    CASE WHEN m.metodo = 'ia' THEN ia.extracao:response:quem_destrava::STRING END  AS quem_destrava,
    CASE
      WHEN m.metodo = 'ia' THEN ia.extracao:response:dias_impacto::DOUBLE
      WHEN m.texto RLIKE 'impacto estimado de [0-9]+ dias'
        THEN CAST(regexp_extract(m.texto, 'impacto estimado de ([0-9]+) dias', 1) AS DOUBLE)
      WHEN m.texto RLIKE 'impacto estimado: [0-9]+ semana'
        THEN CAST(regexp_extract(m.texto, 'impacto estimado: ([0-9]+) semana', 1) AS DOUBLE) * 7
    END                                                              AS dias_impacto,
    m.metodo,
    m.texto_status,
    current_timestamp()                                              AS _classificado_em
  FROM com_metodo m
  LEFT JOIN ia
    ON ia.projeto_id = m.projeto_id AND ia.data_status = m.data_status
) AS novos
ON destino.projeto_id = novos.projeto_id AND destino.data_status = novos.data_status
WHEN NOT MATCHED THEN INSERT *;


-- c · leitura: quantos status por método e causa
SELECT metodo, causa_bloqueio, COUNT(*) AS status
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, status DESC;
