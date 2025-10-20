-- {"query": "43059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 513} 

WITH UserActivity AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(Score) AS TotalScore,
        AVG(ViewCount) AS AvgViewCount,
        MAX(CreationDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ua.TotalPosts,
        ua.TotalScore,
        ua.AvgViewCount,
        RANK() OVER (ORDER BY ua.TotalScore DESC, u.Reputation DESC) AS Rank
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    WHERE u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
),
TagStatistics AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.AnswerCount) AS AvgAnswers
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
ComplexQuery AS (
    SELECT
        tc.DisplayName,
        tc.Reputation,
        ts.TagName,
        ts.QuestionCount,
        ts.TotalViews,
        ts.AvgAnswers,
        (SELECT COUNT(*) FROM Badges WHERE UserId = tc.Id AND Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Comments WHERE UserId = tc.Id AND Score > 10) AS HighScoreComments
    FROM TopContributors tc
    CROSS JOIN TagStatistics ts
    WHERE tc.Rank <= 10
)
SELECT
    DisplayName,
    Reputation,
    TagName,
    QuestionCount,
    TotalViews,
    AvgAnswers,
    GoldBadges,
    HighScoreComments
FROM ComplexQuery
ORDER BY Reputation DESC, TotalViews DESC
LIMIT 50;
