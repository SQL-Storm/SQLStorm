-- {"query": "5194.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 772} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LastActivityDate,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
popular_tags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.Count > 100
),
tag_partition AS (
  SELECT
    pt.PostId,
    unnest(string_to_array(substring(pt.Tags, 2, length(pt.Tags)-2), '><')) AS tag_name
  FROM Posts pt
  WHERE pt.PostTypeId = 1
),
tag_popularity AS (
  SELECT
    tp.tag_name,
    COUNT(*) AS tag_posts,
    SUM(p.score) AS total_score,
    AVG(p.viewcount) AS avg_views
  FROM tag_partition tp
  JOIN Posts p ON p.Id = tp.PostId
  GROUP BY tp.tag_name
),
correlated_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS comment_count,
    MAX(c.CreationDate) AS last_comment
  FROM Comments c
  GROUP BY c.PostId
),
correlated_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(v.BountyAmount) AS bounty
  FROM Votes v
  GROUP BY v.PostId
),
enriched AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.CommentCount,
    rq.LastActivityDate,
    rq.AnswerCount,
    rq.FavoriteCount,
    pc.comment_count,
    cv.upvotes,
    cv.downvotes,
    cv.bounty,
    pt.tag_name,
    tp.total_score,
    tp.avg_views
  FROM recent_questions rq
  LEFT JOIN correlated_comments pc ON pc.PostId = rq.PostId
  LEFT JOIN correlated_votes cv ON cv.PostId = rq.PostId
  LEFT JOIN tag_popularity tp ON tp.tag_name = ANY(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'))
  LEFT JOIN (SELECT tag_name, SUM(tag_posts) AS total_score FROM tag_popularity GROUP BY tag_name) pt ON pt.tag_name = ANY(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'))
)
SELECT
  e.PostId,
  e.Title,
  e.OwnerUserId,
  (SELECT DisplayName FROM Users u WHERE u.Id = e.OwnerUserId) AS OwnerDisplayName,
  e.CreationDate,
  e.Score,
  e.ViewCount,
  e.CommentCount,
  e.LastActivityDate,
  e.AnswerCount,
  e.FavoriteCount,
  e.comment_count,
  e.upvotes,
  e.downvotes,
  e.bounty,
  e.tag_name,
  e.total_score,
  e.avg_views
FROM enriched e
ORDER BY e.total_score DESC NULLS LAST, e.avg_views DESC NULLS LAST
LIMIT 100;