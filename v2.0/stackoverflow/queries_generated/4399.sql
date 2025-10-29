-- {"query": "4399.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1619} 

WITH UserPostCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) AS BronzeBadges,
        MIN(b.Date) AS FirstBadgeDate
    FROM Badges AS b
    GROUP BY b.UserId
),
RecentUserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
        COALESCE(upc.TotalScore, 0) AS UserTotalScore,
        COALESCE(ubs.GoldBadges, 0) AS UserGoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS UserSilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS UserBronzeBadges,
        CASE
            WHEN u.LastAccessDate > DATE('now', '-30 day') THEN 'Active'
            WHEN u.LastAccessDate > DATE('now', '-90 day') THEN 'Moderately Active'
            ELSE 'Inactive'
        END AS ActivityLevel,
        upc.LatestPostDate,
        ubs.FirstBadgeDate,
        (strftime('%J', u.LastAccessDate) - strftime('%J', u.CreationDate)) AS DaysSinceCreation,
        (strftime('%J', DATE('now')) - strftime('%J', u.LastAccessDate)) AS DaysSinceLastAccess
    FROM Users AS u
    LEFT JOIN UserPostCounts AS upc ON u.Id = upc.OwnerUserId
    LEFT JOIN UserBadgeStats AS ubs ON u.Id = ubs.UserId
    WHERE u.Id > 0 -- Exclude community user
),
HighScoringQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.AnswerCount DESC) AS RankNum
    FROM Posts AS p
    WHERE p.PostTypeId = 1 AND p.Score > 100 AND p.AnswerCount > 5
),
TopUsersWithBadges AS (
    SELECT
        rua.Id,
        rua.DisplayName,
        rua.Reputation,
        rua.UserGoldBadges,
        rua.UserSilverBadges,
        rua.UserBronzeBadges,
        rua.ActivityLevel,
        rua.DaysSinceCreation,
        rua.DaysSinceLastAccess,
        CASE WHEN ubs.UserId IS NOT NULL THEN 'Has Badges' ELSE 'No Badges' END AS BadgeStatus
    FROM RecentUserActivity AS rua
    LEFT JOIN UserBadgeStats AS ubs ON rua.Id = ubs.UserId
    WHERE rua.Reputation > 10000
)
SELECT
    rua.DisplayName AS UserName,
    rua.Reputation,
    rua.TotalQuestions,
    rua.TotalAnswers,
    rua.UserTotalScore,
    rua.UserGoldBadges,
    rua.UserSilverBadges,
    rua.UserBronzeBadges,
    rua.ActivityLevel,
    rua.DaysSinceCreation,
    rua.DaysSinceLastAccess,
    CASE
        WHEN p1.Title IS NOT NULL AND p2.Title IS NOT NULL THEN SUBSTRING(p1.Title FROM 1 FOR 30) || '...' || SUBSTRING(p2.Title FROM 1 FOR 30)
        WHEN p1.Title IS NOT NULL THEN SUBSTRING(p1.Title FROM 1 FOR 60)
        ELSE 'No High Score Question'
    END AS RelatedHighScoringPosts,
    CASE
        WHEN pl.LinkTypeId = 1 THEN 'Linked'
        WHEN pl.LinkTypeId = 3 THEN 'Duplicate'
        ELSE 'Other Link Type'
    END AS LinkRelationship,
    CASE
        WHEN ph.PostHistoryTypeId IN (10, 12, 14) THEN 'Closed/Deleted/Locked'
        WHEN ph.PostHistoryTypeId IN (11, 13, 15) THEN 'Reopened/Undeleted/Unlocked'
        ELSE 'Other History Event'
    END AS RecentHistoryEventType,
    COALESCE(ua.CountOfComments, 0) AS CommentCountOnAnswers,
    CASE
        WHEN rua.UserGoldBadges > 0 AND rua.UserSilverBadges > 0 AND rua.UserBronzeBadges > 0 THEN 'All Tier Badges'
        WHEN rua.UserGoldBadges > 0 THEN 'Gold Badge Holder'
        WHEN rua.UserSilverBadges > 0 THEN 'Silver Badge Holder'
        WHEN rua.UserBronzeBadges > 0 THEN 'Bronze Badge Holder'
        ELSE 'No Notable Badges'
    END AS BadgeTierStatus
FROM RecentUserActivity AS rua
LEFT JOIN HighScoringQuestions AS hsq1 ON rua.Id = hsq1.OwnerUserId
LEFT JOIN HighScoringQuestions AS hsq2 ON hsq1.RankNum = hsq2.RankNum + 1 -- Correlated subquery logic within CTEs for comparison
LEFT JOIN Posts AS p1 ON hsq1.QuestionId = p1.Id
LEFT JOIN Posts AS p2 ON hsq2.QuestionId = p2.Id
LEFT JOIN PostLinks AS pl ON rua.Id = pl.PostId AND pl.CreationDate BETWEEN DATE('now', '-1 year') AND DATE('now')
LEFT JOIN PostHistory AS ph ON rua.Id = ph.UserId AND ph.CreationDate BETWEEN DATE('now', '-1 month') AND DATE('now')
LEFT JOIN (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CountOfComments
    FROM Comments AS c
    JOIN Posts AS p ON c.PostId = p.Id
    WHERE p.PostTypeId = 2 -- Answers
    GROUP BY c.UserId
) AS ua ON rua.Id = ua.UserId
WHERE rua.Reputation > 5000
ORDER BY rua.Reputation DESC, lua.DaysSinceLastAccess ASC;
