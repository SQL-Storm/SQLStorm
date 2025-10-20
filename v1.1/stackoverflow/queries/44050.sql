-- {"query": "44050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 114700, "output_tokens": 40931} 
WITH CTE AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CreationDate,
    RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
)
SELECT
  c.PostId,
  c.PostTypeId,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.CreationDate
FROM CTE c
WHERE c.RowNum = 1
ORDER BY c.Score DESC, c.ViewCount DESC, c.CreationDate DESC
LIMIT 10;