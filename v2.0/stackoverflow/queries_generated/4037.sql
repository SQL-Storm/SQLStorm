-- {"query": "4037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1553} 

WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      MAX(p.CreationDate) AS LastPostDate,
      AVG(p.Score) AS AvgPostScore,
      SUM(p.FavoriteCount) AS TotalFavorites
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteActivity AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE NULL END) AS BountyStartCount
    FROM Votes AS v
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  UserBadgeDistribution AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadgeCount,
      COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadgeCount,
      COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadgeCount
    FROM Badges AS b
    GROUP BY
      b.UserId
  ),
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS ViewRank,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate AS UserLastAccessDate,
  COALESCE(upa.PostCount, 0) AS TotalPosts,
  COALESCE(upa.QuestionCount, 0) AS TotalQuestions,
  COALESCE(upa.AnswerCount, 0) AS TotalAnswers,
  COALESCE(u.UpVotes, 0) AS UserUpVotesGiven,
  COALESCE(u.DownVotes, 0) AS UserDownVotesGiven,
  COALESCE(uva.UpVoteCount, 0) AS VotesUpReceived,
  COALESCE(uva.DownVoteCount, 0) AS VotesDownReceived,
  COALESCE(uca.CommentCount, 0) AS TotalCommentsMade,
  COALESCE(uca.AvgCommentScore, 0.0) AS AvgCommentScore,
  COALESCE(ubd.GoldBadgeCount, 0) AS GoldBadges,
  COALESCE(ubd.SilverBadgeCount, 0) AS SilverBadges,
  COALESCE(ubd.BronzeBadgeCount, 0) AS BronzeBadges,
  CASE
    WHEN upa.PostCount > 0 THEN CAST(upa.TotalFavorites AS REAL) / upa.PostCount
    ELSE 0.0
  END AS AvgFavoritesPerPost,
  COALESCE(upa.AvgPostScore, 0.0) AS AvgPostScore,
  CASE
    WHEN rp.ScoreRank <= 3 THEN rp.Title
    ELSE 'No Top 3 Posts'
  END AS TopPostTitle,
  CASE
    WHEN rp.ScoreRank <= 3 THEN rp.Score
    ELSE 0
  END AS TopPostScore,
  CASE
    WHEN rp.ScoreRank <= 3 THEN rp.ViewRank
    ELSE 0
  END AS TopPostViewRank,
  CASE
    WHEN rp.PreviousScore > 0 AND rp.NextScore > 0 THEN (rp.NextScore - rp.PreviousScore)
    ELSE 0
  END AS ScoreChangeBetweenAdjacentPosts,
  LOWER(SUBSTRING(u.Location FROM 1 FOR 3)) AS LocationPrefix,
  LENGTH(u.AboutMe) AS AboutMeLength,
  CASE
    WHEN u.WebsiteUrl LIKE '%stackexchange.com%' THEN 'StackExchange Network'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Specific'
    WHEN u.WebsiteUrl IS NOT NULL THEN 'Other'
    ELSE 'No Website'
  END AS WebsiteCategory,
  COALESCE(CAST(upa.LastPostDate AS VARCHAR), 'Never') AS LastPostActivity,
  COALESCE(CAST(uca.LastCommentDate AS VARCHAR), 'Never') AS LastCommentActivity,
  CASE
    WHEN u.LastAccessDate > DATE('now', '-90 day') THEN 'Active Recently'
    WHEN u.LastAccessDate > DATE('now', '-365 day') THEN 'Moderately Active'
    ELSE 'Inactive'
  END AS UserActivityStatus
FROM Users AS u
LEFT JOIN UserPostActivity AS upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN UserCommentActivity AS uca
  ON u.Id = uca.UserId
LEFT JOIN UserVoteActivity AS uva
  ON u.Id = uva.UserId
LEFT JOIN UserBadgeDistribution AS ubd
  ON u.Id = ubd.UserId
LEFT JOIN RankedPosts AS rp
  ON u.Id = rp.OwnerUserId AND rp.ScoreRank <= 3
WHERE
  u.DisplayName IS NOT NULL
  AND u.Reputation > 1000
ORDER BY
  u.Reputation DESC,
  UserActivityStatus,
  UPA.PostCount DESC
LIMIT 100;
