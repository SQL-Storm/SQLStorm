WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.Id] AS Ancestors
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.Ancestors || t.Id
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON NOT (t.Id = ANY(r.Ancestors))
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(b.Class), 0) AS BadgeScore,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(b.Class), 0) DESC, u.Reputation DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS AnsweredByRegisteredUsers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        COUNT(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS PostsLast30Days,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS QuestionsLast30Days,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS AnswersLast30Days
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '90 days'
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3
),
ComplexUserSummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ua.PostsLast30Days, 0) AS PostsLast30Days,
        COALESCE(ua.QuestionsLast30Days, 0) AS QuestionsLast30Days,
        COALESCE(ua.AnswersLast30Days, 0) AS AnswersLast30Days,
        CASE
            WHEN u.Views IS NULL THEN 0
            ELSE u.Views
        END AS Views,
        CASE
            WHEN u.Location IS NULL OR LENGTH(TRIM(u.Location)) = 0 THEN 'Unknown'
            ELSE u.Location
        END AS Location,
        CASE
            WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE 'http%' THEN SUBSTRING(u.WebsiteUrl FROM 1 FOR 30)
            ELSE 'No Website'
        END AS WebsitePreview
    FROM Users u
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    LEFT JOIN (
        SELECT DISTINCT ON (UserId) UserId, PostsLast30Days, QuestionsLast30Days, AnswersLast30Days
        FROM UserActivityWindow
        ORDER BY UserId, PostId DESC
    ) ua ON ua.UserId = u.Id
)
SELECT
    tq.Id AS QuestionId,
    tq.Title,
    tq.OwnerUserId,
    tq.OwnerName,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    asn.AnswerCount,
    asn.AvgAnswerScore,
    asn.MaxAnswerScore,
    asn.AnsweredByRegisteredUsers,
    COALESCE(qcr.CloseReasonName, 'Open') AS CloseReason,
    COALESCE(qcr.CloseVotesCount, 0) AS CloseVotesCount,
    dupl.RelatedPostId AS DuplicateOfPostId,
    dupl.RelatedPostTitle AS DuplicateOfPostTitle,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.PostsLast30Days,
    cus.QuestionsLast30Days,
    cus.AnswersLast30Days,
    cus.Views,
    cus.Location,
    cus.WebsitePreview,
    ROW_NUMBER() OVER (PARTITION BY tq.OwnerUserId ORDER BY tq.Score DESC) AS UserTopQuestionRank,
    DENSE_RANK() OVER (ORDER BY tq.Score DESC) AS GlobalQuestionRank,
    CASE
        WHEN POSITION('<sql>' IN COALESCE(tq.Tags, '')) > 0 THEN 'Contains SQL Tag'
        ELSE 'No SQL Tag'
    END AS SqlTagPresence,
    LENGTH(COALESCE(tq.Title, '')) AS TitleLength,
    COALESCE(tq.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    CASE
        WHEN tq.AcceptedAnswerId IS NOT NULL THEN (
            SELECT p.Score FROM Posts p WHERE p.Id = tq.AcceptedAnswerId
        )
        ELSE NULL
    END AS AcceptedAnswerScore
FROM TopQuestions tq
LEFT JOIN AnswerStats asn ON asn.QuestionId = tq.Id
LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = tq.Id
LEFT JOIN DuplicateLinks dupl ON dupl.PostId = tq.Id
LEFT JOIN ComplexUserSummary cus ON cus.Id = tq.OwnerUserId
WHERE (COALESCE(asn.AnswerCount, 0) > 2 OR tq.Score > 10)
  AND (COALESCE(cus.GoldBadges, 0) + COALESCE(cus.SilverBadges, 0) + COALESCE(cus.BronzeBadges, 0)) > 0
ORDER BY GlobalQuestionRank
LIMIT 100;