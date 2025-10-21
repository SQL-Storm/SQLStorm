-- {"query": "50091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1057} 

WITH UserPostMetrics AS (
  SELECT
    OwnerUserId AS UserId,
    COUNT(*) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
    COUNT(*) FILTER (WHERE PostTypeId = 2) AS AnswerCount,
    SUM(Score) AS TotalPostScore,
    AVG(Score) FILTER (WHERE PostTypeId = 2) AS AvgAnswerScore,
    SUM(ViewCount) AS TotalViewCount,
    SUM(FavoriteCount) AS TotalFavoriteCount,
    MIN(CreationDate) AS FirstPostDate,
    MAX(LastActivityDate) AS LastPostActivity
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY
    OwnerUserId
), UserBadgeAchievements AS (
  SELECT
    UserId,
    COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
    MIN(Date) FILTER (WHERE Class = 1) AS FirstGoldBadgeDate
  FROM Badges
  GROUP BY
    UserId
), TagMasters AS (
  SELECT
    p.OwnerUserId AS UserId,
    SUM(p.Score) AS TagScore,
    SUM(p.AnswerCount) AS TaggedQuestionsAnswerCount,
    COUNT(p.Id) AS TaggedQuestionCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TopTags
  FROM Posts p
  JOIN Tags t
    ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND t.Count > 10000
  GROUP BY
    p.OwnerUserId
  HAVING
    COUNT(p.Id) > 5
), UserInteractionStats AS (
  SELECT
    u.Id AS UserId,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalCommentsMade,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVotesGiven,
    (SELECT SUM(BountyAmount) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS TotalBountyAmountGiven
  FROM Users u
)
SELECT
  u.DisplayName,
  u.Reputation,
  u.Location,
  upm.QuestionCount,
  upm.AnswerCount,
  upm.TotalPostScore,
  upm.AvgAnswerScore,
  upm.TotalViewCount,
  uba.GoldBadges,
  uba.SilverBadges,
  uis.TotalCommentsMade,
  uis.UpVotesGiven,
  tm.TagScore AS PopularTagScore,
  tm.TopTags,
  (uba.FirstGoldBadgeDate - upm.FirstPostDate) AS TimeToFirstGold,
  (
    (u.Reputation * 0.2) + (upm.TotalPostScore * 0.15) + (tm.TagScore * 0.3) + (COALESCE(upm.TotalFavoriteCount, 0) * 2) + (uba.GoldBadges * 100) - (uis.DownVotesGiven * 0.5)
  ) AS OverallInfluenceScore,
  RANK() OVER (PARTITION BY SUBSTRING(u.Location, 1, 3) ORDER BY (
    (u.Reputation * 0.2) + (upm.TotalPostScore * 0.15) + (tm.TagScore * 0.3) + (COALESCE(upm.TotalFavoriteCount, 0) * 2) + (uba.GoldBadges * 100) - (uis.DownVotesGiven * 0.5)
  ) DESC) AS RankInLocationGroup
FROM Users u
JOIN UserPostMetrics upm
  ON u.Id = upm.UserId
JOIN UserBadgeAchievements uba
  ON u.Id = uba.UserId
JOIN TagMasters tm
  ON u.Id = tm.UserId
JOIN UserInteractionStats uis
  ON u.Id = uis.UserId
WHERE
  u.Reputation > 20000 AND u.Location IS NOT NULL AND upm.AnswerCount > upm.QuestionCount AND uba.GoldBadges > 1 AND upm.LastPostActivity > (CURRENT_TIMESTAMP - INTERVAL '3 year') AND tm.TaggedQuestionsAnswerCount > 100
ORDER BY
  OverallInfluenceScore DESC
LIMIT 200;
