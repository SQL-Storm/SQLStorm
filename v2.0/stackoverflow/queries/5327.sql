-- {"query": "5327.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1015}
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn_loc
  FROM Users u
),
recent_badges AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date AS EarnedDate,
    b.Class,
    b.TagBased,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn_badge
  FROM Badges b
  WHERE b.Date >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
),
question_stats AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    CASE
      WHEN p.ViewCount = 0 THEN 0
      ELSE CAST(p.Score AS DOUBLE PRECISION) / p.ViewCount
    END AS ScorePerView
  FROM Posts p
  WHERE p.PostTypeId = 1
),
recent_comments AS (
  SELECT
    c.PostId,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(*) AS NumComments
  FROM Comments c
  WHERE c.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH)
  GROUP BY c.PostId
),
linked_to_duplicates AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    p2.PostTypeId AS RelatedPostType
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE lt.Name = 'Duplicate'
),
complex_filter AS (
  SELECT
    q.PostId,
    q.OwnerUserId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    q.PostTypeId,
    q.AcceptedAnswerId,
    q.ScorePerView,
    CASE
      WHEN rc.AvgCommentScore IS NULL THEN 0
      ELSE rc.AvgCommentScore
    END AS AvgCommentScore,
    CASE
      WHEN rc.NumComments IS NULL THEN 0
      ELSE rc.NumComments
    END AS NumComments,
    CASE
      WHEN bd.BadgeName IS NULL THEN 'None'
      ELSE bd.BadgeName
    END AS LatestBadge
  FROM question_stats q
  LEFT JOIN recent_comments rc ON q.PostId = rc.PostId
  LEFT JOIN linked_to_duplicates ltd ON q.PostId = ltd.PostId
  LEFT JOIN recent_badges bd ON q.OwnerUserId = bd.UserId AND bd.rn_badge = 1
  LEFT JOIN top_users tu ON q.OwnerUserId = tu.UserId
  LEFT JOIN (
    SELECT UserId, MAX(Date) AS Date FROM Badges GROUP BY UserId
  ) latest ON latest.UserId = q.OwnerUserId
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS PostsCount FROM Posts WHERE OwnerUserId IS NOT NULL GROUP BY OwnerUserId
  ) pc ON pc.UserId = q.OwnerUserId
)
SELECT
  cf.PostId,
  cf.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  cf.Title,
  cf.Tags,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.Score,
  cf.ViewCount,
  cf.AnswerCount,
  cf.CommentCount,
  cf.FavoriteCount,
  cf.AcceptedAnswerId,
  cf.ScorePerView,
  cf.AvgCommentScore,
  cf.NumComments,
  cf.LatestBadge,
  tu.Reputation,
  tu.CreationDate AS OwnerCreationDate,
  tu.LastAccessDate AS OwnerLastAccess
FROM complex_filter cf
LEFT JOIN Users u ON cf.OwnerUserId = u.Id
LEFT JOIN top_users tu ON cf.OwnerUserId = tu.UserId
LEFT JOIN recent_badges rb ON cf.OwnerUserId = rb.UserId AND rb.rn_badge = 1
ORDER BY cf.ScorePerView DESC NULLS LAST, cf.ViewCount DESC, cf.Score DESC
LIMIT 100;