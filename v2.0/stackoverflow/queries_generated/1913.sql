-- {"query": "1913.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2987} 

WITH BaseQuestions AS (
    -- Select foundational questions based on popularity, activity, and recency.
    -- Calculates approximate age in years using date arithmetic.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS QuestionOwnerId,
        p.CreationDate AS QuestionCreationDate,
        p.Title AS QuestionTitle,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.ClosedDate,
        p.LastActivityDate,
        p.Tags,
        EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / (365.25 * 24 * 60 * 60) AS QuestionAgeYears, -- Complex date calculation
        p.AcceptedAnswerId,
        p.OwnerDisplayName
    FROM Posts p
    WHERE
        p.PostTypeId = 1
        AND p.ViewCount > 5000       -- Filter for highly viewed questions
        AND p.Score > 50             -- Filter for highly scored questions
        AND p.AnswerCount > 0        -- Ensure questions have at least one answer
        AND p.CreationDate >= '2015-01-01' -- Limit data range for performance and relevance
        AND p.Tags IS NOT NULL       -- Exclude questions without tags
),
QuestionHistoryDetails AS (
    -- Summarize post history events for each question, including edit, close, and reopen statistics.
    -- Uses window functions to identify the last user performing a history action and the last close reason.
    SELECT
        bq.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) AS UniqueHistoryContributors,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditRevisionCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 'TRUE' ELSE 'FALSE' END) AS WasEverClosedFlag, -- NULL logic using string 'TRUE'/'FALSE'
        MAX(ph.CreationDate) AS LatestHistoryActionDate,
        MIN(ph.CreationDate) AS EarliestHistoryActionDate,
        FIRST_VALUE(ph.UserId) OVER (PARTITION BY bq.PostId ORDER BY ph.CreationDate DESC) AS LastHistoryActionUserId, -- Window function
        FIRST_VALUE(COALESCE(crt.Name, ph.Comment)) OVER (PARTITION BY bq.PostId ORDER BY ph.CreationDate DESC) AS LastCloseReasonDetail -- NULL logic (COALESCE) + Window function
    FROM BaseQuestions bq
    JOIN PostHistory ph ON bq.PostId = ph.PostId
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment = crt.Id::text -- Conditional join for close reasons
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11) -- Relevant history types for analysis
    GROUP BY bq.PostId
),
QuestionVotesAndComments AS (
    -- Aggregates upvotes, downvotes, and comment statistics for each question.
    -- Calculates average comment score, handling potential NULLs.
    SELECT
        bq.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS AverageCommentScore, -- Conditional aggregation
        MAX(c.CreationDate) AS LastCommentDate,
        MIN(c.CreationDate) AS FirstCommentDate
    FROM BaseQuestions bq
    LEFT JOIN Votes v ON bq.PostId = v.PostId AND v.VoteTypeId IN (2, 3) -- Only consider up/down votes
    LEFT JOIN Comments c ON bq.PostId = c.PostId
    GROUP BY bq.PostId
),
AnswerAndAcceptanceMetrics AS (
    -- Analyzes answers to each question, including total scores, average scores, and identifies the top answerer.
    -- Uses a correlated subquery to check if the accepted answer is highly scored.
    SELECT
        bq.PostId,
        COUNT(ans.Id) AS TotalAnswers,
        SUM(ans.Score) AS TotalAnswerScore,
        AVG(ans.Score) AS AvgAnswerScore,
        MAX(ans.CreationDate) AS LatestAnswerDate,
        (
            SELECT CASE WHEN ans_acc.Score > 10 THEN 'TRUE' ELSE 'FALSE' END
            FROM Posts ans_acc
            WHERE ans_acc.Id = bq.AcceptedAnswerId AND ans_acc.PostTypeId = 2
        ) AS AcceptedAnswerIsHighlyScored, -- Correlated subquery
        FIRST_VALUE(ans.OwnerUserId) OVER (PARTITION BY bq.PostId ORDER BY ans.Score DESC, ans.CreationDate ASC) AS TopAnswererId -- Window function
    FROM BaseQuestions bq
    LEFT JOIN Posts ans ON bq.PostId = ans.ParentId AND ans.PostTypeId = 2 -- Join for answers
    GROUP BY bq.PostId, bq.AcceptedAnswerId
),
TagUsageStats AS (
    -- Extracts the primary tag, counts the total number of tags for a question, and gets its global usage count.
    -- Utilizes complex string manipulation functions.
    SELECT
        bq.PostId,
        LOWER(TRIM(SPLIT_PART(SUBSTRING(bq.Tags FROM 2 FOR LENGTH(bq.Tags) - 2), '><', 1))) AS PrimaryTag, -- String extraction
        LENGTH(bq.Tags) - LENGTH(REPLACE(bq.Tags, '><', '')) + 1 AS NumberOfTags, -- Complex string calculation for tag count
        MAX(t.Count) AS PrimaryTagGlobalCount -- Global count for the primary tag
    FROM BaseQuestions bq
    LEFT JOIN Tags t ON LOWER(TRIM(SPLIT_PART(SUBSTRING(bq.Tags FROM 2 FOR LENGTH(bq.Tags) - 2), '><', 1))) = t.TagName
    GROUP BY bq.PostId, SPLIT_PART(SUBSTRING(bq.Tags FROM 2 FOR LENGTH(bq.Tags) - 2), '><', 1)
),
RelatedPostSummary AS (
    -- Summarizes linked and duplicate posts, aggregating duplicate post IDs into a single string.
    SELECT
        bq.PostId,
        COUNT(pl.Id) AS TotalLinks,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks,
        STRING_AGG(CASE WHEN lt.Name = 'Duplicate' THEN CONCAT('DUP:', pl.RelatedPostId) ELSE NULL END, ';') FILTER (WHERE lt.Name = 'Duplicate') AS DuplicatePostIds -- String aggregation and conditional filtering
    FROM BaseQuestions bq
    LEFT JOIN PostLinks pl ON bq.PostId = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY bq.PostId
),
UserRankings AS (
    -- Ranks users globally by reputation and provides reputation percentiles and badge counts.
    -- Uses RANK() and NTILE() window functions.
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS GlobalReputationRank, -- Window function
        NTILE(100) OVER (ORDER BY u.Reputation DESC) AS ReputationPercentile, -- Window function
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, -- Conditional aggregation
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
)
-- Final SELECT statement combining data from all CTEs.
-- Includes various expressions, NULL logic, and a final correlated subquery.
SELECT
    bq.PostId,
    bq.QuestionTitle,
    bq.QuestionCreationDate,
    bq.QuestionScore,
    bq.ViewCount,
    bq.AnswerCount,
    bq.CommentCount,
    bq.FavoriteCount,
    ROUND(bq.QuestionAgeYears, 2) AS QuestionAgeYears,
    COALESCE(u_owner.UserDisplayName, bq.OwnerDisplayName, 'Deleted User') AS QuestionOwnerDisplayName, -- NULL logic
    u_owner.Reputation AS QuestionOwnerReputation,
    u_owner.GlobalReputationRank AS QuestionOwnerReputationRank,
    qhd.TotalHistoryEvents,
    qhd.EditRevisionCount,
    qhd.CloseEventCount,
    qhd.ReopenEventCount,
    qhd.WasEverClosedFlag,
    qhd.LatestHistoryActionDate,
    qhd.LastCloseReasonDetail,
    COALESCE(u_last_hist.UserDisplayName, 'Community/Deleted User') AS LastHistoryActionUserDisplayName, -- NULL logic
    COALESCE(qvc.TotalUpvotesReceived, 0) AS TotalQuestionUpvotes, -- NULL logic
    COALESCE(qvc.TotalDownvotesReceived, 0) AS TotalQuestionDownvotes, -- NULL logic
    qvc.UniqueCommenters,
    ROUND(COALESCE(qvc.AverageCommentScore, 0), 2) AS AverageCommentScore, -- Numeric calculation and NULL logic
    adm.TotalAnswers,
    adm.AvgAnswerScore,
    COALESCE(adm.AcceptedAnswerIsHighlyScored, 'FALSE') AS AcceptedAnswerIsHighlyScored, -- NULL logic
    COALESCE(u_top_ans.UserDisplayName, 'N/A') AS TopAnswererDisplayName, -- NULL logic
    tss.PrimaryTag,
    tss.NumberOfTags,
    tss.PrimaryTagGlobalCount,
    rps.TotalLinks,
    rps.DuplicateLinks,
    COALESCE(rps.DuplicatePostIds, 'None') AS DuplicatePostIdsList, -- NULL logic
    CASE
        WHEN bq.ClosedDate IS NOT NULL AND qhd.ReopenEventCount > qhd.CloseEventCount THEN 'Closed & Reopened More'
        WHEN bq.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN qhd.EditRevisionCount > 5 THEN 'Heavily Edited'
        WHEN bq.ViewCount > 100000 THEN 'Very Popular'
        ELSE 'Active'
    END AS QuestionStatusCategory, -- Complex CASE expression
    (
        SELECT COUNT(DISTINCT ph_inner.UserId)
        FROM PostHistory ph_inner
        WHERE ph_inner.PostId = bq.PostId AND ph_inner.PostHistoryTypeId = 5 -- Specific PostHistoryTypeId for body edits
    ) AS BodyEditContributorsCount_Correlated -- Final correlated subquery
FROM BaseQuestions bq
LEFT JOIN UserRankings u_owner ON bq.QuestionOwnerId = u_owner.UserId
LEFT JOIN QuestionHistoryDetails qhd ON bq.PostId = qhd.PostId
LEFT JOIN UserRankings u_last_hist ON qhd.LastHistoryActionUserId = u_last_hist.UserId
LEFT JOIN QuestionVotesAndComments qvc ON bq.PostId = qvc.PostId
LEFT JOIN AnswerAndAcceptanceMetrics adm ON bq.PostId = adm.PostId
LEFT JOIN UserRankings u_top_ans ON adm.TopAnswererId = u_top_ans.UserId
LEFT JOIN TagUsageStats tss ON bq.PostId = tss.PostId
LEFT JOIN RelatedPostSummary rps ON bq.PostId = rps.PostId
WHERE
    bq.QuestionScore >= 100 -- Further filtering for higher impact questions
    AND qhd.WasEverClosedFlag = 'TRUE' -- Only include questions that were explicitly closed
    AND qhd.ReopenEventCount > 0       -- And were subsequently reopened at least once
ORDER BY bq.ViewCount DESC, bq.QuestionScore DESC, qhd.EditRevisionCount DESC
LIMIT 100; -- Limit the final result set for benchmarking practicality
