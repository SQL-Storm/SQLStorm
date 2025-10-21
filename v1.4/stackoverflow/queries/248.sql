-- {"query": "248.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7036} 
WITH
recent_questions AS (
  SELECT
    p.Id AS post_id,
    p.Title AS post_title,
    p.OwnerUserId,
    p.CreationDate AS post_date,
    p.Score AS post_score,
    p.ViewCount AS post_views,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id) AS VoteCount,
    STRING_AGG(tn.TagName, ',') AS TagList
  FROM Posts p
  LEFT JOIN LATERAL (
     SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
  ) tn ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, COALESCE(p.AnswerCount, 0)
  ORDER BY p.Score DESC, p.CreationDate DESC
  LIMIT 300
),
user_summary AS (
  SELECT
     u.Id,
     u.DisplayName,
     u.Reputation,
     u.LastAccessDate,
     COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id), 0) AS BadgeCount,
     ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS RepRank
  FROM Users u
),
combined AS (
  SELECT
     rq.post_id,
     rq.post_title,
     rq.post_date,
     rq.post_score,
     rq.post_views,
     rq.AnswerCount,
     rq.CommentCount,
     rq.TagList,
     us.Id AS user_id,
     us.DisplayName AS user_name,
     us.Reputation,
     us.RepRank,
     us.BadgeCount
  FROM recent_questions rq
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
  LEFT JOIN user_summary us ON us.Id = u.Id
),
tag_activity AS (
  SELECT TagName, COUNT(*) AS usage
  FROM (
     SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
     FROM Posts p
     WHERE p.PostTypeId = 1
  ) s
  GROUP BY TagName
  ORDER BY usage DESC
  LIMIT 20
)
SELECT
  'post' AS kind,
  post_id,
  post_title,
  post_date,
  post_score,
  post_views,
  AnswerCount,
  CommentCount,
  TagList,
  user_id,
  user_name,
  Reputation,
  RepRank,
  BadgeCount
FROM combined
UNION ALL
SELECT
  'tag' AS kind,
  NULL AS post_id,
  NULL AS post_title,
  NULL AS post_date,
  NULL AS post_score,
  NULL AS post_views,
  NULL AS AnswerCount,
  NULL AS CommentCount,
  TagName AS TagList,
  NULL AS user_id,
  NULL AS user_name,
  NULL AS Reputation,
  NULL AS RepRank,
  NULL AS BadgeCount
FROM tag_activity
ORDER BY kind, post_score DESC NULLS LAST
LIMIT 100;