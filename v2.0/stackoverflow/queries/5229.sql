-- {"query": "5229.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 880} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate ASC
    ) AS rn_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
),
Filtered AS (
  SELECT
    r.*,
    -- compute a complex up/down weighted activity score
    (
      (r.Score * 4) +
      (CASE WHEN r.ViewCount > 1000 THEN 100 ELSE 0 END) +
      (COALESCE(r.AnswerCount,0) * 10) +
      (CASE WHEN r.FavoriteCount > 0 THEN r.FavoriteCount * 5 ELSE 0 END) +
      (EXTRACT(epoch FROM (cast('2024-10-01 12:34:56' as timestamp) - r.CreationDate)) / 3600) * -1
    ) AS activity_score,
    -- example of correlated subquery: see if there exists a close event
    EXISTS (
      SELECT 1
      FROM PostHistory ph
      WHERE ph.PostId = r.Id
        AND ph.PostHistoryTypeId = 10 -- Post Closed
        AND ph.CreationDate > r.CreationDate
    ) AS recently_closed
  FROM RankedPosts r
  WHERE r.rn_type = 1
),
CTE_Window AS (
  SELECT
    f.*,
    -- window function: running sum of score by PostType across time
    SUM(f.Score) OVER (
      PARTITION BY f.PostTypeId
      ORDER BY f.CreationDate
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_score_by_type,
    -- rank within window by activity_score desc
    RANK() OVER (
      PARTITION BY f.PostTypeId
      ORDER BY f.activity_score DESC
    ) AS type_rank
  FROM Filtered f
)
SELECT
  cte.Id,
  cte.PostTypeId,
  pt.Name AS PostTypeName,
  cte.OwnerUserId,
  cte.Title,
  cte.Tags,
  cte.CreationDate,
  cte.LastActivityDate,
  cte.ViewCount,
  cte.Score,
  cte.CommentCount,
  cte.AnswerCount,
  cte.FavoriteCount,
  cte.Body,
  cte.Reputation,
  cte.DisplayName,
  cte.AccountId,
  cte.LastEditorUserId,
  cte.LastEditDate,
  cte.OwnerDisplayName,
  cte.ContentLicense,
  cte.activity_score,
  cte.recently_closed,
  cte.running_score_by_type,
  cte.type_rank,
  -- complex string expression with NULL handling
  COALESCE(NULLIF(regexp_replace(cte.Tags, '^[<>]|[<>]$', '', 'g'), ''), 'untagged') AS CleanTags
FROM CTE_Window cte
JOIN PostTypes pt ON cte.PostTypeId = pt.Id
LEFT JOIN Tags t ON t.Id = cte.Id -- placeholder join to include tags table in sample
LEFT JOIN Badges b ON b.UserId = cte.OwnerUserId
ORDER BY
  cte.activity_score DESC,
  cte.running_score_by_type DESC,
  cte.type_rank ASC
LIMIT 500;