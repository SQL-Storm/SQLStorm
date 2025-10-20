-- {"query": "13082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 714} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgPostScore,
        MAX(u.LastAccessDate) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
QuestionMetrics AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS RankByViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '1 YEAR'
),
TopUserQuestions AS (
    SELECT
        qm.PostId,
        qm.Title,
        qm.Score,
        qm.ViewCount,
        qm.AnswerCount,
        qm.FavoriteCount
    FROM UserActivity ua
    JOIN QuestionMetrics qm ON ua.UserId = qm.OwnerUserId
    WHERE qm.RankByScore <= 5
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgPostScore,
    STRING_AGG(DISTINCT COALESCE(tuq.Title, 'N/A'), ', ') AS TopQuestions,
    SUM(CASE WHEN tuq.AnswerCount > 0 THEN 1 ELSE 0 END) AS AnsweredQuestions,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    AVG(EXTRACT(EPOCH FROM (ua.LastActivityDate - u.CreationDate)) / 86400) AS AvgActivitySpanDays
FROM UserActivity ua
JOIN Users u ON ua.UserId = u.Id
LEFT JOIN TopUserQuestions tuq ON ua.UserId = tuq.OwnerUserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId = 10
LEFT JOIN Badges b ON ua.UserId = b.UserId
GROUP BY ua.UserId, ua.DisplayName, ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.AvgPostScore, u.CreationDate
ORDER BY ua.TotalPosts DESC, ua.AvgPostScore DESC
LIMIT 10;
