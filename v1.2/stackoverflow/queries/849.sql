WITH RECURSIVE RecursiveTagCounts AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate
    FROM
        Tags t
        LEFT JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%' AND p.PostTypeId = 1
    WHERE
        t.Count > 1000

    UNION ALL

    SELECT
        rtc.TagId,
        rtc.TagName,
        rtc.Count,
        p.Id,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate
    FROM
        RecursiveTagCounts rtc
        JOIN Posts p ON p.ParentId = rtc.PostId AND p.PostTypeId = 2
    WHERE
        p.Score > (
            SELECT AVG(Score)
            FROM Posts
            WHERE ParentId = rtc.PostId AND PostTypeId = 2
        )
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COALESCE(SUM(vtUp.VotesCount), 0) AS TotalUpVotes,
        COALESCE(SUM(vtDown.VotesCount), 0) AS TotalDownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN (
            SELECT PostId, COUNT(*) AS VotesCount
            FROM Votes
            WHERE VoteTypeId = 2
            GROUP BY PostId
        ) vtUp ON vtUp.PostId = COALESCE(p.Id, a.Id) OR vtUp.PostId = a.Id OR vtUp.PostId = p.Id
        LEFT JOIN (
            SELECT PostId, COUNT(*) AS VotesCount
            FROM Votes
            WHERE VoteTypeId = 3
            GROUP BY PostId
        ) vtDown ON vtDown.PostId = COALESCE(p.Id, a.Id) OR vtDown.PostId = a.Id OR vtDown.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostScoreStats AS (
    SELECT
        PostTypeId,
        AVG(Score) AS AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Score) AS MedianScore,
        MAX(Score) AS MaxScore,
        MIN(Score) AS MinScore
    FROM Posts
    WHERE PostTypeId IN (1, 2)
    GROUP BY PostTypeId
),
QuestionsWithCloseInfo AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.OwnerUserId,
        p.ClosedDate,
        crt.Name AS CloseReason,
        DENSE_RANK() OVER (PARTITION BY crt.Id ORDER BY p.CreationDate) AS CloseOrderInReason
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE p.PostTypeId = 1
),
TopBadges AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.Class = 1
)
SELECT
    qwi.Id AS QuestionId,
    qwi.Title,
    qwi.CreationDate,
    qwi.Score,
    qwi.ViewCount,
    qwi.AnswerCount,
    qwi.FavoriteCount,
    qwi.Tags,
    u.DisplayName AS OwnerName,
    u.Reputation AS OwnerRep,
    qwi.CloseReason,
    qwi.CloseOrderInReason,
    psq.AvgScore AS AvgQuestionScore,
    psa.AvgScore AS AvgAnswerScore,
    tb.Name AS LatestGoldBadge,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qwi.Id AND c.CreationDate > qwi.CreationDate) AS NewCommentsAfterQuestion,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qwi.Id AND v.VoteTypeId = 2 AND v.CreationDate > qwi.CreationDate) AS UpVotesAfterQuestion,
    ROW_NUMBER() OVER (PARTITION BY qwi.CloseReason ORDER BY qwi.ViewCount DESC) AS PopularityInCloseReason
FROM
    QuestionsWithCloseInfo qwi
    LEFT JOIN Users u ON u.Id = qwi.OwnerUserId
    LEFT JOIN PostScoreStats psq ON psq.PostTypeId = 1
    LEFT JOIN PostScoreStats psa ON psa.PostTypeId = 2
    LEFT JOIN TopBadges tb ON tb.UserId = u.Id AND tb.BadgeRank = 1
WHERE
    (qwi.CloseReason IS NOT NULL OR qwi.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1))
    AND qwi.AnswerCount > 0
    AND u.Reputation > 1000
ORDER BY
    qwi.CloseReason,
    qwi.ViewCount DESC
LIMIT 100;