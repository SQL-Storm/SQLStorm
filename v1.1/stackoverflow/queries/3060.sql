WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionsCount,
        COUNT(DISTINCT a.Id) AS AnswersCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS UpDownVotes,
        AVG((EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate))) / 86400.0) AS AvgDaysBetweenCreationAccess
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostHistoryCounts AS (
    SELECT 
        ph.PostId, 
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 6, 10, 13, 24, 37, 50, 52, 53, 66) THEN 1 ELSE 0 END) AS SignificantEditsCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 50 THEN ph.CreationDate ELSE NULL END) AS LastCommunityBump
    FROM PostHistory ph
    GROUP BY ph.PostId
),
ResolvedQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(phc.SignificantEditsCount, 0) AS EditsCount,
        phc.LastCommunityBump,
        p.OwnerUserId
    FROM Posts p
    LEFT JOIN PostHistoryCounts phc ON p.Id = phc.PostId
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        parent.Id AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreAnswers,
        SUM(CASE WHEN a.OwnerUserId IS NULL OR a.OwnerUserId = -1 THEN 1 ELSE 0 END) AS DeletedOrAnonymousAnswers
    FROM Posts parent
    LEFT JOIN Posts a ON a.ParentId = parent.Id AND a.PostTypeId = 2
    GROUP BY parent.Id
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS QuestionsWithTag,
        AVG(p.ViewCount) AS AvgViewsPerQuestion,
        MAX(p.ViewCount) AS MaxViews,
        SUM(CASE WHEN p.Score >= 5 THEN 1 ELSE 0 END) AS HighlyRatedQuestions
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
TopVotedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        v.UserId AS VoteUserId,
        ut.DisplayName AS VoterDisplayName,
        v.CreationDate AS VoteDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY v.CreationDate DESC) AS VoteRank
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Users ut ON ut.Id = v.UserId
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionsCount,
    u.AnswersCount,
    u.CommentsCount,
    u.BadgesCount,
    u.UpDownVotes,
    u.AvgDaysBetweenCreationAccess,
    req.QuestionId,
    req.Title,
    req.Tags,
    req.CreationDate AS QuestionCreated,
    req.ViewCount,
    req.Score,
    req.AnswerCount AS QuestionAnswers,
    req.CommentCount AS QuestionComments,
    req.EditsCount,
    req.LastCommunityBump,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.HighScoreAnswers,
    ans.DeletedOrAnonymousAnswers,
    tp.TagName,
    tp.QuestionsWithTag,
    tp.AvgViewsPerQuestion,
    tp.MaxViews,
    tp.HighlyRatedQuestions,
    tvp.Id AS TopVotedPostId,
    tvp.Title AS TopVoteTitle,
    tvp.Score AS TopVoteScore,
    tvp.VoteUserId,
    tvp.VoterDisplayName,
    tvp.VoteDate
FROM UserActivity u
INNER JOIN ResolvedQuestions req ON req.OwnerUserId = u.UserId
LEFT JOIN AnswerStats ans ON ans.QuestionId = req.QuestionId
LEFT JOIN TagPopularity tp ON tp.TagName = ANY(STRING_TO_ARRAY(SUBSTR(req.Tags, 2, LENGTH(req.Tags)-2), '><'))
LEFT JOIN LATERAL (
    SELECT p2.Id, p2.Title, p2.Score, p2.VoteUserId, p2.VoterDisplayName, p2.VoteDate
    FROM TopVotedPosts p2
    JOIN Posts p3 ON p3.Id = p2.Id
    WHERE p3.OwnerUserId = u.UserId AND p3.PostTypeId = 1
    ORDER BY p2.VoteDate DESC
    LIMIT 1
) tvp ON TRUE
WHERE u.Reputation > 1000
GROUP BY
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionsCount,
    u.AnswersCount,
    u.CommentsCount,
    u.BadgesCount,
    u.UpDownVotes,
    u.AvgDaysBetweenCreationAccess,
    req.QuestionId,
    req.Title,
    req.Tags,
    req.CreationDate,
    req.ViewCount,
    req.Score,
    req.AnswerCount,
    req.CommentCount,
    req.EditsCount,
    req.LastCommunityBump,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.HighScoreAnswers,
    ans.DeletedOrAnonymousAnswers,
    tp.TagName,
    tp.QuestionsWithTag,
    tp.AvgViewsPerQuestion,
    tp.MaxViews,
    tp.HighlyRatedQuestions,
    tvp.Id,
    tvp.Title,
    tvp.Score,
    tvp.VoteUserId,
    tvp.VoterDisplayName,
    tvp.VoteDate
ORDER BY u.Reputation DESC, req.CreationDate DESC
LIMIT 100;