WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COALESCE(SUM(p.Score), 0) AS TotalPostScores,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY COUNT(CASE WHEN b.Class = 1 THEN 1 END) DESC, SUM(p.Score) DESC) AS RankInLocation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    WHERE u.Location IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Location
),
HighlyActiveQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COALESCE(SUM(a.Score), 0) AS TotalAnswerScore,
        COUNT(a.Id) AS AnswerCount
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount
)
SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalPostScores,
    ubs.RankInLocation,
    haq.QuestionId,
    haq.Title AS QuestionTitle,
    haq.CreationDate AS QuestionCreationDate,
    haq.Score AS QuestionScore,
    haq.ViewCount AS QuestionViewCount,
    haq.TotalAnswerScore,
    haq.AnswerCount
FROM UserBadgeStats ubs
LEFT JOIN HighlyActiveQuestions haq ON haq.OwnerUserId = ubs.UserId
ORDER BY ubs.GoldBadges DESC, ubs.TotalPostScores DESC, haq.TotalAnswerScore DESC;