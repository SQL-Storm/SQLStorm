WITH RECURSIVE RecursivePostsCTE AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.AcceptedAnswerId, p.Title, p.Score, p.CreationDate,
    1 AS depth,
    ARRAY[p.Id] AS path
  FROM posts p
  WHERE p.PostTypeId = 1

  UNION ALL

  SELECT a.Id, a.PostTypeId, a.OwnerUserId, a.AcceptedAnswerId, a.Title, a.Score, a.CreationDate,
    c.depth + 1,
    c.path || a.Id
  FROM posts a
  INNER JOIN RecursivePostsCTE c ON a.ParentId = c.Id
  WHERE a.PostTypeId = 2
    AND NOT (a.Id = ANY(c.path))
),
AskedQuestionsWithMetrics AS (
  SELECT
    q.Id,
    q.Title,
    COALESCE(0, 0) AS answered_gold_badges,
    COUNT(DISTINCT pht.Id) FILTER (
      WHERE pht.PostHistoryTypeId IN (4,5,6)
        AND pht.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
    ) AS recent_edits
  FROM posts q
  LEFT JOIN posthistory pht ON pht.PostId = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Title
)
SELECT *
FROM AskedQuestionsWithMetrics;