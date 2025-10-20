WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || t2.Id
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON NOT (t2.Id = ANY (r.Path))
    WHERE t2.IsModeratorOnly = false AND t2.IsRequired = false AND r.Level < 3
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserReputationStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        row_number() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
    WHERE u.Reputation > 1000
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
        u.DisplayName AS OwnerName,
        dense_rank() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.Score > 10 AND p.ViewCount > 1000
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
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
        COUNT(*) AS CloseVotes
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
QuestionComments AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        SUM(CASE WHEN c.UserId IS NULL THEN 0 ELSE 1 END) AS CommentsByRegisteredUsers,
        string_agg(DISTINCT substring(c.Text FROM 1 FOR 20), ' | ') AS SampleComments
    FROM Comments c
    GROUP BY c.PostId
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS PostsLast30Days,
        sum(p.Score) OVER (PARTITION BY u.Id ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS ScoreLast30Days
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '90 days'
),
UserLinkStats AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        count(*) OVER (PARTITION BY pl.PostId) AS LinkCountPerPost
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
CombinedResults AS (
    SELECT
        tq.Id AS QuestionId,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerName,
        tq.Score,
        tq.ViewCount,
        tq.CreationDate,
        tq.Tags,
        asn.AnswerCount,
        asn.AvgAnswerScore,
        asn.MaxAnswerScore,
        asn.AnsweredByRegisteredUsers,
        qcr.CloseReasonName,
        qcr.CloseVotes,
        qc.CommentCount,
        qc.CommentsByRegisteredUsers,
        ua.PostsLast30Days,
        ua.ScoreLast30Days,
        ul.LinkTypeName,
        ul.LinkCountPerPost,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        ur.ReputationRank
    FROM TopQuestions tq
    LEFT JOIN AnswerStats asn ON asn.QuestionId = tq.Id
    LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = tq.Id
    LEFT JOIN QuestionComments qc ON qc.PostId = tq.Id
    LEFT JOIN UserActivityWindow ua ON ua.UserId = tq.OwnerUserId
    LEFT JOIN UserLinkStats ul ON ul.PostId = tq.Id
    LEFT JOIN UserReputationStats ur ON ur.UserId = tq.OwnerUserId
    WHERE (qcr.CloseVotes IS NULL OR qcr.CloseVotes < 5)
)
SELECT
    cr.QuestionId,
    cr.Title,
    cr.OwnerName,
    cr.Score,
    cr.ViewCount,
    cr.CreationDate,
    cr.Tags,
    COALESCE(cr.AnswerCount, 0) AS AnswerCount,
    COALESCE(cr.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(cr.MaxAnswerScore, 0) AS MaxAnswerScore,
    COALESCE(cr.AnsweredByRegisteredUsers, 0) AS AnsweredByRegisteredUsers,
    cr.CloseReasonName,
    COALESCE(cr.CloseVotes, 0) AS CloseVotes,
    COALESCE(cr.CommentCount, 0) AS CommentCount,
    COALESCE(cr.CommentsByRegisteredUsers, 0) AS CommentsByRegisteredUsers,
    cr.PostsLast30Days,
    cr.ScoreLast30Days,
    cr.LinkTypeName,
    cr.LinkCountPerPost,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.ReputationRank,
    length(cr.Title) AS TitleLength,
    CASE WHEN cr.ViewCount > 0 THEN round(CAST(cr.Score AS numeric) / cr.ViewCount, 4) ELSE NULL END AS ScoreToViewRatio,
    CASE WHEN cr.AnswerCount > 0 THEN round(CAST(cr.MaxAnswerScore AS numeric) / cr.AnswerCount, 4) ELSE NULL END AS MaxAnswerScorePerAnswer,
    CASE WHEN COALESCE(cr.CloseVotes, 0) > 0 THEN 'Closed' ELSE 'Open' END AS PostStatus,
    substring(cr.Tags FROM 2 FOR 100) AS SampleTags,
    COALESCE(ur.Location, 'Unknown') AS UserLocation,
    COALESCE(ur.DisplayName, 'Anonymous') AS UserDisplayName,
    COALESCE(ur.Reputation, 0) AS UserReputation
FROM CombinedResults cr
LEFT JOIN Users ur ON ur.Id = cr.OwnerUserId
WHERE cr.ReputationRank <= 100
ORDER BY cr.Score DESC, cr.ViewCount DESC, COALESCE(cr.AnswerCount, 0) DESC
LIMIT 50;