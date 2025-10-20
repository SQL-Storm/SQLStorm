WITH RECURSIVE cte AS (
  SELECT 
    p.Id,
    il.Level AS InitLoad,
    ROW_NUMBER() OVER (PARTITION BY p.AcceptedAnswerId ORDER BY p.Score DESC NULLS LAST) AS AnswerRank
  FROM Posts p
  LEFT JOIN Posts parent ON parent.Id = p.ParentId
  CROSS JOIN LATERAL (VALUES (NULL)) AS il(Level)
)
SELECT Id, InitLoad, AnswerRank
FROM cte
GROUP BY Id, InitLoad, AnswerRank;