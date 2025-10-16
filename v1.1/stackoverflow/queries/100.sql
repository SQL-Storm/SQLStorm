WITH cte_rn AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.PostTypeId,
           ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn
    FROM Posts p
)
SELECT r1.Id, r1.Title, r1.Score, r1.ViewCount, r1.AnswerCount
FROM cte_rn r1
JOIN cte_rn r2 ON r1.rn = r2.rn
WHERE r1.PostTypeId = 1
  AND r2.PostTypeId = 2;