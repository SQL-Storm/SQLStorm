-- {"query": "5622.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 695} 
WITH recent_questions AS (
  SELECT 
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
tag_popularity AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    COUNT(*) AS tag_count
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY 1
),
top_tags AS (
  SELECT tag
  FROM tag_popularity
  ORDER BY tag_count DESC
  LIMIT 5
),
tag_join AS (
  SELECT rp.PostId, rp.Title, rp.OwnerUserId, rp.LastActivityDate,
         CASE 
           WHEN t.TagName IS NOT NULL THEN t.TagName
           ELSE 'untagged'
         END AS primary_tag
  FROM recent_questions rp
  LEFT JOIN (
    SELECT unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS tag
    FROM Posts rq
    WHERE rq.Id = rp.PostId
  ) t ON TRUE
  LEFT JOIN Tags ts ON ts.TagName = t.tag
  WHERE rp.PostId IN (SELECT PostId FROM recent_questions)
)
SELECT
  rp.PostId,
  rp.Title,
  rp.OwnerDisplayName,
  rp.Reputation,
  rp.CreationDate,
  rp.ViewCount,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.LastActivityDate,
  rp.primary_tag,
  -- window function: rolling rank by view count within same tag group
  RANK() OVER (PARTITION BY rp.primary_tag ORDER BY rp.ViewCount DESC, rp.CreationDate DESC) AS view_rank_within_tag,
  -- correlated subquery: latest edit date from PostHistory for this post
  (SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     WHERE ph.PostId = rp.PostId
       AND ph.PostHistoryTypeId IN (16, 36, 50)) AS last_community_update
FROM (
  SELECT rp2.PostId, rp2.Title, rp2.OwnerUserId, rp2.OwnerDisplayName, rp2.Reputation,
         rp2.CreationDate, rp2.ViewCount, rp2.Score, rp2.AnswerCount, rp2.CommentCount,
         rp2.FavoriteCount, rp2.LastActivityDate, rp2.primary_tag
  FROM Posts rp2
  JOIN Users u ON rp2.OwnerUserId = u.Id
  WHERE rp2.PostTypeId = 1
) rp
ORDER BY rp.view_rank_within_tag ASC, rp.LastActivityDate DESC
LIMIT 100;