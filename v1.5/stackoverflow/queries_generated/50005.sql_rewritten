-- {"query": "50005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1070} 
WITH AnswererStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalAnswers,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.CommentCount) AS AvgAnswerComments,
        MIN(p.CreationDate) AS FirstAnswerDate,
        MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
QuestionerStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalQuestions,
        SUM(p.Score) AS TotalQuestionScore,
        AVG(p.ViewCount) AS AvgQuestionViews,
        SUM(p.FavoriteCount) AS TotalFavoritesReceived
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.Location,
    COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(qs.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    (COALESCE(ans.TotalAnswerScore, 0) * 0.5) + (COALESCE(qs.TotalQuestionScore, 0) * 0.2) + (u.Reputation * 0.1) + (COALESCE(bs.GoldBadges, 0) * 10) + (COALESCE(vs.UpvotesGiven, 0) * 0.05) AS CalculatedInfluenceScore,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    NTILE(100) OVER (ORDER BY (COALESCE(ans.TotalAnswerScore, 0) * 0.5) + (COALESCE(qs.TotalQuestionScore, 0) * 0.2) + (u.Reputation * 0.1) + (COALESCE(bs.GoldBadges, 0) * 10) + (COALESCE(vs.UpvotesGiven, 0) * 0.05) DESC) AS InfluencePercentile,
    LAST_VALUE(p.Title) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastPostTitle,
    EXTRACT(EPOCH FROM (ans.LastAnswerDate - ans.FirstAnswerDate)) / 86400.0 / NULLIF(ans.TotalAnswers, 0) AS AvgDaysBetweenAnswers
FROM Users u
LEFT JOIN AnswererStats ans ON u.Id = ans.OwnerUserId
LEFT JOIN QuestionerStats qs ON u.Id = qs.OwnerUserId
LEFT JOIN UserBadgeStats bs ON u.Id = bs.UserId
LEFT JOIN UserVoteStats vs ON u.Id = vs.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 1)
  AND u.CreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
  AND COALESCE(ans.TotalAnswers, 0) > COALESCE(qs.TotalQuestions, 0)
  AND u.Id IN (
    SELECT DISTINCT c.UserId
    FROM Comments c
    JOIN Posts cp ON c.PostId = cp.Id
    WHERE c.Score > 10 AND cp.PostTypeId = 1
)
ORDER BY CalculatedInfluenceScore DESC, u.Reputation DESC
LIMIT 500;