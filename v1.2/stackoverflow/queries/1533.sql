WITH RECURSIVE RecursiveActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, 1 AS Level
    FROM Users u
    WHERE u.Reputation >= 1500 AND u.Location IS NOT NULL
    UNION ALL
    SELECT u2.Id, u2.DisplayName, u2.Reputation, ra.Level + 1
    FROM Users u2
    JOIN RecursiveActiveUsers ra ON ra.Id = u2.Id - 1
    WHERE u2.Reputation >= 1500 AND u2.Location IS NOT NULL AND ra.Level < 5
),
UserBadgeStats AS (
    SELECT 
        b.UserId, 
        COUNT(*) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionAnswerRatio AS (
    SELECT 
        p.OwnerUserId,
        CASE 
            WHEN SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) = 0 THEN NULL
            ELSE CAST(SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS numeric)
                 / CAST(SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS numeric)
        END AS AnswerToQuestionRatio
    FROM Posts p
    INNER JOIN PostTypes pt ON pt.Id = p.PostTypeId
    WHERE p.OwnerUserId > 0 
    GROUP BY p.OwnerUserId
),
LatestUserSeenActivity AS (
    SELECT u.Id, u.DisplayName, MAX(p.LastActivityDate) AS LastUserActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentHighScoringQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.Score DESC) AS Rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 10 AND p.ClosedDate IS NULL
),
RecentCommentsOnHighScoreQ AS (
    SELECT 
        c.Id AS CommentId,
        c.PostId,
        c.Text,
        c.Score AS CommentScore,
        c.UserId AS CommentUserId,
        c.CreationDate AS CommentCreated,
        q.OwnerUserId AS QuestionOwnerId,
        qi.Score AS QuestionScore
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id 
    JOIN RecentHighScoringQuestions q ON q.Id = p.Id AND q.Rn <= 5
    JOIN Posts qi ON p.Id = qi.Id
)
SELECT 
    ru.Id AS UserId,
    ru.DisplayName,
    ru.Reputation,
    COALESCE(ubh.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubh.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubh.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubh.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(qar.AnswerToQuestionRatio, 0) AS AnswerQuestionRatio,
    ua.LastUserActivity,
    qc.Id AS RecentQuestionId,
    qc.Title AS RecentQuestionTitle,
    qc.Score AS RecentQuestionScore,
    rc.CommentId AS RecentCommentId,
    rc.Text AS RecentCommentText,
    rc.CommentScore AS RecentCommentScore,
    rc.CommentUserId AS RecentCommentUserId,
    rc.CommentCreated AS RecentCommentCreated,
    rc.QuestionOwnerId,
    rc.QuestionScore
FROM RecursiveActiveUsers ru
LEFT JOIN UserBadgeStats ubh ON ubh.UserId = ru.Id
LEFT JOIN QuestionAnswerRatio qar ON qar.OwnerUserId = ru.Id
LEFT JOIN LatestUserSeenActivity ua ON ua.Id = ru.Id
LEFT JOIN RecentHighScoringQuestions qc ON qc.OwnerUserId = ru.Id AND qc.Rn = 1
LEFT JOIN RecentCommentsOnHighScoreQ rc ON rc.QuestionOwnerId = ru.Id
GROUP BY
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ubh.TotalBadges,
    ubh.GoldBadges,
    ubh.SilverBadges,
    ubh.BronzeBadges,
    qar.AnswerToQuestionRatio,
    ua.LastUserActivity,
    qc.Id,
    qc.Title,
    qc.Score,
    rc.CommentId,
    rc.Text,
    rc.CommentScore,
    rc.CommentUserId,
    rc.CommentCreated,
    rc.QuestionOwnerId,
    rc.QuestionScore;