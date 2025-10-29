-- {"query": "4219.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1275}
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostActivityRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PreviousReputation,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS NextReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL AND u.Location IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS GlobalTagRank
    FROM Tags t
    WHERE t.TagName NOT LIKE '%[^a-zA-Z0-9-]%'
),
UserTagEngagement AS (
    SELECT
        rua.UserId,
        tp.TagName,
        COUNT(p.Id) AS UserTagPostCount,
        ROW_NUMBER() OVER (PARTITION BY rua.UserId ORDER BY COUNT(p.Id) DESC, tp.TagPostCount DESC) AS UserTagRank
    FROM RankedUserActivity rua
    JOIN Posts p ON rua.UserId = p.OwnerUserId
    JOIN TagPopularity tp ON p.Tags LIKE '%' || tp.TagName || '%'
    WHERE tp.GlobalTagRank <= 500
    GROUP BY rua.UserId, tp.TagName, tp.TagPostCount
),
RecentHighReputationUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        CreationDate
    FROM RankedUserActivity
    WHERE ReputationRank <= 1000 AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
),
AverageAnswerQuality AS (
    SELECT
        p.Id AS QuestionId,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(a.Id) AS NumberOfAnswers,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IN (SELECT UserId FROM RecentHighReputationUsers) THEN 1 ELSE 0 END) AS AnswersFromRecentTopUsers
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '3 months')
    GROUP BY p.Id
)
SELECT
    COALESCE(rua.DisplayName, 'Anonymous') AS UserDisplayName,
    rua.Reputation,
    rua.TotalPosts,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.AveragePostScore,
    rua.ReputationRank,
    rua.PostActivityRank,
    rua.PreviousReputation,
    rua.NextReputation,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = rua.UserId AND b.Class = 1) AS GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = rua.UserId AND b.Class = 2) AS SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = rua.UserId AND b.Class = 3) AS BronzeBadgeCount,
    CASE WHEN EXISTS (SELECT 1 FROM Comments c WHERE c.UserId = rua.UserId AND c.Score > 10) THEN 'Active Commenter' ELSE 'Less Active Commenter' END AS CommenterStatus,
    (
        SELECT STRING_AGG(ute.TagName, '; ')
        FROM UserTagEngagement ute
        WHERE ute.UserId = rua.UserId AND ute.UserTagRank <= 3
    ) AS Top3Tags,
    COALESCE(aqa.AvgAnswerScore, 0) AS AvgAnswerScoreForUserQuestions,
    COALESCE(aqa.NumberOfAnswers, 0) AS AvgNumberOfAnswersForUserQuestions,
    COALESCE(aqa.AnswersFromRecentTopUsers, 0) AS UserQuestionsAnsweredByRecentTopUsers,
    (CASE WHEN rua.DisplayName ~ '[0-9]' THEN 'Contains Numbers' ELSE 'No Numbers' END) AS DisplayNameFormat,
    CASE
        WHEN rua.AveragePostScore > 50 THEN 'Excellent'
        WHEN rua.AveragePostScore > 20 THEN 'Good'
        WHEN rua.AveragePostScore > 5 THEN 'Average'
        ELSE 'Below Average'
    END AS ScoreCategory,
    CAST(rua.CreationDate AS DATE) AS UserCreationDate
FROM RankedUserActivity rua
LEFT JOIN AverageAnswerQuality aqa ON rua.UserId = aqa.QuestionId
WHERE rua.TotalPosts > 10 AND rua.Reputation > 1000
ORDER BY rua.Reputation DESC, rua.TotalPosts DESC
LIMIT 100;