-- {"query": "50065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 941} 

WITH UserAnswerStats AS (
  SELECT
    OwnerUserId,
    SUM(Score) AS TotalAnswerScore,
    COUNT(Id) AS TotalAnswers
  FROM Posts
  WHERE
    PostTypeId = 2
    AND OwnerUserId IS NOT NULL
  GROUP BY
    OwnerUserId
), UserVoteStats AS (
  SELECT
    p.OwnerUserId,
    COUNT(v.Id) AS UpvotesReceived
  FROM Votes AS v
  JOIN Posts AS p
    ON v.PostId = p.Id
  WHERE
    v.VoteTypeId = 2
    AND p.OwnerUserId IS NOT NULL
  GROUP BY
    p.OwnerUserId
), UserBadgeStats AS (
  SELECT
    UserId,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
  FROM Badges
  GROUP BY
    UserId
), UserActivitySummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
    u.Views,
    COALESCE(uas.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(uas.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(uvs.UpvotesReceived, 0) AS UpvotesReceived,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    (
      u.Reputation * 0.2 + COALESCE(uas.TotalAnswerScore, 0) * 0.3 + COALESCE(uvs.UpvotesReceived, 0) * 0.5 + COALESCE(ubs.GoldBadges, 0) * 100 + COALESCE(ubs.SilverBadges, 0) * 25
    ) AS EngagementScore
  FROM Users AS u
  LEFT JOIN UserAnswerStats AS uas
    ON u.Id = uas.OwnerUserId
  LEFT JOIN UserVoteStats AS uvs
    ON u.Id = uvs.OwnerUserId
  LEFT JOIN UserBadgeStats AS ubs
    ON u.Id = ubs.UserId
  WHERE
    u.Reputation > 1000 AND u.AccountId IS NOT NULL
), RankedUsers AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY JoinYear ORDER BY EngagementScore DESC, Reputation DESC) AS YearlyRank
  FROM UserActivitySummary
)
SELECT
  ru.JoinYear,
  ru.YearlyRank,
  ru.UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.EngagementScore,
  ru.TotalAnswers,
  ru.UpvotesReceived,
  ru.GoldBadges,
  ru.SilverBadges,
  lp.Title AS LastPostTitle,
  lp.CreationDate AS LastPostDate,
  lp.ViewCount AS LastPostViewCount,
  lp.Score AS LastPostScore,
  lc.Text AS LastCommentText,
  lc.CreationDate AS LastCommentDate,
  lc.Score AS LastCommentScore
FROM RankedUsers AS ru
LEFT JOIN LATERAL (
  SELECT
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score
  FROM Posts AS p
  WHERE
    p.OwnerUserId = ru.UserId
  ORDER BY
    p.LastActivityDate DESC
  LIMIT 1
) lp
  ON TRUE
LEFT JOIN LATERAL (
  SELECT
    c.Text,
    c.CreationDate,
    c.Score
  FROM Comments AS c
  WHERE
    c.UserId = ru.UserId
  ORDER BY
    c.CreationDate DESC
  LIMIT 1
) lc
  ON TRUE
WHERE
  ru.YearlyRank <= 10
ORDER BY
  ru.JoinYear ASC,
  ru.YearlyRank ASC;
