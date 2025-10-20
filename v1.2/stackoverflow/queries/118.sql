WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        CAST(t.TagName AS VARCHAR(1000)) AS Path
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
        r.Path || ' > ' || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Count < r.Count AND r.Level < 3
    WHERE t2.IsModeratorOnly = false AND t2.IsRequired = false
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
        COALESCE(ubc_gold.BadgeCount,0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount,0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount,0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
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
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserTopQuestionRank
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
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS AnsweredByKnownUsers
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
),
QuestionVotes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
QuestionCommentsCount AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
),
QuestionDetails AS (
    SELECT
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerName,
        tq.Score,
        tq.ViewCount,
        tq.CreationDate,
        tq.Tags,
        tq.AcceptedAnswerId,
        COALESCE(ans.AnswerCount,0) AS AnswerCount,
        COALESCE(ans.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(ans.MaxAnswerScore,0) AS MaxAnswerScore,
        COALESCE(ans.AnsweredByKnownUsers,0) AS AnsweredByKnownUsers,
        COALESCE(qv.UpVotes,0) AS UpVotes,
        COALESCE(qv.DownVotes,0) AS DownVotes,
        COALESCE(qv.Favorites,0) AS Favorites,
        COALESCE(qc.CommentCount,0) AS CommentCount,
        qcr.CloseReasonName,
        qcr.CloseDate,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        ur.Reputation,
        ur.Location,
        ur.RepRank,
        ROW_NUMBER() OVER (PARTITION BY tq.OwnerUserId ORDER BY tq.Score DESC) AS QuestionRankByUser
    FROM TopQuestions tq
    LEFT JOIN AnswerStats ans ON ans.QuestionId = tq.Id
    LEFT JOIN QuestionVotes qv ON qv.PostId = tq.Id
    LEFT JOIN QuestionCommentsCount qc ON qc.PostId = tq.Id
    LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = tq.Id
    LEFT JOIN UserReputationStats ur ON ur.UserId = tq.OwnerUserId
),
AcceptedAnswerDetails AS (
    SELECT
        p.Id,
        p.ParentId AS QuestionId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        u.DisplayName AS AnswerOwnerName,
        u.Reputation AS AnswerOwnerReputation
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
),
FinalResults AS (
    SELECT
        qd.Id AS QuestionId,
        qd.Title,
        qd.OwnerUserId,
        qd.OwnerName,
        qd.Score AS QuestionScore,
        qd.ViewCount,
        qd.CreationDate,
        qd.Tags,
        qd.AnswerCount,
        qd.AvgAnswerScore,
        qd.MaxAnswerScore,
        qd.AnsweredByKnownUsers,
        qd.UpVotes,
        qd.DownVotes,
        qd.Favorites,
        qd.CommentCount,
        qd.CloseReasonName,
        qd.CloseDate,
        qd.GoldBadges,
        qd.SilverBadges,
        qd.BronzeBadges,
        qd.Reputation AS OwnerReputation,
        qd.Location,
        qd.RepRank,
        qd.QuestionRankByUser,
        a.AnswerScore AS AcceptedAnswerScore,
        a.AnswerCreationDate AS AcceptedAnswerCreationDate,
        a.AnswerOwnerName AS AcceptedAnswerOwnerName,
        a.AnswerOwnerReputation AS AcceptedAnswerOwnerReputation,
        (COALESCE(qd.Tags, 'NoTags') || ' | ' || COALESCE(qd.Location, 'UnknownLocation') || ' | ' || 'Badges(G/S/B): ' || CAST(qd.GoldBadges AS VARCHAR) || '/' || CAST(qd.SilverBadges AS VARCHAR) || '/' || CAST(qd.BronzeBadges AS VARCHAR)) AS TagLocationBadgeSummary,
        RANK() OVER (PARTITION BY qd.Location ORDER BY qd.Score DESC) AS LocationScoreRank,
        CASE
            WHEN qd.AcceptedAnswerId IS NULL AND qd.Score > 50 AND qd.AnswerCount > 5 THEN 1
            ELSE 0
        END AS HighScoreNoAcceptedAnswerFlag,
        (
            SELECT COUNT(DISTINCT p2.OwnerUserId)
            FROM Posts p2
            WHERE p2.PostTypeId = 2 AND p2.ParentId = qd.Id AND p2.OwnerUserId IS NOT NULL
        ) AS DistinctAnswerersCount,
        qd.AcceptedAnswerId,
        qd.Score AS QDScore
    FROM QuestionDetails qd
    LEFT JOIN AcceptedAnswerDetails a ON a.Id = qd.AcceptedAnswerId
    GROUP BY
        qd.Id,
        qd.Title,
        qd.OwnerUserId,
        qd.OwnerName,
        qd.Score,
        qd.ViewCount,
        qd.CreationDate,
        qd.Tags,
        qd.AnswerCount,
        qd.AvgAnswerScore,
        qd.MaxAnswerScore,
        qd.AnsweredByKnownUsers,
        qd.UpVotes,
        qd.DownVotes,
        qd.Favorites,
        qd.CommentCount,
        qd.CloseReasonName,
        qd.CloseDate,
        qd.GoldBadges,
        qd.SilverBadges,
        qd.BronzeBadges,
        qd.Reputation,
        qd.Location,
        qd.RepRank,
        qd.QuestionRankByUser,
        a.AnswerScore,
        a.AnswerCreationDate,
        a.AnswerOwnerName,
        a.AnswerOwnerReputation,
        qd.AcceptedAnswerId,
        qd.Score
)
SELECT
    fr.QuestionId,
    fr.Title,
    fr.OwnerName,
    fr.OwnerReputation,
    fr.Location,
    fr.QuestionScore,
    fr.ViewCount,
    fr.AnswerCount,
    fr.AvgAnswerScore,
    fr.MaxAnswerScore,
    fr.AnsweredByKnownUsers,
    fr.UpVotes,
    fr.DownVotes,
    fr.Favorites,
    fr.CommentCount,
    fr.CloseReasonName,
    fr.CloseDate,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.AcceptedAnswerScore,
    fr.AcceptedAnswerCreationDate,
    fr.AcceptedAnswerOwnerName,
    fr.AcceptedAnswerOwnerReputation,
    fr.TagLocationBadgeSummary,
    fr.LocationScoreRank,
    fr.HighScoreNoAcceptedAnswerFlag,
    fr.DistinctAnswerersCount
FROM FinalResults fr
WHERE fr.Location IS NOT NULL
ORDER BY fr.LocationScoreRank, fr.QuestionScore DESC
LIMIT 100;