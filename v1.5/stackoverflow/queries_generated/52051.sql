-- {"query": "52051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 715} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS BadgeScore,
        COUNT(DISTINCT v.Id) AS UpvotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalQuestions,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.ViewCount) AS MaxViews
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
AnswerStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(CASE WHEN p.Id = pp.AcceptedAnswerId THEN 1 END) AS AcceptedAnswers
    FROM Posts p
    LEFT JOIN Posts pp ON p.Id = pp.AcceptedAnswerId
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
TagUsage AS (
    SELECT 
        p.OwnerUserId,
        t.TagName,
        COUNT(*) AS TagPosts
    FROM Posts p
    CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag
    JOIN Tags t ON t.TagName = tag
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
TopTag AS (
    SELECT 
        OwnerUserId,
        TagName,
        TagPosts,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagPosts DESC) AS rn
    FROM TagUsage
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.TotalPostScore,
    us.TotalViews,
    us.TotalBadges,
    us.BadgeScore,
    us.UpvotesReceived,
    qs.TotalQuestions,
    qs.AvgQuestionScore,
    qs.MaxViews,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.AcceptedAnswers,
    tt.TagName AS TopTag,
    (us.Reputation * 0.1 + us.TotalPostScore * 0.2 + us.UpvotesReceived * 0.3 + us.BadgeScore * 0.4) AS CompositeScore
FROM UserStats us
LEFT JOIN QuestionStats qs ON us.UserId = qs.OwnerUserId
LEFT JOIN AnswerStats ans ON us.UserId = ans.OwnerUserId
LEFT JOIN TopTag tt ON us.UserId = tt.OwnerUserId AND tt.rn = 1
WHERE us.TotalPosts > 0
ORDER BY CompositeScore DESC, us.TotalPosts DESC
LIMIT 100;