WITH RECURSIVE RecursiveTagCounts AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY_REMOVE(ARRAY_AGG(p.Id) FILTER (WHERE p.Id IS NOT NULL), NULL) AS PostIds
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.Id, t.TagName, t.Count
    UNION ALL
    SELECT
        rtc.Id,
        rtc.TagName,
        rtc.Count,
        pl.RelatedPostIdArray
    FROM RecursiveTagCounts rtc
    JOIN (
        -- expand one level of related posts per recursive step without using aggregates in the recursive term
        SELECT
            pl.PostId,
            ARRAY_AGG(pl.RelatedPostId) FILTER (WHERE pl.RelatedPostId IS NOT NULL) AS RelatedPostIdArray
        FROM PostLinks pl
        GROUP BY pl.PostId
    ) pl ON pl.PostId = ANY(rtc.PostIds)
    WHERE array_length(rtc.PostIds, 1) < 1000
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        AVG(p.Score) FILTER (WHERE p.OwnerUserId = u.Id AND p.Score IS NOT NULL) AS AvgPostScore,
        MAX(p.CreationDate) FILTER (WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.Score > 10 AND p.ViewCount > 1000
),
ClosedQuestions AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS ClosedDate,
        crt.Name AS CloseReason
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserBadges AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM Posts p
    JOIN Posts q ON q.Id = p.ParentId AND q.PostTypeId = 1
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
UserPostHistoryEdits AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.UserId, ph.PostId, ph.PostHistoryTypeId
)
SELECT
    u.UserId,
    u.DisplayName,
    u.QuestionsAsked,
    u.AnswersGiven,
    u.CommentsMade,
    COALESCE(ubGold.BadgeCount, 0) AS GoldBadges,
    COALESCE(ubSilver.BadgeCount, 0) AS SilverBadges,
    COALESCE(ubBronze.BadgeCount, 0) AS BronzeBadges,
    u.UpVotesReceived,
    u.DownVotesReceived,
    u.AvgPostScore,
    u.LastPostDate,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.ViewCount AS TopQuestionViews,
    cs.ClosedDate,
    cs.CloseReason,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.HasAcceptedAnswer,
    eh.EditCount AS TotalEditsMade,
    CASE
        WHEN u.AvgPostScore IS NULL THEN 'No posts'
        WHEN u.AvgPostScore > 10 THEN 'High quality'
        WHEN u.AvgPostScore BETWEEN 5 AND 10 THEN 'Medium quality'
        ELSE 'Low quality'
    END AS QualityLabel
FROM UserActivity u
LEFT JOIN TopQuestions tq ON tq.OwnerName = u.DisplayName AND tq.rn = 1
LEFT JOIN ClosedQuestions cs ON cs.PostId = tq.Id
LEFT JOIN AnswerStats ans ON ans.QuestionId = tq.Id
LEFT JOIN UserBadges ubGold ON ubGold.UserId = u.UserId AND ubGold.Class = 1
LEFT JOIN UserBadges ubSilver ON ubSilver.UserId = u.UserId AND ubSilver.Class = 2
LEFT JOIN UserBadges ubBronze ON ubBronze.UserId = u.UserId AND ubBronze.Class = 3
LEFT JOIN (
    SELECT UserId, SUM(EditCount) AS EditCount FROM UserPostHistoryEdits GROUP BY UserId
) eh ON eh.UserId = u.UserId
WHERE u.QuestionsAsked > 5
ORDER BY u.UpVotesReceived DESC NULLS LAST, u.QuestionsAsked DESC
LIMIT 100;