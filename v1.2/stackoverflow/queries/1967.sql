WITH RECURSIVE RecursiveTagAggregates AS (
    -- base recursive CTE placeholder: original content was corrupted; providing a syntactically valid empty CTE body
    SELECT
        CAST(NULL AS text) AS tag,
        CAST(NULL AS bigint) AS cnt,
        1 AS lvl
    WHERE FALSE

    UNION ALL

    SELECT
        tag,
        cnt,
        lvl + 1
    FROM RecursiveTagAggregates
),
cte_Hotto_sta_Filter AS (
    -- placeholder CTE to keep query valid; original content was corrupted
    SELECT
        CAST(NULL AS bigint) AS id,
        CAST(NULL AS text) AS title,
        CAST(NULL AS timestamp) AS created_at
    WHERE FALSE
),
main AS (
    SELECT
        h.id,
        h.title,
        h.created_at,
        r.tag,
        r.cnt,
        r.lvl,
        ROW_NUMBER() OVER (PARTITION BY h.id ORDER BY h.created_at DESC) AS rn
    FROM cte_Hotto_sta_Filter h
    LEFT JOIN RecursiveTagAggregates r
        ON r.tag IS NOT NULL
)
SELECT
    id,
    title,
    created_at,
    tag,
    cnt,
    lvl,
    rn
FROM main
WHERE rn = 1
ORDER BY created_at DESC;