-- {"query": "50053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 900} 

WITH AnswerStats AS (
  SELECT
    p_ans.OwnerUserId,
    t.TagName,
    COUNT(p_ans.Id) AS AnswerCount,
    SUM(p_ans.Score) AS TotalAnswerScore,
    AVG(p_ans.Score) AS AverageAnswerScore,
    MIN(p_ans.CreationDate) AS FirstAnswerDate,
    MAX(p_ans.CreationDate) AS LastAnswerDate
  FROM Tags AS t
  JOIN Posts AS p_q
    ON p_q.PostTypeId = 1 AND p_q.Tags LIKE '%' || t.TagName || '%'
  JOIN Posts AS p_ans
    ON p_ans.ParentId = p_q.Id AND p_ans.PostTypeId = 2
  WHERE
    t.Count > 1000 AND p_ans.OwnerUserId IS NOT NULL AND p_q.ClosedDate IS NULL
  GROUP BY
    p_ans.OwnerUserId,
    t.TagName
), BadgeStats AS (
  SELECT
    UserId,
    Name AS TagName,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  WHERE
    TagBased = B'1'
  GROUP BY
    UserId,
    Name
), ContributorScores AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    ans.TagName,
    ans.AnswerCount,
    ans.TotalAnswerScore,
    ans.AverageAnswerScore,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    (
      (ans.TotalAnswerScore * 0.4) + (ans.AnswerCount * 1.5) + (ans.AverageAnswerScore * 2.0) + (u.Reputation * 0.01) + (COALESCE(bs.GoldBadges, 0) * 100) + (COALESCE(bs.SilverBadges, 0) * 25) + (COALESCE(bs.BronzeBadges, 0) * 5)
    ) / (1 + EXTRACT(EPOCH FROM (NOW() - ans.LastAnswerDate)) / (3600*24*30)) AS WeightedScore, -- Decay score based on last activity
    ans.FirstAnswerDate,
    ans.LastAnswerDate
  FROM AnswerStats AS ans
  JOIN Users AS u
    ON ans.OwnerUserId = u.Id
  LEFT JOIN BadgeStats AS bs
    ON ans.OwnerUserId = bs.UserId AND ans.TagName = bs.TagName
  WHERE u.Reputation > 1000 AND ans.AnswerCount > 5
)
SELECT
  TagName,
  UserId,
  DisplayName,
  Reputation,
  AnswerCount,
  TotalAnswerScore,
  AverageAnswerScore,
  GoldBadges,
  SilverBadges,
  BronzeBadges,
  WeightedScore,
  DENSE_RANK() OVER (PARTITION BY TagName ORDER BY WeightedScore DESC, TotalAnswerScore DESC) AS RankInTag
FROM ContributorScores
WHERE
  WeightedScore > 50
  AND EXTRACT(YEAR FROM UserCreationDate) < EXTRACT(YEAR FROM NOW()) - 2
QUALIFY DENSE_RANK() OVER (PARTITION BY TagName ORDER BY WeightedScore DESC, TotalAnswerScore DESC) <= 10
ORDER BY
  TagName,
  RankInTag,
  WeightedScore DESC;
