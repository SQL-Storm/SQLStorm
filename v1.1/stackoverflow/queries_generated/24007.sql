-- {"query": "24007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4663} 
WITH
    q AS (
        SELECT
            p.Id AS QId,
            p.Title,
            p.Score AS QScore,
            p.OwnerUserId,
            p.CreationDate,
            regexp_split_to_array(p.Tags, '<>') AS tag_arr
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    tag_rows AS (
        SELECT
            QId,
            unnest(tag_arr) AS tag
        FROM q
    ),
    tag_counts AS (
        SELECT
            tag,
            COUNT(*) AS tag_use
        FROM tag_rows
        GROUP BY tag
    ),
    top_answer AS (
        SELECT
            p.ParentId AS QId,
            p.Id AS AId,
            p.Score AS AScore,
            ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 2
    ),
    top_ans_only AS (
        SELECT
            QId,
            AId,
            AScore
        FROM top_answer
        WHERE rn = 1
    ),
    ans_count AS (
        SELECT
            ParentId AS QId,
            COUNT(*) AS AnsCnt
        FROM Posts
        WHERE PostTypeId = 2
          AND ParentId IS NOT NULL
        GROUP BY ParentId
    )
SELECT
    q.QId,
    q.Title,
    q.QScore,
    COALESCE(u.DisplayName, 'Community') AS Owner,
    q.CreationDate,
    tr.tag,
    COALESCE(tc.tag_use,0) AS TagUsage,
    ac.AnsCnt,
    CASE WHEN EXISTS (
            SELECT 1 FROM Posts p2
            WHERE p2.ParentId = q.QId
              AND p2.Score > 10
          ) THEN 1 ELSE 0 END AS HighScoreAnswer,
    ta.AId AS TopAnswerId,
    ta.AScore AS TopAnswerScore
FROM q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN tag_rows tr ON q.QId = tr.QId
LEFT JOIN tag_counts tc ON tr.tag = tc.tag
LEFT JOIN ans_count ac ON q.QId = ac.QId
LEFT JOIN top_ans_only ta ON q.QId = ta.QId
WHERE q.QScore >= 0
UNION ALL
SELECT
    p.Id AS QId,
    p.Title,
    p.Score AS QScore,
    COALESCE(u.DisplayName, 'Community') AS Owner,
    p.CreationDate,
    NULL AS tag,
    0 AS TagUsage,
    0 AS AnsCnt,
    0 AS HighScoreAnswer,
    NULL AS TopAnswerId,
    NULL AS TopAnswerScore
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
  AND p.Score < 0
ORDER BY QId DESC;