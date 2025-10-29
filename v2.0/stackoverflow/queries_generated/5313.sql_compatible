WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '180 days'
),
TagHub AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    SUM(t.Score) AS ScoreSum,
    AVG(t.Score) FILTER (WHERE t.OwnerUserId IS NOT NULL) AS AvgOwnerScore,
    MAX(t.LastActivityDate) AS LastActive
  FROM (
    SELECT
      unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id,
      p.Score,
      p.OwnerUserId,
      p.LastActivityDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
  ) AS t
  GROUP BY t.TagName
),
CorrelatedCommentStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    COUNT(c.Id) AS NumComments,
    AVG(COALESCE(c.Score, 0)) AS AvgCommentScore
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.OwnerUserId
),
TopVotedAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    SUM(v.BountyAmount) AS TotalBounty,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
    MAX(v.CreationDate) AS LastVote
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
CrossJoinSample AS (
  SELECT
    r.PostId,
    r.Title AS PostTitle,
    r.Score AS PostScore,
    th.TagName,
    th.TagPostCount,
    th.ScoreSum,
    th.AvgOwnerScore,
    ch.NumComments,
    ch.AvgCommentScore,
    u.Id AS OwnerId,
    u.DisplayName AS OwnerDisplayName,
    a.TotalBounty,
    r.LastActivityDate,
    r.CommentCount,
    r.FavoriteCount
  FROM RecentActivePosts r
  LEFT JOIN LATERAL (
    SELECT * FROM TagHub th WHERE th.TagName IS NOT NULL ORDER BY th.TagPostCount DESC LIMIT 3
  ) AS th ON TRUE
  LEFT JOIN CorrelatedCommentStats ch ON ch.PostId = r.PostId
  LEFT JOIN TopVotedAuthors a ON a.UserId = r.OwnerUserId
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
)
SELECT
  c.PostId,
  c.PostTitle,
  c.PostScore,
  COALESCE(c.OwnerDisplayName, 'Unknown') AS Owner,
  c.LastActivityDate,
  c.CommentCount,
  c.FavoriteCount,
  COALESCE(c.AvgCommentScore, 0) AS AvgCommentScore,
  COALESCE(c.ScoreSum, 0) AS TagScoreTotal,
  COALESCE(c.TagPostCount, 0) AS TagPopularityRank,
  COALESCE(c.AvgOwnerScore, 0) AS AvgOwnerPostScore,
  COALESCE(c.TotalBounty, 0) AS OwnerTotalBounty,
  CASE
    WHEN c.PostScore >= 50 THEN 'Hot'
    WHEN c.PostScore >= 20 THEN 'Active'
    ELSE 'New'
  END AS ActivityTier,
  COALESCE(c.NumComments, 0) AS NumComments
FROM CrossJoinSample c
ORDER BY c.PostScore DESC NULLS LAST, c.LastActivityDate DESC
LIMIT 100;