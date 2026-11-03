-- silver.entregas_fornecedor: prometido x entregue pelas consultorias.

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias contratadas: data do pedido, prometida e de entrega, prazos em dias e atraso. em_aberto = ainda não entregue; em_atraso = em aberto com a data prometida antes de hoje (16/10/2026). fornecedor vem normalizado; fornecedor_como_veio guarda a grafia original.'
AS
WITH tipado AS (
  SELECT
    entrega_id,
    projeto_id,
    -- A CodeForge vem de 4 jeitos ('Codeforge Consultoria', 'Code Forge Consultoria'...).
    CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
         THEN 'CodeForge Consultoria Ltda'
         ELSE fornecedor END                                   AS fornecedor,
    fornecedor                                                 AS fornecedor_como_veio,
    item,
    CAST(valor AS DECIMAL(18,2))                               AS valor,
    to_date(data_pedido, 'yyyy-MM-dd')                         AS data_pedido,
    to_date(data_prometida, 'yyyy-MM-dd')                      AS data_prometida,
    to_date(nullif(data_entrega, ''), 'yyyy-MM-dd')            AS data_entrega,   -- vazia = em aberto (não é sujeira)
    CAST(prazo_contratado_dias AS INT)                         AS prazo_contratado_dias,
    status
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  *,
  datediff(data_prometida, data_pedido)                                   AS prazo_prometido_dias,
  datediff(data_entrega, data_pedido)                                     AS prazo_real_dias,
  datediff(data_entrega, data_prometida)                                  AS dias_de_atraso_na_entrega,
  data_entrega IS NULL                                                    AS em_aberto,
  data_entrega IS NULL AND data_prometida < DATE'2026-10-16'              AS em_atraso
FROM tipado;
