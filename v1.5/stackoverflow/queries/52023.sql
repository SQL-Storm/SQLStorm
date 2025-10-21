-- {"query": "52023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 460} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 AND v.VoteTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScoreWithUpvotes,
        COUNT(CASE WHEN p.PostTypeId = 2 AND p.Score >= 5 THEN 1 END) AS HighScoreAnswerCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(CASE WHEN p.PostTypeId = 2 AND p.Score >= 5 THEN 1 END) > 0
),
RankedUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        BadgeCount,
        TotalQuestionViews,
        AvgAnswerScoreWithUpvotes,
        HighScoreAnswerCount,
        RANK() OVER (ORDER BY AvgAnswerScoreWithUpvotes DESC, Reputation DESC, BadgeCount DESC) AS UserRank
    FROM UserStats
    WHERE BadgeCount > 10 AND AvgAnswerScoreWithUpvotes IS NOT NULL
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.BadgeCount,
    ru.TotalQuestionViews,
    ru.AvgAnswerScoreWithUpvotes,
    ru.HighScoreAnswerCount,
    ru.UserRank,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT SUM(c.Score) FROM Comments c JOIN Posts p ON c.PostId = p.Id WHERE p.OwnerUserId = ru.UserId) AS TotalCommentScoreOnPosts
FROM RankedUsers ru
WHERE ru.UserRank <= 10
ORDER BY ru.UserRank;