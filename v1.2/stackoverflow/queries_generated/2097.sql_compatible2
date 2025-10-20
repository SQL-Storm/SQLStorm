WITH RecursiveLeadingEntities AS (
    -- The original CTE body appears to be corrupted/non-SQL text. Replace with an empty selectable CTE to keep SQL valid.
    SELECT CAST(NULL AS text) AS entity_id
), base_data AS (
    -- placeholder base query to allow following aggregation; replace with real table/query as needed
    SELECT
        entity_id,
        CAST(NULL AS text) AS group_col,
        CAST(NULL AS numeric) AS value_col
    FROM (
      SELECT entity_id FROM (VALUES (CAST(NULL AS text))) v(entity_id)
    ) t
)
SELECT
    entity_id,
    group_col,
    SUM(value_col) AS total_value
FROM base_data
GROUP BY
    entity_id,
    group_col;