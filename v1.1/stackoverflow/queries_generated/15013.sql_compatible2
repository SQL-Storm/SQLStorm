WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        AVG(u.Reputation) OVER (PARTITION BY b.Class) AS AvgReputationByBadgeClass,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank,
        b.Class
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, b.Class, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.Tags,
        p.CreationDate,
        COALESCE(p.AnswerCount, 0) AS Answers,
        v.VoteCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PopularityRank
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount 
        FROM Votes 
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.BadgeCount,
    ubs.AvgReputationByBadgeClass,
    tq.Id AS TopQuestionId,
    tq.Title AS TopQuestionTitle,
    tq.Score AS QuestionScore,
    tq.Answers,
    tq.VoteCount,
    CASE 
        WHEN tq.Answers > 5 THEN 'High Activity'
        WHEN tq.Answers BETWEEN 1 AND 5 THEN 'Moderate Activity'
        ELSE 'Low Activity'
    END AS QuestionActivityLevel,
    EXTRACT(YEAR FROM tq.CreationDate) AS QuestionYear,
    ROUND(tq.Score * 1.5 + ubs.BadgeCount * 0.5, 2) AS CompositeRank
FROM UserBadgeStats ubs
JOIN TopQuestions tq ON ubs.UserId = tq.PopularityRank
WHERE 
    ubs.BadgeRank <= 100 
    AND tq.Score > 10 
    AND LENGTH(tq.Tags) > 5
    AND tq.CreationDate > DATE '2010-01-01'
ORDER BY CompositeRank DESC
LIMIT 50;