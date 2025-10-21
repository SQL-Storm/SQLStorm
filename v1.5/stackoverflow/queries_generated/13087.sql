-- {"query": "13087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 621} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        AVG(p.ViewCount) AS AvgPostViews
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
        AND u.Reputation > 1000
    GROUP BY 
        u.Id
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        ph.Comment AS CloseReason,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS UserQuestionRank
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
        AND p.Score > 5
),
BadgeSummary AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    u.DisplayName,
    ua.TotalPosts,
    ua.HighScorePosts,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    tq.Title AS TopQuestion,
    tq.ViewCount AS TopQuestionViews,
    tq.AnswerCount AS TopQuestionAnswers,
    tq.CloseReason
FROM 
    UserActivity ua
JOIN 
    Users u ON ua.UserId = u.Id
LEFT JOIN 
    BadgeSummary b ON ua.UserId = b.UserId
LEFT JOIN 
    TopQuestions tq ON ua.UserId = tq.OwnerUserId AND tq.UserQuestionRank = 1
WHERE 
    ua.PostRank <= 10
    AND u.Location IS NOT NULL
ORDER BY 
    ua.TotalPosts DESC, u.Reputation DESC;
