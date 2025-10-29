-- {"query": "2076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1445} 
WITH RecursiveTagCounts AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(t.Count,0) AS TotalCount,
        COALESCE(p.ViewCount,0) AS PostViewCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC NULLS LAST) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.TagName IS NOT NULL
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS TotalPostScore,
        EXTRACT(EPOCH FROM (MAX(u.LastAccessDate) - MIN(u.CreationDate))) / 86400 AS ActiveDays,
        COALESCE(b.BadgeCount,0) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) DESC NULLS LAST) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        WHERE BadgeClass IN (1,2,3)
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, b.BadgeCount
),
TopUsersQuestions AS (
    SELECT
        u.UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY u.UserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS UserQuestionRank
    FROM UserActivity u
    JOIN Posts p ON p.OwnerUserId = u.UserId AND p.PostTypeId = 1
    WHERE u.UserRank <= 20
),
QuestionsWithAccepted AS (
    SELECT
        q.PostId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.CreationDate AS AcceptedAnswerCreation,
        a.OwnerUserId AS AcceptedAnswerUserId,
        u.DisplayName AS AcceptedAnswerUserName
    FROM TopUsersQuestions q
    LEFT JOIN Posts a ON a.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = q.PostId)
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.UserQuestionRank <= 3
),
CloseReasonSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(ph.Id) AS CloseVotesCount,
        MAX(cr.Name) AS LastCloseReason,
        MAX(ph.CreationDate) AS LastCloseDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr ON cr.Id::text = ph.Comment
    GROUP BY p.Id
),
CommentStats AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        STRING_AGG(c.Text, ' | ' ORDER BY c.CreationDate DESC) FILTER (WHERE c.Score IS NOT NULL AND c.Score > 5) AS HighScoreComments
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id
),
FinalStats AS (
    SELECT
        q.PostId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        q.AcceptedAnswerScore,
        q.AcceptedAnswerCreation,
        q.AcceptedAnswerUserId,
        q.AcceptedAnswerUserName,
        cr.CloseVotesCount,
        cr.LastCloseReason,
        cr.LastCloseDate,
        cs.CommentCount,
        cs.AvgCommentScore,
        cs.HighScoreComments
    FROM QuestionsWithAccepted q
    LEFT JOIN CloseReasonSummary cr ON cr.PostId = q.PostId
    LEFT JOIN CommentStats cs ON cs.PostId = q.PostId
),
RankedPosts AS (
    SELECT
        *,
        RANK() OVER (ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST) AS PostRank
    FROM FinalStats
)
SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.AcceptedAnswerId,
    rp.AcceptedAnswerScore,
    rp.AcceptedAnswerCreation,
    rp.AcceptedAnswerUserId,
    rp.AcceptedAnswerUserName,
    rp.CloseVotesCount,
    rp.LastCloseReason,
    rp.LastCloseDate,
    rp.CommentCount,
    rp.AvgCommentScore,
    LEFT(rp.HighScoreComments, 500) AS SnippetHighScoreComments,
    ROUND((rp.Score::NUMERIC / NULLIF(EXTRACT(EPOCH FROM NOW() - rp.CreationDate)/3600, 0)), 2) AS ScorePerHour,
    CASE
        WHEN rp.LastCloseDate IS NOT NULL AND rp.LastCloseDate > rp.CreationDate THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    CONCAT(
        'UserRank:', ua.UserRank, ', Questions:', ua.QuestionCount, ', Answers:', ua.AnswerCount, ', Badges:', ua.BadgeCount
    ) AS OwnerStats,
    STRING_AGG(DISTINCT lnk.Name, ', ') FILTER (WHERE lnk.Name IS NOT NULL) AS LinkTypes
FROM RankedPosts rp
JOIN UserActivity ua ON ua.UserId = rp.AcceptedAnswerUserId
LEFT JOIN (
    SELECT
        pl.PostId,
        lt.Name
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
) lnk ON lnk.PostId = rp.PostId
WHERE rp.PostRank <= 10
GROUP BY 
    rp.PostId, rp.Title, rp.Score, rp.ViewCount, rp.CreationDate, 
    rp.AcceptedAnswerId, rp.AcceptedAnswerScore, rp.AcceptedAnswerCreation, rp.AcceptedAnswerUserId, rp.AcceptedAnswerUserName,
    rp.CloseVotesCount, rp.LastCloseReason, rp.LastCloseDate,
    rp.CommentCount, rp.AvgCommentScore, rp.HighScoreComments, ua.UserRank, ua.QuestionCount, ua.AnswerCount, ua.BadgeCount
ORDER BY rp.Score DESC NULLS LAST, rp.ViewCount DESC NULLS LAST;