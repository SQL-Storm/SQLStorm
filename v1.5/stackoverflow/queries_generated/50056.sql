-- {"query": "50056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 946} 

WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswerScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate < (CURRENT_DATE - INTERVAL '5 year')
      AND u.Reputation > 15000
      AND u.Location IS NOT NULL AND u.Location != ''
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 50 AND COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) > 0
),
RankedUsers AS (
    SELECT
        *,
        (TotalAnswerScore * 0.4 + TotalQuestionViews * 0.1 + Reputation * 0.3 + GoldBadges * 100) AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY Location ORDER BY (TotalAnswerScore * 0.4 + TotalQuestionViews * 0.1 + Reputation * 0.3 + GoldBadges * 100) DESC) AS LocationRank,
        NTILE(100) OVER (ORDER BY (TotalAnswerScore * 0.4 + TotalQuestionViews * 0.1 + Reputation * 0.3 + GoldBadges * 100) DESC) AS GlobalPercentile
    FROM UserMetrics
),
TopUsersPerLocation AS (
    SELECT *
    FROM RankedUsers
    WHERE LocationRank <= 3
),
UserAnswerStats AS (
    SELECT
        p.OwnerUserId,
        p_q.Tags,
        COUNT(p.Id) AS AnswerCountInTag,
        SUM(p.Score) AS ScoreInTag
    FROM Posts p
    JOIN Posts p_q ON p.ParentId = p_q.Id
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IN (SELECT UserId FROM TopUsersPerLocation)
    GROUP BY p.OwnerUserId, p_q.Tags
)
SELECT
    tu.DisplayName,
    tu.Location,
    tu.Reputation,
    tu.EngagementScore,
    tu.LocationRank,
    tu.GlobalPercentile,
    MostPopularTag.Tags AS MostActiveTag,
    MostPopularTag.AnswerCountInTag,
    MostPopularTag.ScoreInTag,
    LastQuestion.Title AS LastQuestionTitle,
    LastQuestion.CreationDate AS LastQuestionDate,
    HighestScoringAnswer.Body AS HighestAnswerBody,
    HighestScoringAnswer.Score AS HighestAnswerScore
FROM TopUsersPerLocation tu
LEFT JOIN LATERAL (
    SELECT Tags, AnswerCountInTag, ScoreInTag
    FROM UserAnswerStats uas
    WHERE uas.OwnerUserId = tu.UserId
    ORDER BY uas.ScoreInTag DESC, uas.AnswerCountInTag DESC
    LIMIT 1
) AS MostPopularTag ON true
LEFT JOIN LATERAL (
    SELECT Title, CreationDate
    FROM Posts
    WHERE OwnerUserId = tu.UserId AND PostTypeId = 1
    ORDER BY CreationDate DESC
    LIMIT 1
) AS LastQuestion ON true
LEFT JOIN LATERAL (
    SELECT Body, Score
    FROM Posts
    WHERE OwnerUserId = tu.UserId AND PostTypeId = 2
    ORDER BY Score DESC
    LIMIT 1
) AS HighestScoringAnswer ON true
WHERE tu.GlobalPercentile >= 95
ORDER BY tu.Location, tu.LocationRank;
