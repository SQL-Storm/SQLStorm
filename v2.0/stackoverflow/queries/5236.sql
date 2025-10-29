-- {"query": "5236.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 821}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.AcceptedAnswerId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
    p.Id
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagStats AS (
  SELECT
    tg.Tag,
    COUNT(*) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM TopTags tg
  JOIN Posts p ON p.Id = tg.Id
  GROUP BY tg.Tag
),
CrossJoined AS (
  SELECT
    r.Id AS PostId,
    r.Title,
    r.OwnerUserId,
    r.ViewCount,
    r.Score,
    r.LastActivityDate,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    r.Tags,
    t.Tag
  FROM RecentActivePosts r
  LEFT JOIN TopTags t ON t.Id = r.Id
),
Windowed AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    p.AcceptedAnswerId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
  FROM Posts p
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days'
    AND p.OwnerUserId IS NOT NULL
)
SELECT
  w.PostId,
  w.PostTypeId,
  w.Title,
  w.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  w.CreationDate,
  w.LastActivityDate,
  w.ViewCount,
  w.Score,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.Tags,
  COALESCE(a.Title, NULL) AS AcceptedAnswerTitle,
  v1.VoteTypeId AS LastUpvoteType,
  COALESCE(v2.BountyAmount, 0) AS LastBountyAmount,
  COALESCE(bt.PostCount, 0) AS RelatedPostCount,
  COALESCE(ts.TotalViews, 0) AS TagTotalViews,
  CASE
    WHEN w.Score > 20 THEN 'Hot'
    WHEN w.Score > 0 THEN 'Rising'
    ELSE 'New'
  END AS BuzzLevel
FROM Windowed w
JOIN Users u ON w.OwnerUserId = u.Id
LEFT JOIN Posts a ON w.AcceptedAnswerId = a.Id
LEFT JOIN LATERAL (
  SELECT v.VoteTypeId
  FROM Votes v
  WHERE v.PostId = w.PostId AND v.VoteTypeId = 2
  ORDER BY v.CreationDate DESC
  LIMIT 1
) v1 ON TRUE
LEFT JOIN LATERAL (
  SELECT v.BountyAmount
  FROM Votes v
  WHERE v.PostId = w.PostId AND v.VoteTypeId = 8
  ORDER BY v.CreationDate DESC
  LIMIT 1
) v2 ON TRUE
LEFT JOIN (
  SELECT PostId, Count(*) AS PostCount
  FROM PostLinks
  GROUP BY PostId
) bt ON bt.PostId = w.PostId
LEFT JOIN TagStats ts ON ts.Tag = regexp_replace(w.Tags, '^\(|\)$', '', 'g')
WHERE w.rn = 1
GROUP BY
  w.PostId,
  w.PostTypeId,
  w.Title,
  w.OwnerUserId,
  u.DisplayName,
  u.Reputation,
  w.CreationDate,
  w.LastActivityDate,
  w.ViewCount,
  w.Score,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.Tags,
  a.Title,
  v1.VoteTypeId,
  v2.BountyAmount,
  bt.PostCount,
  ts.TotalViews
ORDER BY w.LastActivityDate DESC, w.Score DESC
LIMIT 100;