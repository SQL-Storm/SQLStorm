-- {"query": "2879.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1699} 

WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        COALESCE(SUM(vUp.VotesCount), 0) AS UpVotesReceived,
        COALESCE(SUM(vDown.VotesCount), 0) AS DownVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS RankByReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VotesCount
        FROM Votes
        WHERE VoteTypeId = 2 -- UpMod
        GROUP BY PostId
    ) vUp ON vUp.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VotesCount
        FROM Votes
        WHERE VoteTypeId = 3 -- DownMod
        GROUP BY PostId
    ) vDown ON vDown.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostCTE AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.Title,
        p.Tags,
        CONCAT_WS(' | ',
            COALESCE(p.Title, 'No Title'),
            COALESCE(p.Tags, '<empty>'),
            CAST(p.Score AS varchar),
            CAST(p.ViewCount AS varchar)
        ) AS TagScoreViewConcat
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
RankedPosts AS (
    SELECT 
        p.*,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS OldestRank
    FROM PostCTE p
),
QuestionsWithAcceptedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        a.Id AS AcceptedAnswerId,
        a.OwnerUserId AS AcceptedAnswerOwnerUserId,
        a.Score AS AcceptedAnswerScore,
        au.DisplayName AS AcceptedAnswerOwnerName,
        EXISTS (
            SELECT 1 FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2
        ) AS AcceptedAnswerHasUpvotes
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    WHERE q.PostTypeId = 1
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.LinkTypeId = 3 -- Duplicate
),
CloseVotesCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS NumCloseVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS NumReopenVotes,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.PostId
),
AggregatedComments AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentsCount,
        AVG(c.Score) AS AvgCommentScore,
        STRING_AGG(
            CASE 
                WHEN c.Text IS NOT NULL THEN 
                    LEFT(c.Text, 30) || CASE WHEN length(c.Text) > 30 THEN '...' ELSE '' END
                ELSE 'NULL'
            END, 
            ' || '
            ORDER BY c.CreationDate DESC
        ) AS RecentCommentsSnippet
    FROM Comments c
    GROUP BY c.PostId
),
EnhancedPosts AS (
    SELECT
        rp.Id,
        rp.PostTypeId,
        ru.DisplayName AS OwnerDisplayName,
        ru.Reputation AS OwnerReputation,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.Title,
        rp.Tags,
        rp.TagScoreViewConcat,
        dc.NumCloseVotes,
        dc.NumReopenVotes,
        dc.CloseReasonId,
        ac.CommentsCount,
        ac.AvgCommentScore,
        ac.RecentCommentsSnippet
    FROM RankedPosts rp
    LEFT JOIN Users ru ON rp.OwnerUserId = ru.Id
    LEFT JOIN CloseVotesCounts dc ON dc.PostId = rp.Id
    LEFT JOIN AggregatedComments ac ON ac.PostId = rp.Id
),
UserQuestionsAnswers AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS UserQuestions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS UserAnswers,
        AVG(p.Score) AS AvgPostScore,
        COUNT(*) AS TotalPostsUser
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ua.BadgeCount,
    COALESCE(uqa.UserQuestions, 0) AS UserQuestions,
    COALESCE(uqa.UserAnswers, 0) AS UserAnswers,
    COALESCE(uqa.AvgPostScore, 0) AS AvgPostScore,
    COALESCE(uqa.TotalPostsUser, 0) AS TotalPostsUser,
    psc.Id AS PopularQuestionId,
    psc.Title AS PopularQuestionTitle,
    psc.Score AS PopularQuestionScore,
    psc.ViewCount AS PopularQuestionViews,
    psc.Tags AS PopularQuestionTags,
    dq.PostId AS DuplicateQuestionId,
    dq.RelatedPostId AS DuplicateOfQuestionId,
    dq.LinkTypeName AS DuplicateLinkType,
    qwa.AcceptedAnswerId,
    qwa.AcceptedAnswerOwnerName,
    qwa.AcceptedAnswerScore,
    qwa.AcceptedAnswerHasUpvotes,
    ep.CommentsCount AS PostCommentsCount,
    ep.AvgCommentScore AS PostAvgCommentScore,
    ep.RecentCommentsSnippet AS CommentsSnippet
FROM RecursiveUserActivity ua
LEFT JOIN LATERAL (
    SELECT ep2.Id, ep2.Title, ep2.Score, ep2.ViewCount, ep2.Tags
    FROM EnhancedPosts ep2
    WHERE ep2.PostTypeId = 1 AND ep2.OwnerDisplayName = ua.DisplayName
    ORDER BY ep2.Score DESC, ep2.ViewCount DESC
    LIMIT 1
) psc ON true
LEFT JOIN DuplicateLinks dq ON dq.PostId = psc.Id
LEFT JOIN QuestionsWithAcceptedAnswers qwa ON qwa.QuestionId = psc.Id
LEFT JOIN EnhancedPosts ep ON ep.Id = psc.Id
LEFT JOIN UserQuestionsAnswers uqa ON uqa.OwnerUserId = ua.UserId
WHERE ua.Reputation > 1000
  AND ua.TotalPosts > 5
ORDER BY ua.Reputation DESC, ua.TotalPosts DESC, psc.Score DESC
LIMIT 100;
