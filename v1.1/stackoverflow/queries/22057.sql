-- {"query": "22057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1329} 
WITH UserBadgeStats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           COUNT(b.Id) AS TotalBadges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           AVG(b.Class) AS AvgBadgeClass,
           STRING_AGG(b.Name, '; ') AS BadgeNames
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostStats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(p.Id) AS TotalPosts,
           SUM(p.Score) AS TotalScore,
           AVG(p.Score) AS AvgScore,
           MAX(p.Score) AS MaxScore,
           MIN(p.Score) AS MinScore,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
           COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 2 THEN p.ParentId END) AS AcceptedAnswers,
           STRING_AGG(LEFT(p.Title, 50), ', ') FILTER (WHERE p.PostTypeId = 1) AS SampleTitles
    FROM Posts p
    GROUP BY p.OwnerUserId
),
CommentStats AS (
    SELECT c.UserId,
           COUNT(c.Id) AS TotalComments,
           SUM(c.Score) AS CommentScoreSum,
           AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
VoteStats AS (
    SELECT v.UserId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
           COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS BountiesStarted,
           SUM(v.BountyAmount) AS TotalBountyAmount
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
CombinedStats AS (
    SELECT COALESCE(ubs.UserId, ps.UserId, cs.UserId, vs.UserId) AS UserId,
           ubs.DisplayName,
           COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
           COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
           COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
           COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
           ubs.AvgBadgeClass,
           ubs.BadgeNames,
           COALESCE(ps.TotalPosts, 0) AS TotalPosts,
           COALESCE(ps.TotalScore, 0) AS TotalScore,
           ps.AvgScore,
           ps.MaxScore,
           ps.MinScore,
           COALESCE(ps.Questions, 0) AS Questions,
           COALESCE(ps.Answers, 0) AS Answers,
           COALESCE(ps.AcceptedAnswers, 0) AS AcceptedAnswers,
           ps.SampleTitles,
           COALESCE(cs.TotalComments, 0) AS TotalComments,
           COALESCE(cs.CommentScoreSum, 0) AS CommentScoreSum,
           cs.AvgCommentLength,
           COALESCE(vs.UpVotesReceived, 0) AS UpVotesReceived,
           COALESCE(vs.DownVotesReceived, 0) AS DownVotesReceived,
           COALESCE(vs.BountiesStarted, 0) AS BountiesStarted,
           COALESCE(vs.TotalBountyAmount, 0) AS TotalBountyAmount
    FROM UserBadgeStats ubs
    FULL OUTER JOIN PostStats ps ON ubs.UserId = ps.UserId
    FULL OUTER JOIN CommentStats cs ON ubs.UserId = cs.UserId
    FULL OUTER JOIN VoteStats vs ON ubs.UserId = vs.UserId
),
RankedUsers AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY (TotalScore + CommentScoreSum + TotalBountyAmount) DESC, TotalPosts DESC) AS OverallRank,
           RANK() OVER (PARTITION BY GoldBadges ORDER BY TotalScore DESC) AS RankInGoldTier,
           NTILE(10) OVER (ORDER BY TotalPosts DESC) AS PostDecile,
           LAG(TotalScore, 1) OVER (ORDER BY TotalScore DESC) - TotalScore AS ScoreDiffFromPrev
    FROM CombinedStats
)
SELECT ru.*,
       CASE 
           WHEN ru.TotalPosts > 0 AND ru.TotalScore / NULLIF(ru.TotalPosts, 0) > (SELECT AVG(TotalScore / NULLIF(TotalPosts, 0)) FROM CombinedStats WHERE TotalPosts > 0) THEN 'High Performer'
           WHEN ru.GoldBadges > 0 THEN 'Elite'
           WHEN ru.TotalPosts = 0 THEN 'New User'
           ELSE 'Regular'
       END AS UserCategory,
       (ru.TotalScore + ru.CommentScoreSum) / NULLIF(ru.TotalPosts, 0) AS EfficiencyRatio,
       CONCAT(LEFT(ru.DisplayName, 10), '...') AS ShortName,
       EXTRACT(YEAR FROM cast('2024-10-01 12:34:56' as timestamp)) - EXTRACT(YEAR FROM (SELECT MIN(CreationDate) FROM Posts WHERE OwnerUserId = ru.UserId)) AS AccountAgeYears
FROM RankedUsers ru
WHERE ru.TotalBadges > 0 OR ru.TotalPosts > 0
  AND EXISTS (
      SELECT 1 
      FROM Posts p 
      WHERE p.OwnerUserId = ru.UserId 
      AND p.Score > (
          SELECT AVG(Score) 
          FROM Posts 
          WHERE PostTypeId = 1
      )
  )
UNION ALL
SELECT ru.*,
       'No Match' AS UserCategory,
       NULL AS EfficiencyRatio,
       '' AS ShortName,
       NULL AS AccountAgeYears
FROM RankedUsers ru
WHERE ru.TotalBadges = 0 AND ru.TotalPosts = 0
ORDER BY OverallRank, UserId;