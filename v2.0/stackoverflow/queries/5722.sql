-- {"query": "5722.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 647}
WITH RECURSIVE RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate IS NOT NULL
    AND p.LastActivityDate > CAST('2024-10-01' AS date) - INTERVAL '90 days'
),
TopAuthors AS (
  SELECT
    ra.OwnerUserId,
    ra.DisplayName,
    ra.Reputation,
    SUM(COALESCE(ra.Score,0)) AS total_post_score,
    SUM(COALESCE(ra.ViewCount,0)) AS total_view_count,
    MAX(ra.LastActivityDate) AS last_active
  FROM RecentActive ra
  GROUP BY ra.OwnerUserId, ra.DisplayName, ra.Reputation
),
TagSplit AS (
  SELECT
    p.Id AS PostId,
    TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM SUBSTRING(p.Tags FROM 1 FOR COALESCE(NULLIF(POSITION('><' IN p.Tags)-1, -1), CHAR_LENGTH(p.Tags))))) AS TagName,
    CASE
      WHEN POSITION('><' IN p.Tags) = 0 THEN '' 
      ELSE SUBSTRING(p.Tags FROM POSITION('><' IN p.Tags) + 2)
    END AS rest
  FROM Posts p
  WHERE p.Tags IS NOT NULL AND p.Tags <> ''
  UNION ALL
  SELECT
    ts.PostId,
    TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM SUBSTRING(ts.rest FROM 1 FOR COALESCE(NULLIF(POSITION('><' IN ts.rest)-1, -1), CHAR_LENGTH(ts.rest))))) AS TagName,
    CASE
      WHEN POSITION('><' IN ts.rest) = 0 THEN ''
      ELSE SUBSTRING(ts.rest FROM POSITION('><' IN ts.rest) + 2)
    END AS rest
  FROM TagSplit ts
  WHERE ts.rest IS NOT NULL AND ts.rest <> ''
),
TagAnalytics AS (
  SELECT
    ts.TagName,
    COUNT(*) AS tag_post_count,
    SUM(COALESCE(p.ViewCount,0)) AS tag_total_views,
    AVG(COALESCE(p.Score,0)) AS tag_avg_score
  FROM TagSplit ts
  JOIN Posts p ON p.Id = ts.PostId
  WHERE ts.TagName IS NOT NULL AND ts.TagName <> ''
  GROUP BY ts.TagName
),
WorstCN AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(p.Score, 0) AS computed_score
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate IS NOT NULL
  ORDER BY computed_score ASC
  LIMIT 100
)
SELECT
  ta.TagName,
  ta.tag_post_count,
  ta.tag_total_views,
  ta.tag_avg_score,
  ba.total_post_score,
  ba.total_view_count,
  ba.last_active,
  wa.PostId AS worst_post_id,
  wa.Title AS worst_post_title,
  wa.Score AS worst_post_score,
  wa.ViewCount AS worst_post_views,
  wa.CreationDate AS worst_post_created,
  wa.LastActivityDate AS worst_post_active,
  wa.DisplayName AS worst_post_owner,
  wa.Reputation AS worst_post_owner_rep
FROM TagAnalytics ta
LEFT JOIN TopAuthors ba
  ON 1=1
LEFT JOIN WorstCN wa
  ON 1=1
ORDER BY ta.tag_post_count DESC
LIMIT 200;