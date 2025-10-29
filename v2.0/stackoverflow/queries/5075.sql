-- {"query": "5075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 651}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.AccountId,
    SUM(p.Score) OVER (PARTITION BY CAST(p.CreationDate AS DATE) ORDER BY p.CreationDate) AS DailyScoreCumulative,
    ROW_NUMBER() OVER (PARTITION BY CAST(p.CreationDate AS DATE) ORDER BY p.Score DESC, p.Id) AS RankByDay
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
recent_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountLast30
  FROM Comments c
  WHERE c.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days')
  GROUP BY c.PostId
),
tag_issues AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
outer_join_demo AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.Score,
    r.OwnerDisplayName,
    r.Reputation,
    r.Tags,
    r.DailyScoreCumulative,
    r.RankByDay,
    rc.CommentCountLast30,
    tj.TagName
  FROM ranked_posts r
  LEFT JOIN recent_comments rc ON rc.PostId = r.PostId
  LEFT JOIN (
    SELECT DISTINCT SUBSTRING(t.Tags FROM POSITION('<' IN t.Tags) FOR CHAR_LENGTH(t.Tags)) AS dummy, t.Id AS PostId
    FROM Posts t
  ) AS dj ON dj.PostId = r.PostId
  LEFT JOIN Tags tj ON 1=1
)
SELECT
  p1.PostId,
  p1.Title,
  p1.OwnerDisplayName,
  p1.Reputation,
  p1.CreationDate,
  p1.Score,
  p1.ViewCount,
  p1.CommentCount,
  p1.AnswerCount,
  p1.FavoriteCount,
  p1.Tags,
  p1.LastActivityDate,
  p1.DailyScoreCumulative,
  p1.RankByDay,
  rc.CommentCountLast30,
  tj.TagName
FROM ranked_posts p1
LEFT JOIN recent_comments rc ON rc.PostId = p1.PostId
LEFT JOIN (
  SELECT DISTINCT t.TagName
  FROM Tags t
) AS tj ON 1=1
WHERE p1.RankByDay <= 10
  AND p1.DailyScoreCumulative > 0
ORDER BY p1.CreationDate DESC, p1.Score DESC
LIMIT 100;