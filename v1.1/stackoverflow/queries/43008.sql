WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditsMade,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        p.OwnerUserId,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '6 months'
    GROUP BY p.Id, p.Title, p.ViewCount, p.Score, p.OwnerUserId
    HAVING COUNT(DISTINCT v.Id) > 10
)
SELECT 
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.EditsMade,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    tq.Title AS TopQuestionTitle,
    tq.ViewCount,
    tq.Score,
    tq.TotalVotes
FROM UserActivity ua
JOIN TopQuestions tq ON ua.Id = tq.OwnerUserId
WHERE ua.QuestionsAsked > 5 AND tq.QuestionRank <= 10
ORDER BY tq.Score DESC, ua.EditsMade DESC
LIMIT 20;