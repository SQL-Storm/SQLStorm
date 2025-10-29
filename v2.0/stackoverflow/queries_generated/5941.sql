-- {"query": "5941.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 955} 
WITH
recent_q AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation AS OwnerReputation
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
tag_based AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.OwnerReputation,
    array_length(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'), 1) AS TagCount,
    rq.CommentCount,
    rq.FavoriteCount
  FROM recent_q rq
),
top_tags AS (
  SELECT
    unnest(string_to_array(substring(t.Tags, 2, length(t.Tags)-2), '><')) AS Tag,
    COUNT(*) AS TagFrequency
  FROM Posts p
  CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS t(Tag)
  WHERE p.PostTypeId = 1
  GROUP BY Tag
  ORDER BY TagFrequency DESC
  LIMIT 5
),
cross_joined AS (
  SELECT
    t.Tag,
    b.PostId,
    b.Title,
    b.CreationDate,
    b.Score,
    b.ViewCount,
    b.OwnerUserId,
    b.LastActivityDate,
    b.OwnerReputation,
    b.TagCount,
    b.CommentCount,
    b.FavoriteCount
  FROM top_tags t
  LEFT JOIN tag_based b
    ON position(t.Tag in b.Tags) > 0
),
activity_metrics AS (
  SELECT
    PostId,
    Title,
    CreationDate,
    ViewCount,
    Score,
    OwnerReputation,
    LastActivityDate,
    OwnerUserId,
    TagCount,
    CommentCount,
    FavoriteCount,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY PostId) AS UpVotes,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY PostId) AS DownVotes,
    SUM(CASE WHEN VoteTypeId = 16 THEN 1 ELSE 0 END) OVER (PARTITION BY PostId) AS ModeratorReviews
  FROM Posts p
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
)
SELECT
  cm.PostId,
  cm.Title,
  cm.CreationDate,
  cm.ViewCount,
  cm.Score,
  cm.OwnerReputation AS OwnerReputationAtCreation,
  cm.LastActivityDate,
  cm.OwnerUserId,
  cm.TagCount,
  cm.CommentCount,
  cm.FavoriteCount,
  cm.UpVotes,
  cm.DownVotes,
  cm.ModeratorReviews,
  CASE
    WHEN cm.LastActivityDate > cm.CreationDate + INTERVAL '30 days'
      THEN true
      ELSE false
  END AS ActiveLongerThan30Days,
  array_agg(DISTINCT t.Tag) FILTER (WHERE t.Tag IS NOT NULL) AS TopAssociatedTags
FROM activity_metrics cm
LEFT JOIN LATERAL (
  SELECT
    unnest(string_to_array(substring(cm.Tags, 2, length(cm.Tags)-2), '><')) AS Tag
) t ON true
LEFT JOIN cross_joined cj ON cm.PostId = cj.PostId
GROUP BY
  cm.PostId,
  cm.Title,
  cm.CreationDate,
  cm.ViewCount,
  cm.Score,
  cm.OwnerReputation,
  cm.LastActivityDate,
  cm.OwnerUserId,
  cm.TagCount,
  cm.CommentCount,
  cm.FavoriteCount,
  cm.UpVotes,
  cm.DownVotes,
  cm.ModeratorReviews
ORDER BY cm.Score DESC NULLS LAST, cm.ViewCount DESC NULLS LAST
LIMIT 100;