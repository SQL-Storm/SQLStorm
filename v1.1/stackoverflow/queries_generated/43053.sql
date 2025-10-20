-- {"query": "43053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 540} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > NOW() - INTERVAL '1 year'
    GROUP BY u.Id
),
TagAnalysis AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionsCount,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.Score) AS MaxScore
    FROM Tags t
    JOIN Posts p ON t.Id = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')::int[])
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
)
SELECT
    ua.UserId,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgScore,
    ua.TotalEdits,
    ua.TotalBadges,
    ta.TagName,
    ta.QuestionsCount,
    ta.AvgViewCount,
    ta.MaxScore
FROM UserActivity ua
JOIN Posts p ON ua.UserId = p.OwnerUserId
JOIN TagAnalysis ta ON p.Tags LIKE CONCAT('%<', ta.TagName, '>%')
WHERE ua.ReputationRank <= 100
ORDER BY ua.TotalPosts DESC, ta.QuestionsCount DESC
LIMIT 20;
