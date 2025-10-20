-- {"query": "6023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 822} 
WITH top_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
),
recent_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountLast72h
  FROM Comments c
  WHERE c.CreationDate >= NOW() - INTERVAL '72 hours'
  GROUP BY c.PostId
),
recent_votes AS (
  SELECT
    v.PostId,
    SUM(CASE
          WHEN v.VoteTypeId = 2 THEN 1
          WHEN v.VoteTypeId = 3 THEN -1
          ELSE 0
        END) AS NetScore72h
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '72 hours'
  GROUP BY v.PostId
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  CROSS APPLY (SELECT value AS TagName
               FROM string_to_table(p.Tags, '><') ) s
  GROUP BY t.TagName
),
edge_cases AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.Tags,
    tp.CreationDate,
    tp.OwnerUserId,
    tp.ViewCount,
    tp.Score,
    COALESCE(rc.CommentCountLast72h, 0) AS Comments72h,
    COALESCE(rv.NetScore72h, 0) AS NetScore72h
  FROM top_posts tp
  LEFT JOIN recent_comments rc ON rc.PostId = tp.PostId
  LEFT JOIN recent_votes rv ON rv.PostId = tp.PostId
),
user_rank AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rnk
  FROM Users u
  WHERE u.Reputation > 1000
),
final AS (
  SELECT
    e.PostId,
    e.Title,
    e.Tags,
    e.CreationDate,
    e.OwnerUserId,
    e.ViewCount,
    e.Score,
    e.Comments72h,
    e.NetScore72h,
    urr.DisplayName AS OwnerDisplayName,
    ur.Reputation AS OwnerReputation,
    ur.rnk AS OwnerRank
  FROM edge_cases e
  LEFT JOIN Users ur ON ur.Id = e.OwnerUserId
  LEFT JOIN user_rank urr ON urr.UserId = e.OwnerUserId
  LEFT JOIN user_rank ur ON ur.Id = e.OwnerUserId
)
SELECT
  f.PostId,
  f.Title,
  f.Tags,
  f.CreationDate,
  f.OwnerUserId,
  f.OwnerDisplayName,
  f.OwnerReputation,
  f.OwnerRank,
  f.ViewCount,
  f.Score,
  f.Comments72h,
  f.NetScore72h,
  f.CreationDate::DATE AS CreationDateOnly,
  CASE
    WHEN f.Comments72h > 0 AND f.NetScore72h >= 0 THEN 'Active'
    WHEN f.Comments72h = 0 AND f.NetScore72h = 0 THEN 'Neutral'
    ELSE 'Stale'
  END AS PostStatus
FROM final f
ORDER BY f.OwnerRank, f.CreationDate DESC
LIMIT 100;