WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
        COUNT(CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) AS AnswersProvided,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p2.PostTypeId = 2 THEN p2.Score END) AS AvgAnswerScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) AS LastQuestionDate,
        MAX(CASE WHEN p2.PostTypeId = 2 THEN p2.CreationDate END) AS LastAnswerDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id AND p2.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
PopularQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        pl.RelatedPostId,
        v.VoteTypeId,
        COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.Tags, pl.RelatedPostId, v.VoteTypeId
    HAVING p.Score > 10 AND p.ViewCount > 1000
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnAnswers,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnAnswers,
        MAX(p.Score) AS TopAnswerScore
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastActivity,
        COUNT(ph.Id) AS RevisionCount,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,24)
    GROUP BY ph.PostId
)
SELECT
    uq.QuestionId,
    uq.Title,
    u.DisplayName AS QuestionOwner,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.QuestionsPosted,
    ub.AnswersProvided,
    ub.AvgQuestionScore,
    ub.AvgAnswerScore,
    ub.LastQuestionDate,
    ub.LastAnswerDate,
    uq.Score AS QuestionScore,
    uq.ViewCount AS QuestionViews,
    uq.AnswerCount,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.UpVotesOnAnswers,
    ans.DownVotesOnAnswers,
    ans.TopAnswerScore,
    uq.CommentCount AS QuestionComments,
    ra.LastActivity,
    ra.RevisionCount,
    ra.UniqueEditors,
    uq.Tags
FROM PopularQuestions uq
JOIN Users u ON u.Id = uq.OwnerUserId
LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
LEFT JOIN AnswerStats ans ON ans.QuestionId = uq.QuestionId
LEFT JOIN RecentActivity ra ON ra.PostId = uq.QuestionId
WHERE uq.QuestionId IN (
    SELECT QuestionId FROM AnswerStats WHERE TotalAnswers > 5
)
ORDER BY uq.Score DESC, ans.TopAnswerScore DESC, ra.LastActivity DESC
LIMIT 50;