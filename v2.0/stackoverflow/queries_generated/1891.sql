-- {"query": "1891.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2871} 

WITH UserPostStats AS (
    -- CTE 1: Aggregate statistics for users related to their posts and answers
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersGiven,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0) AS AveragePostScore, -- Using COALESCE for NULL logic on average
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN pa.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount, -- Counting how many of THEIR answers were accepted
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(p.LastActivityDate) AS LastUserActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts pa ON u.Id = pa.OwnerUserId AND pa.PostTypeId = 1 -- To count accepted answers by this user
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
PostHistorySnapshots AS (
    -- CTE 2: Analyze post history for edits, closures, and state changes, using window functions
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EventDate,
        ph.UserId AS HistoryUserId,
        ph.Comment,
        ph.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS rn_asc,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_desc,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate,
        LEAD(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextEventDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (
        1,  -- Initial Title
        2,  -- Initial Body
        5,  -- Edit Body
        6,  -- Edit Tags
        10, -- Post Closed
        11, -- Post Reopened
        12, -- Post Deleted
        13  -- Post Undeleted
    )
),
PostLifecycleSummary AS (
    -- CTE 3: Summarize post lifecycle events from PostHistorySnapshots
    SELECT
        phs.PostId,
        MIN(phs.EventDate) FILTER (WHERE phs.PostHistoryTypeId IN (1,2)) AS InitialCreationDate,
        MAX(phs.EventDate) FILTER (WHERE phs.PostHistoryTypeId IN (5,6)) AS LastEditDateByAnyone,
        COUNT(DISTINCT CASE WHEN phs.PostHistoryTypeId IN (5,6) THEN phs.EventDate END) AS EditCount,
        SUM(CASE WHEN phs.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedEventCount,
        SUM(CASE WHEN phs.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedEventCount,
        SUM(CASE WHEN phs.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeletedEventCount,
        SUM(CASE WHEN phs.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeletedEventCount,
        MAX(phs.EventDate) FILTER (WHERE phs.PostHistoryTypeId = 10) AS LastClosedDate,
        MAX(phs.EventDate) FILTER (WHERE phs.PostHistoryTypeId = 11) AS LastReopenedDate,
        MAX(phs.EventDate) FILTER (WHERE phs.PostHistoryTypeId = 12) AS LastDeletedDate,
        MAX(phs.EventDate) FILTER (WHERE phs.PostHistoryTypeId = 13) AS LastUndeletedDate,
        MAX(phs.EventDate) AS MostRecentHistoryEvent
    FROM PostHistorySnapshots phs
    GROUP BY phs.PostId
),
QuestionTagAnalysis AS (
    -- CTE 4: Analyze tags for questions, using string expressions and unnesting arrays
    SELECT
        p.Id AS PostId,
        TRIM(REPLACE(REPLACE(LOWER(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))), '-', '_'), '.', '')) AS CleanTagName,
        p.Score,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
AggregatedTagMetrics AS (
    -- CTE 5: Aggregate metrics per clean tag name, using a window function for ranking
    SELECT
        qta.CleanTagName,
        COUNT(DISTINCT qta.PostId) AS TaggedQuestionCount,
        AVG(qta.Score) AS AvgScoreForTag,
        AVG(qta.ViewCount) AS AvgViewCountForTag,
        RANK() OVER (ORDER BY COUNT(DISTINCT qta.PostId) DESC, AVG(qta.Score) DESC) AS TagPopularityRank
    FROM QuestionTagAnalysis qta
    GROUP BY qta.CleanTagName
),
CriticalPosts AS (
    -- CTE 6: Identify "critical" posts using a set operator (UNION ALL)
    SELECT p.Id AS PostId, 'HighScoreQuestion' AS CriticalReason
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score >= (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND Score IS NOT NULL) * 2 -- Correlated subquery for average
    UNION ALL
    SELECT p.Id AS PostId, 'AcceptedAnswer' AS CriticalReason
    FROM Posts p
    WHERE p.PostTypeId = 2 AND EXISTS (
        SELECT 1 FROM Posts q WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId = p.Id
    )
)
SELECT
    u.Id AS UserIdentifier,
    COALESCE(u.DisplayName, 'Anon-' || u.Id::varchar) AS UserName, -- NULL logic, string expression
    u.Reputation,
    u.Location,
    us.TotalPostsOwned,
    us.TotalQuestionsAsked,
    us.TotalAnswersGiven,
    us.TotalPostScore,
    us.AveragePostScore,
    us.AcceptedAnswersCount,
    us.TotalCommentsMade,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (5,6) AND ph.CreationDate > u.CreationDate) AS UserMadeEditsOnPosts, -- Correlated subquery
    p.Id AS PostId,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.Title,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount,
    p.CommentCount AS PostCommentCount,
    ROUND(CAST(p.AnswerCount AS NUMERIC) / NULLIF(p.ViewCount, 0), 2) AS AnswerToViewRatio, -- Complicated calculation with NULLIF
    pls.InitialCreationDate AS PostCreationDate,
    pls.LastEditDateByAnyone,
    (EXTRACT(EPOCH FROM (p.LastActivityDate - pls.InitialCreationDate)) / (60*60*24))::int AS DaysSinceCreationToLastActivity, -- Complicated calculation
    pls.EditCount AS PostEditCount,
    CASE -- Complicated predicate/NULL logic
        WHEN pls.ClosedEventCount > 0 AND (pls.LastReopenedDate IS NULL OR pls.LastClosedDate > pls.LastReopenedDate) THEN 'Closed'
        WHEN pls.ReopenedEventCount > 0 AND (pls.LastClosedDate IS NULL OR pls.LastReopenedDate > pls.LastClosedDate) THEN 'Reopened'
        WHEN pls.DeletedEventCount > 0 AND (pls.LastUndeletedDate IS NULL OR pls.LastDeletedDate > pls.LastUndeletedDate) THEN 'Deleted'
        WHEN pls.UndeletedEventCount > 0 AND (pls.LastDeletedDate IS NULL OR pls.LastUndeletedDate > pls.LastDeletedDate) THEN 'Undeleted'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
        ELSE 'Active'
    END AS PostLifecycleStatus,
    COALESCE(pl.LinkTypeId, -1) AS RelatedLinkType, -- NULL logic
    lt.Name AS RelatedLinkTypeName,
    p.FavoriteCount,
    atm.CleanTagName AS TopTagAssociated,
    atm.TaggedQuestionCount AS TopTagUsage,
    atm.AvgScoreForTag AS TopTagAvgScore,
    atm.TagPopularityRank AS TopTagRank,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS TotalUpvotesOnUserPosts, -- Window function
    COALESCE(AVG(CASE WHEN v.VoteTypeId = 3 THEN 1.0 ELSE 0.0 END) OVER (PARTITION BY p.Id), 0.0) AS DownvoteRatioOnPost, -- Window function
    (SELECT COALESCE(AVG(c_sub.Score), 0) FROM Comments c_sub WHERE c_sub.PostId = p.Id AND c_sub.CreationDate > pls.InitialCreationDate) AS AvgCommentScoreOnPost, -- Correlated subquery
    CASE WHEN cp.PostId IS NOT NULL THEN TRUE ELSE FALSE END AS IsCriticalPost,
    cp.CriticalReason
FROM Users u
LEFT JOIN UserPostStats us ON u.Id = us.UserId
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) b ON u.Id = b.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN PostLifecycleSummary pls ON p.Id = pls.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId -- Outer join
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN QuestionTagAnalysis qta ON p.Id = qta.PostId AND p.PostTypeId = 1 -- Only join for questions with tags
LEFT JOIN AggregatedTagMetrics atm ON qta.CleanTagName = atm.CleanTagName
LEFT JOIN Votes v ON p.Id = v.PostId -- Outer join to include posts without votes
LEFT JOIN CriticalPosts cp ON p.Id = cp.PostId
WHERE
    u.Reputation >= 1000 -- Complicated predicate
    AND u.Location IS NOT NULL AND u.Location ILIKE '%usa%' -- String expression, NULL logic
    AND (p.Score >= 5 OR p.ViewCount >= 100) -- Complicated predicate
    AND (p.AcceptedAnswerId IS NOT NULL OR p.AnswerCount > 0 OR p.CommentCount > 0) -- NULL logic, predicate
    AND p.CreationDate IS NOT NULL
    AND p.CreationDate > '2020-01-01'
    AND EXISTS ( -- Correlated subquery for user post content
        SELECT 1
        FROM Posts p_sub
        WHERE p_sub.OwnerUserId = u.Id
          AND (p_sub.Title ILIKE '%sql%' OR p_sub.Title ILIKE '%database%'
               OR p_sub.Tags ILIKE '%<sql>%' OR p_sub.Tags ILIKE '%<database>%')
    )
ORDER BY
    u.Reputation DESC,
    us.TotalPostsOwned DESC,
    p.CreationDate DESC,
    p.Score DESC
LIMIT 5000;
