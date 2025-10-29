-- {"query": "1725.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3306} 

WITH UserActivitySummary AS (
    -- Summarizes user activity, including post/comment counts, vote counts, and average question scores.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        COUNT(DISTINCT C.Id) AS TotalCommentsByOwner,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END), 0.0) AS AvgQuestionScoreByOwner,
        MAX(U.LastAccessDate) AS LastUserAccessDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    WHERE U.Reputation > 500 -- Filter for more established users
      AND U.LastAccessDate >= (NOW() - INTERVAL '3 year')
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(P.Id) > 0 OR COUNT(C.Id) > 0 OR SUM(CASE WHEN V.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) > 0
),
PostEngagementMetrics AS (
    -- Gathers detailed metrics for Posts, focusing on Questions and Answers.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        COALESCE(P.Score, 0) AS PostScore,
        COALESCE(P.ViewCount, 0) AS PostViewCount,
        COALESCE(P.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(P.CommentCount, 0) AS PostCommentCount,
        COALESCE(P.FavoriteCount, 0) AS PostFavoriteCount,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        (EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / 86400) AS DaysSinceLastActivity, -- Time since last activity in days
        CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        CASE WHEN P.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed,
        P.ClosedDate,
        COALESCE(
            NULLIF(
                TRIM(
                    SPLIT_PART(
                        SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><', 1
                    )
                ),
                ''
            ),
            'no-primary-tag'
        ) AS PrimaryTag, -- Extracts the first tag from the tags string
        -- Rough count of code blocks and HTTP links in the post body
        (LENGTH(P.Body) - LENGTH(REPLACE(P.Body, '<code>', ''))) / 5 AS CodeSnippetCount, -- Assuming '<code>' is 5 characters
        (LENGTH(P.Body) - LENGTH(REPLACE(P.Body, 'http', ''))) / 4 AS LinkCountInBody -- Assuming 'http' is 4 characters
    FROM Posts P
    WHERE P.CreationDate >= (NOW() - INTERVAL '7 year') -- Posts from the last 7 years
      AND P.Body IS NOT NULL
      AND (P.PostTypeId = 1 OR (P.PostTypeId = 2 AND P.ParentId IS NOT NULL)) -- Questions or valid answers
),
PostHistoryInsights AS (
    -- Analyzes post history for edit counts, close/reopen events, and duplicate links.
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount, -- Title, Body, Tags edits
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEvents,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS LastCloseReasonId, -- Assuming Comment contains CloseReasonId for type 10
        (SELECT COUNT(DISTINCT PL.RelatedPostId)
         FROM PostLinks PL
         WHERE PL.PostId = PH.PostId AND PL.LinkTypeId = 3) AS DuplicateLinkCount, -- Correlated subquery for duplicate links
        (SELECT MAX(V.CreationDate)
         FROM Votes V
         WHERE V.PostId = PH.PostId AND V.VoteTypeId = 2) AS LatestUpVoteDate -- Correlated subquery for latest upvote date
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11) -- Relevant history types: Edits, Close, Reopen
    GROUP BY PH.PostId
),
TagPerformance AS (
    -- Aggregates performance metrics for popular tags.
    SELECT
        T.TagName,
        T.Id AS TagId,
        T.Count AS TotalPostsWithTag, -- Direct count from Tags table
        COALESCE(SUM(P.ViewCount), 0) AS TotalTagViewsAggregated,
        COALESCE(AVG(P.Score), 0.0) AS AvgQuestionScoreInTagAggregated,
        COALESCE(AVG(P.AnswerCount), 0.0) AS AvgAnswersPerQuestionInTagAggregated,
        COALESCE(MAX(P.CreationDate), '1900-01-01'::timestamp) AS LatestQuestionInTag
    FROM Tags T
    LEFT JOIN Posts P ON P.Tags LIKE '%<' || T.TagName || '>%' AND P.PostTypeId = 1 AND P.CreationDate >= (NOW() - INTERVAL '7 year')
    WHERE T.Count > 50 -- Filter for tags with at least 50 posts
    GROUP BY T.TagName, T.Id, T.Count
),
RankedPosts AS (
    -- Combines information from previous CTEs and applies window functions for ranking.
    SELECT
        PEM.PostId,
        PEM.PostTypeId,
        PEM.Title,
        PEM.PostScore,
        PEM.PostViewCount,
        PEM.PostAnswerCount,
        PEM.PostCommentCount,
        PEM.PostFavoriteCount,
        PEM.PostCreationDate,
        PEM.LastActivityDate,
        PEM.DaysSinceLastActivity,
        PEM.HasAcceptedAnswer,
        PEM.IsClosed,
        PEM.ClosedDate,
        PEM.PrimaryTag,
        PEM.CodeSnippetCount,
        PEM.LinkCountInBody,
        UAS.DisplayName AS OwnerDisplayName,
        UAS.Reputation AS OwnerReputation,
        UAS.UserCreationDate AS OwnerCreationDate,
        PHI.EditCount,
        PHI.CloseEvents,
        PHI.ReopenEvents,
        PHI.FirstEditDate,
        PHI.LastCloseReasonId,
        PHI.DuplicateLinkCount,
        PHI.LatestUpVoteDate,
        TP.TotalTagViewsAggregated,
        TP.AvgQuestionScoreInTagAggregated,
        TP.AvgAnswersPerQuestionInTagAggregated,
        DENSE_RANK() OVER (PARTITION BY PEM.PrimaryTag ORDER BY PEM.PostScore DESC, PEM.PostViewCount DESC) AS RankInTagByScoreViews,
        ROW_NUMBER() OVER (PARTITION BY UAS.UserId ORDER BY PEM.PostCreationDate DESC) AS UserPostSeqNum,
        LAG(PEM.PostCreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY UAS.UserId ORDER BY PEM.PostCreationDate) AS PreviousPostDate
    FROM PostEngagementMetrics PEM
    INNER JOIN UserActivitySummary UAS ON PEM.OwnerUserId = UAS.UserId
    LEFT JOIN PostHistoryInsights PHI ON PEM.PostId = PHI.PostId
    LEFT JOIN TagPerformance TP ON PEM.PrimaryTag = TP.TagName
    WHERE PEM.PostTypeId = 1 -- Focus on questions for ranking purposes
)
-- Main query: Combines two distinct sets of criteria using UNION ALL.
-- Branch 1: Highly active, well-received, and non-deleted questions.
SELECT
    RP.PostId,
    RP.PostTypeId,
    RP.Title,
    RP.OwnerDisplayName,
    RP.OwnerReputation,
    RP.PostScore,
    RP.PostViewCount,
    RP.PostAnswerCount,
    RP.PostCommentCount,
    RP.PostFavoriteCount,
    RP.PostCreationDate,
    RP.LastActivityDate,
    RP.DaysSinceLastActivity,
    RP.HasAcceptedAnswer,
    RP.IsClosed,
    RP.PrimaryTag,
    RP.CodeSnippetCount,
    RP.LinkCountInBody,
    RP.EditCount,
    RP.CloseEvents,
    RP.ReopenEvents,
    RP.DuplicateLinkCount,
    RP.RankInTagByScoreViews,
    (EXTRACT(EPOCH FROM (RP.PostCreationDate - RP.PreviousPostDate)) / 86400) AS DaysBetweenPosts, -- Days between current and previous post by owner
    (SELECT VT.Name FROM VoteTypes VT WHERE VT.Id = (
        SELECT V.VoteTypeId FROM Votes V WHERE V.PostId = RP.PostId ORDER BY V.CreationDate DESC LIMIT 1
    )) AS LatestVoteTypeName, -- Correlated subquery for the name of the latest vote type
    COALESCE(RP.TotalTagViewsAggregated, 0) AS TotalTagViews,
    COALESCE(RP.AvgQuestionScoreInTagAggregated, 0.0) AS AvgTagScore
FROM RankedPosts RP
WHERE RP.PostTypeId = 1 -- Ensure it's a question
  AND RP.RankInTagByScoreViews <= 10 -- Top 10 questions per primary tag
  AND RP.DaysSinceLastActivity < 365 -- Active within the last year
  AND RP.PostScore >= 50
  AND RP.PostAnswerCount >= 3
  AND RP.HasAcceptedAnswer IS TRUE
  AND RP.CodeSnippetCount > 0
  AND RP.LinkCountInBody > 0
  AND RP.OwnerReputation > 1000
  AND RP.Title ILIKE '%[Pp]erformance%' -- Case-insensitive search for 'performance' in title
  AND RP.LatestUpVoteDate IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM PostHistory PHC JOIN PostHistoryTypes PHT ON PHC.PostHistoryTypeId = PHT.Id WHERE PHC.PostId = RP.PostId AND PHT.Name = 'Post Deleted'
  ) -- Exclude deleted posts
  AND (
        (RP.IsClosed IS FALSE) OR -- Not closed OR
        (RP.IsClosed IS TRUE AND RP.ReopenEvents > 0) OR -- Closed but later reopened OR
        (RP.IsClosed IS TRUE AND RP.LastCloseReasonId IS NOT NULL AND RP.LastCloseReasonId NOT IN ('2', '3')) -- Closed for reasons other than 'Off-topic' or 'Subjective'
      )
UNION ALL
-- Branch 2: Contentious or problematic questions that have been closed, with specific user and tag criteria.
SELECT
    RP_Closed.PostId,
    RP_Closed.PostTypeId,
    RP_Closed.Title,
    RP_Closed.OwnerDisplayName,
    RP_Closed.OwnerReputation,
    RP_Closed.PostScore,
    RP_Closed.PostViewCount,
    RP_Closed.PostAnswerCount,
    RP_Closed.PostCommentCount,
    RP_Closed.PostFavoriteCount,
    RP_Closed.PostCreationDate,
    RP_Closed.LastActivityDate,
    RP_Closed.DaysSinceLastActivity,
    RP_Closed.HasAcceptedAnswer,
    RP_Closed.IsClosed,
    RP_Closed.PrimaryTag,
    RP_Closed.CodeSnippetCount,
    RP_Closed.LinkCountInBody,
    RP_Closed.EditCount,
    RP_Closed.CloseEvents,
    RP_Closed.ReopenEvents,
    RP_Closed.DuplicateLinkCount,
    RP_Closed.RankInTagByScoreViews,
    (EXTRACT(EPOCH FROM (RP_Closed.PostCreationDate - RP_Closed.PreviousPostDate)) / 86400) AS DaysBetweenPosts,
    (SELECT VT.Name FROM VoteTypes VT WHERE VT.Id = (
        SELECT V.VoteTypeId FROM Votes V WHERE V.PostId = RP_Closed.PostId ORDER BY V.CreationDate DESC LIMIT 1
    )) AS LatestVoteTypeName,
    COALESCE(RP_Closed.TotalTagViewsAggregated, 0) AS TotalTagViews,
    COALESCE(RP_Closed.AvgQuestionScoreInTagAggregated, 0.0) AS AvgTagScore
FROM RankedPosts RP_Closed
WHERE RP_Closed.PostTypeId = 1
  AND RP_Closed.IsClosed IS TRUE
  AND RP_Closed.ClosedDate >= (NOW() - INTERVAL '5 year') -- Closed within the last 5 years
  AND RP_Closed.EditCount >= 5 -- Significant number of edits
  AND RP_Closed.CloseEvents >= 1
  AND RP_Closed.ReopenEvents = 0 -- Still closed
  AND RP_Closed.PostScore < 20 -- Low score
  AND RP_Closed.DuplicateLinkCount > 0 -- Has duplicate links
  AND RP_Closed.OwnerReputation BETWEEN 500 AND 5000 -- Mid-tier user
  AND RP_Closed.PrimaryTag IN ('java', 'c#', 'python', 'javascript') -- Focus on specific popular tags
  AND RP_Closed.CodeSnippetCount > 1
ORDER BY PostCreationDate DESC, PostScore DESC
LIMIT 500;
