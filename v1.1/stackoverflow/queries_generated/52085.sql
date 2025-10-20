-- {"query": "52085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 619} 
WITH MonthlyActivity AS (
    SELECT
        DATE_TRUNC('month', p.CreationDate) AS Month,
        COUNT(DISTINCT p.Id) AS PostsCreated,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT v.Id) AS VotesCast
    FROM Posts p
    FULL OUTER JOIN Comments c ON DATE_TRUNC('month', p.CreationDate) = DATE_TRUNC('month', c.CreationDate)
    FULL OUTER JOIN Votes v ON DATE_TRUNC('month', p.CreationDate) = DATE_TRUNC('month', v.CreationDate)
    GROUP BY DATE_TRUNC('month', p.CreationDate)
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TagPostAnalytics AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.AnswerCount) AS AvgAnswers
    FROM Tags t
    JOIN Posts p ON POSITION(t.TagName IN COALESCE(p.Tags, '')) > 0
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
TopVoters AS (
    SELECT
        v.UserId,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(v.Id) DESC) AS Rank
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.UserId
)
SELECT
    ma.Month,
    ma.PostsCreated,
    ma.CommentsMade,
    ma.VotesCast,
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.TotalQuestionViews,
    ups.AvgAnswerScore,
    ups.BadgeCount,
    tpa.TagName,
    tpa.PostCount,
    tpa.TotalScore,
    tpa.AvgAnswers,
    tv.VoteCount,
    tv.Rank
FROM MonthlyActivity ma
CROSS JOIN (
    SELECT * FROM UserPostStats ORDER BY TotalPosts DESC LIMIT 100
) ups
LEFT JOIN TagPostAnalytics tpa ON tpa.TotalScore > (SELECT AVG(TotalScore) FROM TagPostAnalytics)
LEFT JOIN TopVoters tv ON ups.UserId = tv.UserId
ORDER BY ma.Month, tv.Rank, tpa.TotalScore DESC;