-- {"query": "20075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1441} 

WITH UserActivitySummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgPostScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViewCount,
    SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCount
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(p.Id) > 50
),
UserBadgeAnalysis AS (
  SELECT
    UserId,
    COUNT(*) AS TotalBadges,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    -- Calculate a badge diversity score
    (COUNT(DISTINCT Name)::decimal / NULLIF(COUNT(*), 0)) * 100 AS BadgeDiversityPercent
  FROM Badges
  GROUP BY UserId
),
RankedUsers AS (
  SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    -- Composite score for ranking, penalizing users with a high question-to-answer ratio
    (uas.Reputation * 0.6 + uas.TotalScore * 0.4 + COALESCE(uba.GoldBadges, 0) * 100)
    / (1 + (uas.QuestionCount::decimal / NULLIF(uas.AnswerCount, 0))) AS CompositeScore,
    DENSE_RANK() OVER (ORDER BY
      (uas.Reputation * 0.6 + uas.TotalScore * 0.4 + COALESCE(uba.GoldBadges, 0) * 100)
      / (1 + (uas.QuestionCount::decimal / NULLIF(uas.AnswerCount, 0))) DESC
    ) AS UserRank
  FROM UserActivitySummary uas
  LEFT JOIN UserBadgeAnalysis uba ON uas.UserId = uba.UserId
  WHERE uas.UserCreationDate < (NOW() - INTERVAL '5 year')
),
UserPostAnalysis AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.ParentId,
    p.AcceptedAnswerId,
    -- Time since the user's last post
    p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS TimeSinceLastPost,
    -- Rank user's posts by score
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRankByScore,
    -- Calculate score as a percentage of the user's total score
    (p.Score::decimal / NULLIF((SELECT TotalScore FROM UserActivitySummary uas WHERE uas.UserId = p.OwnerUserId), 0)) * 100 AS ScoreContributionPercent
  FROM Posts p
  WHERE p.OwnerUserId IN (SELECT UserId FROM RankedUsers WHERE UserRank <= 100)
    AND p.CommunityOwnedDate IS NULL
)
SELECT
  ru.UserRank,
  ru.DisplayName,
  ru.Reputation,
  upa.Title AS PostTitle,
  pt.Name AS PostType,
  upa.Score AS PostScore,
  upa.ScoreContributionPercent,
  -- String manipulation on tags
  'Tags: ' || COALESCE(REPLACE(SUBSTRING(upa.Tags, 2, LENGTH(upa.Tags) - 2), '><', ', '), 'N/A') AS FormattedTags,
  EXTRACT(YEAR FROM upa.CreationDate) AS PostYear,
  upa.TimeSinceLastPost,
  -- Correlated subquery to get high-score comment count on the post
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = upa.PostId AND c.Score >= 5) AS HighScoreCommentCount,
  -- Analyze the corresponding Question if the post is an Answer
  CASE
    WHEN upa.PostTypeId = 2 THEN (SELECT q.Title FROM Posts q WHERE q.Id = upa.ParentId)
    ELSE 'N/A'
  END AS RelatedQuestionTitle,
  -- Check if this answer was accepted using a subquery
  CASE
    WHEN upa.PostTypeId = 2 THEN (
      SELECT q.AcceptedAnswerId = upa.PostId FROM Posts q WHERE q.Id = upa.ParentId
    )
    ELSE NULL
  END AS IsAcceptedAnswer,
  -- Check if the post is linked to by another post (e.g. as a canonical answer)
  EXISTS(SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = upa.PostId AND pl.LinkTypeId = 1) AS IsLinkedTarget
FROM RankedUsers ru
JOIN UserPostAnalysis upa ON ru.UserId = upa.OwnerUserId
JOIN PostTypes pt ON upa.PostTypeId = pt.Id
WHERE
  ru.UserRank <= 10
  AND upa.PostRankByScore <= 3
  AND (
    upa.Score > (SELECT percentile_cont(0.90) FROM Posts WHERE OwnerUserId = ru.UserId)
    OR upa.PostId IN (SELECT PostId FROM Votes WHERE VoteTypeId = 5 GROUP BY PostId HAVING COUNT(*) > 20)
  )
ORDER BY
  ru.UserRank,
  upa.PostRankByScore;
