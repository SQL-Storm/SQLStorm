WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        parent.Level + 1
    FROM Tags child
    INNER JOIN RecursiveTagHierarchy parent ON child.Id = parent.Id + 1
    WHERE child.IsRequired = FALSE
),
UserBadgeRanks AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        RANK() OVER (
            ORDER BY 
                COUNT(CASE WHEN b.Class = 1 THEN 1 END) DESC,
                COUNT(CASE WHEN b.Class = 2 THEN 1 END) DESC,
                COUNT(CASE WHEN b.Class = 3 THEN 1 END) DESC
        ) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserTopQuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
      AND p.Score > 10
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS AnonymousAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        COUNT(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS PostsLast30Days,
        SUM(p.Score) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS ScoreLast30Days
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(DISTINCT c.PostId) AS UniquePostsCommented
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
QuestionAnswerDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerId,
        u.DisplayName AS AnswerOwnerName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),
QuestionsWithDuplicates AS (
    SELECT DISTINCT
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.Tags,
        dl.RelatedPostId AS DuplicateOf
    FROM Posts q
    LEFT JOIN DuplicateLinks dl ON q.Id = dl.PostId
    WHERE q.PostTypeId = 1
),
FinalSelection AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.Tags,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(qcr.CloseReason, 'Open') AS CloseReason,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.PostsLast30Days,
        ua.ScoreLast30Days,
        ucs.TotalComments,
        ucs.AvgCommentLength,
        ucs.UniquePostsCommented,
        dq.DuplicateOf,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN COALESCE(a.AnswerCount, 0) > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END AS AnswerStatus,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS GlobalRank
    FROM Posts q
    LEFT JOIN AnswerStats a ON q.Id = a.QuestionId
    LEFT JOIN QuestionCloseReasons qcr ON q.Id = qcr.PostId
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN UserBadgeRanks ub ON u.Id = ub.UserId
    LEFT JOIN UserActivityWindow ua ON u.Id = ua.UserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN QuestionsWithDuplicates dq ON q.Id = dq.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
)
SELECT
    fs.QuestionId,
    fs.Title,
    fs.Score,
    fs.ViewCount,
    fs.Tags,
    fs.AnswerCount,
    ROUND(CAST(fs.AvgAnswerScore AS numeric), 2) AS AvgAnswerScore,
    fs.CloseReason,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.PostsLast30Days,
    fs.ScoreLast30Days,
    fs.TotalComments,
    ROUND(CAST(fs.AvgCommentLength AS numeric), 1) AS AvgCommentLength,
    fs.UniquePostsCommented,
    fs.DuplicateOf,
    fs.AnswerStatus,
    fs.GlobalRank,
    CONCAT(
        'User ', COALESCE(u.DisplayName, 'Anonymous'),
        ' has ', COALESCE(CAST(fs.GoldBadges AS VARCHAR), '0'), ' gold, ',
        COALESCE(CAST(fs.SilverBadges AS VARCHAR), '0'), ' silver, and ',
        COALESCE(CAST(fs.BronzeBadges AS VARCHAR), '0'), ' bronze badges.'
    ) AS UserBadgeSummary,
    CASE 
        WHEN fs.CloseReason <> 'Open' THEN CONCAT('Closed due to: ', fs.CloseReason)
        ELSE 'Open question'
    END AS CloseStatus,
    CASE 
        WHEN fs.DuplicateOf IS NOT NULL THEN CONCAT('Duplicate of question ID ', fs.DuplicateOf)
        ELSE 'Not marked as duplicate'
    END AS DuplicateStatus
FROM FinalSelection fs
LEFT JOIN Users u ON fs.QuestionId = u.Id
WHERE fs.AnswerCount >= 2
  AND (COALESCE(fs.GoldBadges, 0) + COALESCE(fs.SilverBadges, 0) + COALESCE(fs.BronzeBadges, 0)) > 0
ORDER BY fs.GlobalRank
LIMIT 100;