-- {"query": "5313.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 898} 
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
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
),
TagHub AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) FILTER (WHERE p.OwnerUserId IS NOT NULL) AS AvgOwnerScore,
    MAX(p.LastActivityDate) AS LastActive
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
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
  ) AS t
  GROUP BY t.TagName
),
CorrelatedCommentStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    COUNT(c.Id) AS NumComments,
    AVG(COALESCE(c.Score,0)) AS AvgCommentScore
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
    t.TagName,
    t.TagPostCount,
    t.ScoreSum,
    t.AvgOwnerScore,
    ch.NumComments,
    ch.AvgCommentScore,
    u.UserId AS OwnerId,
    u.DisplayName AS OwnerDisplayName,
    a.TotalBounty
  FROM RecentActivePosts r
  LEFT JOIN LATERAL (
    SELECT * FROM TagHub th WHERE th.TagName IS NOT NULL ORDER BY th.TagPostCount DESC LIMIT 3
  ) AS t ON TRUE
  LEFT JOIN CorrelatedCommentStats ch ON ch.PostId = r.PostId
  LEFT JOIN TopVotedAuthors a ON a.UserId = r.OwnerUserId
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
)
SELECT
  PostId,
  PostTitle,
  PostScore,
  COALESCE(OwnerDisplayName, 'Unknown') AS Owner,
  LastActivityDate,
  CommentCount,
  FavoriteCount,
  COALESCE(AvgCommentScore, 0) AS AvgCommentScore,
  COALESCE(ScoreSum, 0) AS TagScoreTotal,
  COALESCE(TagPostCount, 0) AS TagPopularityRank,
  COALESCE(AvgOwnerScore, 0) AS AvgOwnerPostScore,
  COALESCE(TotalBounty, 0) AS OwnerTotalBounty,
  CASE
    WHEN PostScore >= 50 THEN 'Hot'
    WHEN PostScore >= 20 THEN 'Active'
    ELSE 'New'
  END AS ActivityTier,
  CASE
    WHEN NumComments IS NULL THEN 0 ELSE NumComments
  END AS NumComments
FROM CrossJoinSample
ORDER BY PostScore DESC NULLS LAST, LastActivityDate DESC
LIMIT 100;