WITH RECURSIVE question_cycles_q AS (
    SELECT
        CAST(NULL AS INTEGER) AS id,
        CAST(NULL AS VARCHAR) AS title,
        CAST(NULL AS INTEGER) AS parent_id
    WHERE FALSE
)
SELECT
    qc.id,
    qc.title,
    qc.parent_id
FROM question_cycles_q qc
GROUP BY qc.id, qc.title, qc.parent_id;