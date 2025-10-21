-- {"query": "44050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 359}

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
```

This query is designed to retrieve the top 10 most recent and highest-scoring posts (both questions and answers) for each user, based on the Posts table. It uses a common table expression (CTE) to rank the posts for each user by creation date, and then selects the top-ranked post for each user, ordered by score, view count, and creation date in descending order.

The CTE calculates the rank of each post for each user, and the outer query selects the top-ranked post for each user. This query can be useful for benchmarking the performance of the database, as it involves a complex join and aggregation, as well as a subquery, which can be resource-intensive operations.
