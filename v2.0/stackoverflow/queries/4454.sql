-- {"query": "4454.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 941}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN COALESCE(c.Score, 0) ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(u.Reputation) AS MaxReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
    HAVING SUM(CASE WHEN p.PostTypeId = 2 THEN COALESCE(c.Score, 0) ELSE 0 END) > 1000
),
HighImpactQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        ROW_NUMBER() OVER(ORDER BY p.Score DESC, p.AnswerCount DESC) AS qr
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 500 AND p.AnswerCount > 10
)
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    COUNT(DISTINCT rpe.PostId) AS PostsEdited,
    AVG(DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56') - u.CreationDate)) AS AvgDaysSinceCreation,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
    COALESCE(uc.QuestionCount, 0) AS UserQuestions,
    COALESCE(uc.AnswerCount, 0) AS UserAnswers,
    COALESCE(uc.TotalAnswerScore, 0) AS UserTotalAnswerScore,
    COALESCE(uc.BadgeCount, 0) AS UserBadges,
    CASE
        WHEN hiq.qr IS NOT NULL AND hiq.qr <= 10 THEN 'Top 10 Impactful'
        WHEN hiq.qr IS NOT NULL AND hiq.qr <= 50 THEN 'Top 50 Impactful'
        ELSE 'Other'
    END AS ImpactCategory
FROM Users u
LEFT JOIN RankedPostEdits rpe ON u.Id = rpe.UserId
LEFT JOIN UserContributions uc ON u.Id = uc.UserId
LEFT JOIN HighImpactQuestions hiq ON u.Id = hiq.OwnerUserId
WHERE u.Id IN (SELECT DISTINCT ph2.UserId FROM PostHistory ph2 WHERE ph2.PostHistoryTypeId IN (4, 5, 6))
GROUP BY
    u.Id,
    u.DisplayName,
    uc.QuestionCount,
    uc.AnswerCount,
    uc.TotalAnswerScore,
    uc.BadgeCount,
    hiq.qr
HAVING COUNT(DISTINCT rpe.PostId) > 5
ORDER BY
    SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) DESC,
    UserTotalAnswerScore DESC;