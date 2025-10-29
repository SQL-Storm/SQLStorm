WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreated,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        COALESCE(a.AvgAnswerScore, 0.0) AS AvgAnswerScore,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserRecentQuestionRank
    FROM Posts q
    LEFT JOIN (
        SELECT
            p.ParentId,
            COUNT(*) AS AnswerCount,
            AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AvgAnswerScore
        FROM Posts p
        WHERE p.PostTypeId = 2
        GROUP BY p.ParentId
    ) a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
),
RecentCloseVotes AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastCloseVoteDate,
        MAX(CAST(ph.Comment AS INTEGER)) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY ph.PostId
),
UserActivityWindows AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) OVER w AS QuestionsPosted,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) OVER w AS AnswersPosted,
        SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) OVER w AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) OVER w AS AvgPostScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS LatestPostRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WINDOW w AS (PARTITION BY u.Id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
),
TopTags AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
),
QuestionsWithTagStats AS (
    SELECT
        q.Id,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotesCount,
        COALESCE(rcv.LastCloseVoteDate, NULL) AS LastCloseVoteDate,
        COALESCE(rcv.CloseReasonId, NULL) AS LastCloseReasonId,
        (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = q.Id) AS CommentCount,
        STRING_AGG(DISTINCT u.DisplayName || '|' || COALESCE(CAST(u.Reputation AS VARCHAR), ''), ', ') AS RecentCommentersWithRep
    FROM Posts q
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id
    LEFT JOIN RecentCloseVotes rcv ON rcv.PostId = q.Id
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Users u ON u.Id = c.UserId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.Score, q.ViewCount, rcv.LastCloseVoteDate, rcv.CloseReasonId
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN PostTypes pt ON pt.Id = (
        CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE pl.LinkTypeId END
    )
    WHERE pl.LinkTypeId = 3 -- duplicate links only
),
UserReputationChange AS (
    SELECT
        v.UserId,
        DATE_TRUNC('month', v.CreationDate) AS Month,
        SUM(CASE 
            WHEN vt.Name = 'UpMod' THEN 10
            WHEN vt.Name = 'DownMod' THEN -2
            WHEN vt.Name = 'AcceptedByOriginator' THEN 15
            ELSE 0
        END) AS MonthlyReputationChange
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId, DATE_TRUNC('month', v.CreationDate)
),
TopUsersByRepChange AS (
    SELECT
        urc.UserId,
        u.DisplayName,
        SUM(urc.MonthlyReputationChange) AS TotalReputationChange
    FROM UserReputationChange urc
    JOIN Users u ON u.Id = urc.UserId
    GROUP BY urc.UserId, u.DisplayName
    HAVING SUM(urc.MonthlyReputationChange) > 1000
)
SELECT
    qas.OwnerUserId AS UserId,
    ubc.DisplayName AS UserName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    qas.QuestionId,
    qas.Title AS QuestionTitle,
    qas.QuestionScore,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.HasAcceptedAnswer,
    qas.UserRecentQuestionRank,
    qts.TagName AS TopTag,
    qws.CloseVotesCount,
    qws.LastCloseVoteDate,
    qws.LastCloseReasonId,
    COALESCE(qws.CommentCount, 0) AS QuestionCommentCount,
    NULLIF(STRING_AGG(DISTINCT LEFT(rc.RecentCommentersWithRep, POSITION('|' IN rc.RecentCommentersWithRep)-1), ', '), '') AS RecentCommenters,
    tu.TotalReputationChange,
    COALESCE(urc.MonthlyReputationChange, 0) AS LatestMonthlyRepChange,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.TotalPostScore,
    ua.AvgPostScore
FROM QuestionAnswerStats qas
JOIN UserBadgeCounts ubc ON ubc.UserId = qas.OwnerUserId
JOIN QuestionsWithTagStats qws ON qws.Id = qas.QuestionId
LEFT JOIN (
    SELECT
        t.TagName,
        t.Count
    FROM Tags t
    WHERE t.Count > 10000
    ORDER BY t.Count DESC
    LIMIT 1
) qts ON POSITION('<' || qts.TagName || '>' IN qws.Tags) > 0
LEFT JOIN TopUsersByRepChange tu ON tu.UserId = qas.OwnerUserId
LEFT JOIN UserReputationChange urc ON urc.UserId = qas.OwnerUserId
    AND urc.Month = (SELECT MAX(Month) FROM UserReputationChange WHERE UserId = qas.OwnerUserId)
LEFT JOIN UserActivityWindows ua ON ua.UserId = qas.OwnerUserId
LEFT JOIN (
    SELECT Id, RecentCommentersWithRep
    FROM QuestionsWithTagStats
) rc ON rc.Id = qas.QuestionId
WHERE qas.QuestionScore > 5
  AND (qws.CloseVotesCount IS NULL OR qws.CloseVotesCount < 3)
GROUP BY
    qas.OwnerUserId,
    ubc.DisplayName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    qas.QuestionId,
    qas.Title,
    qas.QuestionScore,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.HasAcceptedAnswer,
    qas.UserRecentQuestionRank,
    qts.TagName,
    qws.CloseVotesCount,
    qws.LastCloseVoteDate,
    qws.LastCloseReasonId,
    qws.CommentCount,
    rc.RecentCommentersWithRep,
    tu.TotalReputationChange,
    urc.MonthlyReputationChange,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.TotalPostScore,
    ua.AvgPostScore
ORDER BY ubc.GoldBadges DESC, qas.QuestionScore DESC, qas.AnswerCount DESC
LIMIT 100;