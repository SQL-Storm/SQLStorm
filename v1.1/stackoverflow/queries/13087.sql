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
        u.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
        AND u.Reputation > 1000
    GROUP BY 
        u.Id
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
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
        AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
        AND p.Score > 5
),
BadgeSummary AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
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