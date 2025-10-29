-- {"query": "4709.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1771}
WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AverageViewCount,
      MAX(p.CreationDate) AS LatestPostDate,
      STRING_AGG(pt.Name, ', ' ORDER BY pt.Name) AS PostTypes
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AverageCommentScore,
      COUNT(CASE WHEN c.Text LIKE '%interesting%' THEN 1 END) AS InterestingCommentCount
    FROM Comments c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(v.Id) AS VoteCount,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(CASE WHEN v.BountyAmount IS NOT NULL THEN 1 END) AS BountyGivenCount
    FROM Votes v
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  RankedPosts AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.ViewCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank,
      DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS GlobalViewRank,
      LAG(p.CreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate
    FROM Posts p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(ups.PostCount, 0) AS TotalPosts,
  COALESCE(ups.TotalScore, 0) AS TotalScore,
  COALESCE(ups.AverageViewCount, 0) AS AvgPostViews,
  ups.PostTypes,
  COALESCE(ucs.CommentCount, 0) AS TotalComments,
  COALESCE(ucs.AverageCommentScore, 0) AS AvgCommentScore,
  COALESCE(ucs.InterestingCommentCount, 0) AS InterestingCommentCount,
  COALESCE(uvs.VoteCount, 0) AS TotalVotes,
  COALESCE(uvs.UpVoteCount, 0) AS TotalUpvotes,
  COALESCE(uvs.DownVoteCount, 0) AS TotalDownvotes,
  COALESCE(uvs.BountyGivenCount, 0) AS BountyGivenCount,
  rp.Title AS TopScoringPostTitle,
  rp.Score AS TopScoringPostScore,
  rp.AnswerCount AS TopScoringPostAnswerCount,
  rp.ViewCount AS TopScoringPostViews,
  rp.GlobalViewRank,
  CASE
    WHEN ups.LatestPostDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR) THEN 'Recent'
    WHEN ups.LatestPostDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5' YEAR) THEN 'Active'
    ELSE 'Dormant'
  END AS UserActivityStatus,
  CASE
    WHEN rp.ScoreRank <= 1 AND rp.Score > 100 THEN 'Elite Questioner'
    WHEN rp.ScoreRank <= 3 AND rp.Score > 50 THEN 'Prolific Questioner'
    ELSE 'Standard Questioner'
  END AS QuestionerTier,
  CAST(DATE_PART('day', COALESCE(ups.LatestPostDate, TIMESTAMP '1970-01-01 00:00:00') - COALESCE(rp.PreviousPostDate, TIMESTAMP '1970-01-01 00:00:00')) AS INTEGER) AS DaysSinceLastPost,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Network'
    ELSE 'External Website'
  END AS WebsiteCategory
FROM Users u
LEFT JOIN UserPostStats ups
  ON u.Id = ups.OwnerUserId
LEFT JOIN UserCommentStats ucs
  ON u.Id = ucs.UserId
LEFT JOIN UserVoteStats uvs
  ON u.Id = uvs.UserId
LEFT JOIN RankedPosts rp
  ON u.Id = rp.OwnerUserId AND rp.ScoreRank = 1
WHERE
  u.Reputation > 1000
  AND u.CreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH)
  AND COALESCE(ups.PostCount, 0) > 5
UNION
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(ups.PostCount, 0) AS TotalPosts,
  COALESCE(ups.TotalScore, 0) AS TotalScore,
  COALESCE(ups.AverageViewCount, 0) AS AvgPostViews,
  ups.PostTypes,
  COALESCE(ucs.CommentCount, 0) AS TotalComments,
  COALESCE(ucs.AverageCommentScore, 0) AS AvgCommentScore,
  COALESCE(ucs.InterestingCommentCount, 0) AS InterestingCommentCount,
  COALESCE(uvs.VoteCount, 0) AS TotalVotes,
  COALESCE(uvs.UpVoteCount, 0) AS TotalUpvotes,
  COALESCE(uvs.DownVoteCount, 0) AS TotalDownvotes,
  COALESCE(uvs.BountyGivenCount, 0) AS BountyGivenCount,
  rp.Title AS TopScoringPostTitle,
  rp.Score AS TopScoringPostScore,
  rp.AnswerCount AS TopScoringPostAnswerCount,
  rp.ViewCount AS TopScoringPostViews,
  rp.GlobalViewRank,
  CASE
    WHEN ups.LatestPostDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR) THEN 'Recent'
    WHEN ups.LatestPostDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5' YEAR) THEN 'Active'
    ELSE 'Dormant'
  END AS UserActivityStatus,
  CASE
    WHEN rp.ScoreRank <= 1 AND rp.Score > 100 THEN 'Elite Questioner'
    WHEN rp.ScoreRank <= 3 AND rp.Score > 50 THEN 'Prolific Questioner'
    ELSE 'Standard Questioner'
  END AS QuestionerTier,
  CAST(DATE_PART('day', COALESCE(ups.LatestPostDate, TIMESTAMP '1970-01-01 00:00:00') - COALESCE(rp.PreviousPostDate, TIMESTAMP '1970-01-01 00:00:00')) AS INTEGER) AS DaysSinceLastPost,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Network'
    ELSE 'External Website'
  END AS WebsiteCategory
FROM Users u
LEFT JOIN UserPostStats ups
  ON u.Id = ups.OwnerUserId
LEFT JOIN UserCommentStats ucs
  ON u.Id = ucs.UserId
LEFT JOIN UserVoteStats uvs
  ON u.Id = uvs.UserId
LEFT JOIN RankedPosts rp
  ON u.Id = rp.OwnerUserId AND rp.ScoreRank = 1
WHERE
  u.Reputation <= 1000
  AND COALESCE(ups.PostCount, 0) > 10
ORDER BY
  UserId;