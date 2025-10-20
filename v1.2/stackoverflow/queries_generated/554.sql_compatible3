WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        CAST(ARRAY[t.TagName] AS varchar[]) AS TagPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        rth.TagPath || t2.TagName,
        rth.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy rth ON t2.Id = rth.Id + 1
    WHERE rth.Level < 3
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
PostScoresWithWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS avg_score,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS total_posts
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON u.Id = ubc_gold.UserId AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON u.Id = ubc_silver.UserId AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON u.Id = ubc_bronze.UserId AND ubc_bronze.Class = 3
    WHERE u.Reputation > 1000
),
UserTopPosts AS (
    SELECT
        psww.Id,
        psww.OwnerUserId,
        psww.PostTypeId,
        psww.Score,
        psww.ViewCount,
        psww.CreationDate,
        psww.Tags,
        psww.rn,
        psww.avg_score,
        psww.total_posts,
        p.Title,
        p.AcceptedAnswerId,
        CASE
            WHEN psww.PostTypeId = 1 THEN 'Question'
            WHEN psww.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeName
    FROM PostScoresWithWindow psww
    JOIN Posts p ON psww.Id = p.Id
    WHERE psww.rn <= 5
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS MaxAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.Score > q.Score THEN 1 ELSE 0 END) AS AnswersBetterThanQuestion
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
ClosedQuestionsWithReasons AS (
    SELECT
        ph.PostId,
        cr.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes cr ON CAST(ph.Comment AS integer) = cr.Id
    WHERE ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo AS (
    SELECT
        q.Id,
        q.Title,
        q.Tags,
        cqwr.CloseReason,
        cqwr.CloseDate,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation
    FROM Posts q
    LEFT JOIN ClosedQuestionsWithReasons cqwr ON q.Id = cqwr.PostId
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
PostLinksSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS LinkedCount,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommented
    FROM Comments c
    GROUP BY c.UserId
),
FinalResult AS (
    SELECT
        tu.Id AS UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        utp.Id AS PostId,
        utp.PostTypeName,
        utp.Title,
        utp.Score AS PostScore,
        utp.ViewCount AS PostViews,
        utp.Tags,
        utp.avg_score AS UserAvgPostScore,
        pas.AnswerCount,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pas.AnswersBetterThanQuestion,
        qci.CloseReason,
        qci.CloseDate,
        pls.LinkedCount,
        pls.DuplicateCount,
        uca.CommentCount,
        uca.AvgCommentScore,
        uca.LastCommentDate,
        uca.DistinctPostsCommented,
        ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY utp.Score DESC) AS UserPostRank
    FROM TopUsers tu
    LEFT JOIN UserTopPosts utp ON tu.Id = utp.OwnerUserId
    LEFT JOIN PostAnswerStats pas ON utp.Id = pas.QuestionId
    LEFT JOIN QuestionsWithCloseInfo qci ON utp.Id = qci.Id
    LEFT JOIN PostLinksSummary pls ON utp.Id = pls.PostId
    LEFT JOIN UserCommentActivity uca ON uca.UserId = tu.Id
    WHERE utp.Id IS NOT NULL
)
SELECT *
FROM FinalResult
WHERE UserPostRank <= 3
ORDER BY Reputation DESC, UserPostRank, PostScore DESC;