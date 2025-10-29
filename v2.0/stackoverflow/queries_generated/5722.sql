-- {"query": "5722.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 647} 
WITH RecentActive AS (
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
    AND p.LastActivityDate > CURRENT_DATE - INTERVAL '90 days'
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
TagAnalytics AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_post_count,
    SUM(COALESCE(p.ViewCount,0)) AS tag_total_views,
    AVG(COALESCE(p.Score,0)) AS tag_avg_score
  FROM Posts p
  CROSS APPLY (
    SELECT value AS TagName
    FROM STRING_SPLIT(p.Tags, '><')
    WHERE value <> ''
  ) AS t
  GROUP BY t.TagName
),
WorstCN as (
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
    CASE
      WHEN p.Score IS NULL THEN 0
      ELSE p.Score
    END AS computed_score
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