-- {"query": "4627.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2184} 

WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalPosts,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    GROUP BY
      OwnerUserId
  ),
  UserPostScores AS (
    SELECT
      p.OwnerUserId,
      SUM(p.Score) AS TotalScore,
      AVG(p.Score) AS AvgScore
    FROM Posts AS p
    WHERE
      p.Score IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentScores AS (
    SELECT
      c.UserId,
      SUM(c.Score) AS TotalCommentScore,
      AVG(c.Score) AS AvgCommentScore
    FROM Comments AS c
    WHERE
      c.Score IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVotes,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVotes,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE NULL END) AS Favorites
    FROM Votes AS v
    JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    GROUP BY
      v.UserId
  ),
  UserBadgeCounts AS (
    SELECT
      UserId,
      COUNT(CASE WHEN Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
      COUNT(CASE WHEN Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
      COUNT(CASE WHEN Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM Badges
    GROUP BY
      UserId
  ),
  UserPostHistory AS (
    SELECT
      ph.UserId,
      COUNT(DISTINCT CASE WHEN pht.Name = 'Edit Body' THEN ph.PostId ELSE NULL END) AS EditedPosts,
      COUNT(DISTINCT CASE WHEN pht.Name = 'Post Closed' THEN ph.PostId ELSE NULL END) AS ClosedPosts,
      COUNT(DISTINCT CASE WHEN pht.Name = 'Post Deleted' THEN ph.PostId ELSE NULL END) AS DeletedPosts
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    GROUP BY
      ph.UserId
  ),
  UserActivity AS (
    SELECT
      COALESCE(upc.OwnerUserId, ucs.UserId, uv.UserId, ubc.UserId, uph.UserId) AS UserId,
      COALESCE(upc.TotalPosts, 0) AS TotalPosts,
      COALESCE(upc.QuestionCount, 0) AS QuestionCount,
      COALESCE(upc.AnswerCount, 0) AS AnswerCount,
      COALESCE(ups.TotalScore, 0) AS TotalPostScore,
      COALESCE(ups.AvgScore, 0) AS AvgPostScore,
      COALESCE(uc.TotalCommentScore, 0) AS TotalCommentScore,
      COALESCE(uc.AvgCommentScore, 0) AS AvgCommentScore,
      COALESCE(uv.UpVotes, 0) AS TotalUpVotes,
      COALESCE(uv.DownVotes, 0) AS TotalDownVotes,
      COALESCE(uv.Favorites, 0) AS TotalFavorites,
      COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
      COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
      COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
      COALESCE(uph.EditedPosts, 0) AS EditedPosts,
      COALESCE(uph.ClosedPosts, 0) AS ClosedPosts,
      COALESCE(uph.DeletedPosts, 0) AS DeletedPosts,
      ROW_NUMBER() OVER (ORDER BY COALESCE(ups.TotalScore, 0) DESC) AS ScoreRank,
      DENSE_RANK() OVER (PARTITION BY COALESCE(ubc.GoldBadges, 0) ORDER BY COALESCE(upc.TotalPosts, 0) DESC) AS BadgePostRank
    FROM Users AS u
    LEFT JOIN UserPostCounts AS upc
      ON u.Id = upc.OwnerUserId
    LEFT JOIN UserPostScores AS ups
      ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentScores AS uc
      ON u.Id = uc.UserId
    LEFT JOIN UserVoteStats AS uv
      ON u.Id = uv.UserId
    LEFT JOIN UserBadgeCounts AS ubc
      ON u.Id = ubc.UserId
    LEFT JOIN UserPostHistory AS uph
      ON u.Id = uph.UserId
  )
SELECT
  u.DisplayName,
  ua.TotalPosts,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalPostScore,
  ua.AvgPostScore,
  ua.TotalCommentScore,
  ua.AvgCommentScore,
  ua.TotalUpVotes,
  ua.TotalDownVotes,
  ua.TotalFavorites,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  ua.EditedPosts,
  ua.ClosedPosts,
  ua.DeletedPosts,
  ua.ScoreRank,
  ua.BadgePostRank,
  CASE
    WHEN ua.TotalPosts > 1000 THEN 'Veteran'
    WHEN ua.TotalPosts > 100 THEN 'Experienced'
    WHEN ua.TotalPosts > 10 THEN 'Intermediate'
    ELSE 'Novice'
  END AS ExperienceLevel,
  CASE
    WHEN ua.GoldBadges >= 5 THEN 'Elite'
    WHEN ua.GoldBadges >= 1 THEN 'Distinguished'
    ELSE 'Standard'
  END AS BadgeStatus,
  LOWER(REPLACE(u.Location, ' ', '_')) AS NormalizedLocation,
  UPPER(SUBSTRING(u.DisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Exchange Site'
    ELSE 'External Website'
  END AS WebsiteType,
  CASE
    WHEN ua.TotalPostScore > 50000 AND ua.TotalUpVotes > 10000 THEN 'Top Performer'
    WHEN ua.TotalPostScore > 10000 OR ua.TotalUpVotes > 1000 THEN 'High Performer'
    ELSE 'Average Performer'
  END AS PerformanceTier,
  COALESCE(u.Views, 0) AS UserViews,
  ua.TotalPosts + ua.TotalCommentScore AS EngagementScore,
  CASE WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name = 'Editor') THEN 'Yes' ELSE 'No' END AS HasEditorBadge
FROM Users AS u
JOIN ua
  ON u.Id = ua.UserId
WHERE
  ua.TotalPosts > 0
  AND ua.AvgPostScore > 1
  AND ua.CreationDate < '2023-01-01'
UNION
SELECT
  'Community User' AS DisplayName,
  COUNT(p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  SUM(p.Score) AS TotalPostScore,
  AVG(p.Score) AS AvgPostScore,
  SUM(c.Score) AS TotalCommentScore,
  AVG(c.Score) AS AvgCommentScore,
  COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS TotalUpVotes,
  COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS TotalDownVotes,
  COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE NULL END) AS TotalFavorites,
  0 AS GoldBadges,
  0 AS SilverBadges,
  0 AS BronzeBadges,
  0 AS EditedPosts,
  0 AS ClosedPosts,
  0 AS DeletedPosts,
  0 AS ScoreRank,
  0 AS BadgePostRank,
  'N/A' AS ExperienceLevel,
  'N/A' AS BadgeStatus,
  'community_user' AS NormalizedLocation,
  'COM' AS DisplayNamePrefix,
  'No Website' AS WebsiteType,
  'Community Performer' AS PerformanceTier,
  0 AS UserViews,
  COUNT(p.Id) + SUM(c.Score) AS EngagementScore,
  'No' AS HasEditorBadge
FROM Posts AS p
LEFT JOIN Comments AS c
  ON p.Id = c.PostId AND p.OwnerUserId = -1
LEFT JOIN Votes AS v
  ON p.Id = v.PostId AND p.OwnerUserId = -1
LEFT JOIN VoteTypes AS vt
  ON v.VoteTypeId = vt.Id
WHERE
  p.OwnerUserId = -1
GROUP BY
  p.OwnerUserId;
