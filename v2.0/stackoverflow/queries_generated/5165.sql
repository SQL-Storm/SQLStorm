-- {"query": "5165.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1002} 
WITH recent_active AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.Location,
    -- window function to rank posts by activity
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY GREATEST(p.LastActivityDate, p.CreationDate) DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate IS NOT NULL
),
popular AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    ra.OwnerName,
    ra.Reputation,
    ra.Location,
    ra.Tags,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.rn
  FROM recent_active ra
  WHERE ra.rn <= 50
),
tag_buckets AS (
  SELECT
    p.Id AS PostId,
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Posts p
  CROSS APPLY (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS t
  JOIN Tags tg ON tg.TagName = t.TagName
  WHERE p.PostTypeId = 1
),
cross_analytics AS (
  SELECT
    pb.PostId,
    pb.Title,
    pb.LastActivityDate,
    pb.ViewCount,
    pb.Score,
    pb.FavoriteCount,
    pb.AnswerCount,
    vb.VoteCount AS Upvotes,
    vb.DownvoteCount AS Downvotes,
    -- derived metrics
    CASE WHEN pb.ViewCount > 1000 THEN TRUE ELSE FALSE END AS is_high_view,
    CASE WHEN pb.Score > 5 THEN 'hot' ELSE 'normal' END AS status
  FROM popular pb
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
      SUM(CASE WHEN VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes
    FROM Votes
    GROUP BY PostId
  ) v ON pb.PostId = v.PostId
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId IN (2,3,6,7,8,9)
    GROUP BY PostId
  ) vb ON pb.PostId = vb.PostId
)
SELECT
  ca.PostId,
  ca.Title,
  ca.LastActivityDate,
  ca.ViewCount,
  ca.Score,
  ca.FavoriteCount,
  ca.AnswerCount,
  COALESCE(ca.Upvotes, 0) AS Upvotes,
  COALESCE(ca.Downvotes, 0) AS Downvotes,
  ca.is_high_view,
  ca.status,
  u.Reputation AS OwnerReputation,
  u.DisplayName AS OwnerDisplayName,
  u.Location AS OwnerLocation,
  array_agg(DISTINCT tb.TagName) FILTER (WHERE tb.TagName IS NOT NULL) AS TagsUsed,
  pgm.Classification AS BadgeTier
FROM cross_analytics ca
LEFT JOIN Users u ON ca.OwnerUserId = u.Id
LEFT JOIN (
  SELECT
    b.UserId,
    b.Name,
    b.Class
  FROM Badges b
  WHERE b.TagBased = FALSE
) pgm ON ca.OwnerUserId = pgm.UserId
LEFT JOIN (
  SELECT
    p1.PostId,
    t.TagName
  FROM post_tags p1
  JOIN Tags t ON t.TagName = p1.TagName
) tb ON ca.PostId = tb.PostId
GROUP BY
  ca.PostId,
  ca.Title,
  ca.LastActivityDate,
  ca.ViewCount,
  ca.Score,
  ca.FavoriteCount,
  ca.AnswerCount,
  ca.Upvotes,
  ca.Downvotes,
  ca.is_high_view,
  ca.status,
  u.Reputation,
  u.DisplayName,
  u.Location,
  pgm.Classification
ORDER BY ca.LastActivityDate DESC
LIMIT 100;