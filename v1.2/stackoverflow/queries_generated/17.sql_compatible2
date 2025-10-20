WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        ARRAY[t.Id] AS Path
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.IsRequired = TRUE AND NOT t2.Id = ANY(r.Path)
    WHERE r.Level < 3
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
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON u.Id = ubc_gold.UserId AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON u.Id = ubc_silver.UserId AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON u.Id = ubc_bronze.UserId AND ubc_bronze.Class = 3
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
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
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
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
),
QuestionComments AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        SUM(CASE WHEN c.UserId IS NULL THEN 0 ELSE 1 END) AS CommentsByRegisteredUsers,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters
    FROM Comments c
    GROUP BY c.PostId
),
QuestionLinkDuplicates AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN lt.Name = 'Duplicate' THEN 1 END) AS DuplicateCount,
        COUNT(CASE WHEN lt.Name = 'Linked' THEN 1 END) AS LinkedCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
QuestionAggregates AS (
    SELECT
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.Tags,
        q.AcceptedAnswerId,
        q.OwnerName,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(a.AnsweredByRegisteredUsers, 0) AS AnsweredByRegisteredUsers,
        COALESCE(qcr.CloseReason, 'Open') AS CloseReason,
        qcr.CloseDate AS CloseDate,
        COALESCE(qc.CommentCount, 0) AS CommentCount,
        COALESCE(qc.CommentsByRegisteredUsers, 0) AS CommentsByRegisteredUsers,
        qc.Commenters,
        COALESCE(ql.DuplicateCount, 0) AS DuplicateCount,
        COALESCE(ql.LinkedCount, 0) AS LinkedCount
    FROM TopQuestions q
    LEFT JOIN AnswerStats a ON q.Id = a.QuestionId
    LEFT JOIN QuestionCloseReasons qcr ON q.Id = qcr.PostId
    LEFT JOIN QuestionComments qc ON q.Id = qc.PostId
    LEFT JOIN QuestionLinkDuplicates ql ON q.Id = ql.PostId
),
RankedQuestions AS (
    SELECT
        qa.Id,
        qa.Title,
        qa.OwnerUserId,
        qa.Score,
        qa.ViewCount,
        qa.CreationDate,
        qa.Tags,
        qa.AcceptedAnswerId,
        qa.OwnerName,
        qa.AnswerCount,
        qa.AvgAnswerScore,
        qa.MaxAnswerScore,
        qa.AnsweredByRegisteredUsers,
        qa.CloseReason,
        qa.CloseDate,
        qa.CommentCount,
        qa.CommentsByRegisteredUsers,
        qa.Commenters,
        qa.DuplicateCount,
        qa.LinkedCount,
        ROW_NUMBER() OVER (PARTITION BY qa.CloseReason ORDER BY qa.Score DESC, qa.ViewCount DESC) AS RankByCloseReason,
        ROW_NUMBER() OVER (ORDER BY qa.Score DESC, qa.ViewCount DESC) AS OverallRank
    FROM QuestionAggregates qa
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesGiven,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN UserBadgeCounts ubc_gold ON u.Id = ubc_gold.UserId AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON u.Id = ubc_silver.UserId AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON u.Id = ubc_bronze.UserId AND ubc_bronze.Class = 3
    GROUP BY u.Id, u.DisplayName, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
UserTopActivity AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.QuestionsPosted,
        uas.AnswersPosted,
        uas.CommentsMade,
        uas.UpVotesGiven,
        uas.DownVotesGiven,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        RANK() OVER (ORDER BY uas.QuestionsPosted DESC, uas.AnswersPosted DESC, uas.CommentsMade DESC) AS ActivityRank
    FROM UserActivitySummary uas
)
SELECT
    rq.OverallRank,
    rq.Id AS QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.OwnerName,
    rq.Score,
    rq.ViewCount,
    rq.CreationDate,
    rq.Tags,
    rq.AcceptedAnswerId,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.AnsweredByRegisteredUsers,
    rq.CloseReason,
    rq.CloseDate,
    rq.CommentCount,
    rq.CommentsByRegisteredUsers,
    rq.Commenters,
    rq.DuplicateCount,
    rq.LinkedCount,
    urs.ReputationRank,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    uas.QuestionsPosted,
    uas.AnswersPosted,
    uas.CommentsMade,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.GoldBadges AS UserGoldBadges,
    uas.SilverBadges AS UserSilverBadges,
    uas.BronzeBadges AS UserBronzeBadges,
    uas.ActivityRank,
    CONCAT(
        'Tags: ', COALESCE(rq.Tags, 'None'), ' | ',
        'Commenters: ', COALESCE(rq.Commenters, 'No comments'), ' | ',
        'Close Reason: ', rq.CloseReason, ' | ',
        'User Location: ', COALESCE(urs.Location, 'Unknown')
    ) AS SummaryInfo
FROM RankedQuestions rq
LEFT JOIN UserReputationStats urs ON rq.OwnerUserId = urs.UserId
LEFT JOIN UserTopActivity uas ON rq.OwnerUserId = uas.UserId
WHERE rq.OverallRank <= 100
ORDER BY rq.OverallRank;