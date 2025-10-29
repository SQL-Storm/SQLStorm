WITH
UsersLimited AS (
  SELECT Id, Reputation, CreationDate, LastAccessDate
  FROM Users
  ORDER BY RANDOM()
  LIMIT 1000
),
TopTags AS (
  SELECT t.TagName, t.Count, p.Id AS PostId
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE t.Count > 10
),
RecentActivities AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    u.Reputation AS UserReputation,
    p.OwnerUserId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.Tags
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  LEFT JOIN Users u ON u.Id = v.UserId
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TagAnalytics AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxViews,
    MIN(p.ViewCount) AS MinViews
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY t.TagName
),
QualifiedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
    AND p.ViewCount > 0
    AND (p.Score IS NULL OR p.Score > 0)
),
OuterJoinsAndWindow AS (
  SELECT
    qp.PostId,
    pp.Title,
    pp.OwnerUserId,
    uu.DisplayName AS OwnerName,
    pp.CreationDate,
    pp.LastActivityDate,
    pp.Score,
    pp.ViewCount,
    pp.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY qp.PostId
      ORDER BY pp.LastActivityDate DESC, pp.Score DESC
    ) AS rn
  FROM QualifiedPosts qp
  LEFT JOIN Users uu ON uu.Id = qp.OwnerUserId
  LEFT JOIN Posts pp ON pp.Id = qp.PostId
  WHERE qp.PostId = qp.PostId
),
Final AS (
  SELECT
    oj.PostId,
    oj.Title,
    oj.OwnerUserId,
    oj.OwnerName,
    oj.CreationDate,
    oj.LastActivityDate,
    oj.Score,
    oj.ViewCount,
    oj.Tags,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY oj.PostId) AS UpvotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY oj.PostId) AS DownvotesForPost,
    COUNT(*) OVER (PARTITION BY oj.PostId) AS TotalRelatedVotes,
    oj.rn
  FROM OuterJoinsAndWindow oj
  LEFT JOIN Votes v ON v.PostId = oj.PostId
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerName,
  f.CreationDate,
  f.LastActivityDate,
  f.Score,
  f.ViewCount,
  f.Tags,
  f.UpvotesForPost,
  f.DownvotesForPost,
  f.TotalRelatedVotes
FROM Final f
WHERE f.rn = 1
ORDER BY f.LastActivityDate DESC, f.Score DESC
LIMIT 100;