WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS LastGoldBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > (
        SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1
    )
),
EditedPosts AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.TotalQuestionScore,
    ua.TotalAnswerScore,
    ua.LastGoldBadgeDate,
    tq.Title AS TopQuestionTitle,
    tq.ViewCount AS TopQuestionViewCount,
    ep.EditCount
FROM UserActivity ua
LEFT JOIN TopQuestions tq ON ua.UserId = tq.OwnerUserId AND tq.rn = 1
LEFT JOIN EditedPosts ep ON tq.PostId = ep.PostId
WHERE ua.QuestionsAsked > 0 AND COALESCE(ep.EditCount, 0) > (
    SELECT AVG(EditCount) FROM EditedPosts WHERE EditCount IS NOT NULL
)
ORDER BY ua.TotalQuestionScore DESC, ua.Reputation DESC
LIMIT 10;