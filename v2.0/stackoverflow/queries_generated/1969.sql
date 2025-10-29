-- {"query": "1969.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3688} 

WITH UserEngagementMetrics AS (
    -- Calculate user-specific metrics, including badge counts and a derived tier
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        (U.UpVotes - U.DownVotes) AS NetVotesGiven,
        CASE
            WHEN U.Reputation >= 50000 AND COUNT(DISTINCT B.Id) >= 20 AND U.UpVotes > 1000 THEN 'Legendary'
            WHEN U.Reputation >= 10000 AND COUNT(DISTINCT B.Id) >= 10 THEN 'Elite'
            WHEN U.Reputation >= 2000 AND COUNT(DISTINCT B.Id) >= 3 THEN 'Experienced'
            WHEN U.Reputation >= 200 THEN 'Active'
            ELSE 'Novice'
        END AS UserTier,
        U.CreationDate AS UserCreationDate
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
),
PostHistoricalInsights AS (
    -- Analyze post history for significant events like edits, closes, reopens, and apply window functions
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)) AS TotalEditRevertHistoryCount, -- Edits and Reverts
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 10) AS CloseHistoryCount,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 11) AS ReopenHistoryCount,
        COUNT(DISTINCT PH.UserId) AS UniqueHistoryContributors,
        -- Window function: Rank posts by edit count within each PostType
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) DESC) AS EditRankWithinPostType,
        -- Window function: Average score of posts by the same owner, up to this point in time
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgOwnerPostScore
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate, P.ClosedDate
),
TagPerformanceMetrics AS (
    -- Aggregate performance metrics for tags and rank them
    SELECT
        T.TagName,
        COUNT(P.Id) AS TotalPostsInTag,
        AVG(P.Score) AS AvgTagScore,
        AVG(P.ViewCount) AS AvgTagViewCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount ELSE 0 END) AS TotalAnswersInTag,
        MAX(P.CreationDate) AS LatestPostDateInTag,
        MIN(P.CreationDate) AS EarliestPostDateInTag,
        -- Window function: Rank tags by average score
        DENSE_RANK() OVER (ORDER BY AVG(P.Score) DESC, COUNT(P.Id) DESC) AS TagScoreRank
    FROM Tags T
    INNER JOIN Posts P ON P.Tags LIKE CONCAT('%<', T.TagName, '>%') -- String expression for tag matching
    WHERE P.PostTypeId = 1 -- Only questions have tags in this format
    GROUP BY T.TagName
    HAVING COUNT(P.Id) >= 50 AND AVG(P.Score) > 0
),
CommentInteractionAnalysis AS (
    -- Analyze comment sentiment and extract specific comments using subqueries
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(CASE WHEN C.Text ILIKE '%great%' OR C.Text ILIKE '%thanks%' OR C.Text ILIKE '%helpful%' THEN 1 ELSE 0 END) AS PositiveComments,
        SUM(CASE WHEN C.Text ILIKE '%bug%' OR C.Text ILIKE '%error%' OR C.Text ILIKE '%wrong%' OR C.Text ILIKE '%issue%' THEN 1 ELSE 0 END) AS NegativeComments,
        SUM(CASE WHEN C.Text ILIKE '%question%' OR C.Text ILIKE '%clarify%' THEN 1 ELSE 0 END) AS ClarificationRequests,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        -- Correlated subquery: Get the text of the first comment made by the post owner
        (
            SELECT C_sub.Text
            FROM Comments C_sub
            WHERE C_sub.PostId = C.PostId
              AND C_sub.UserId = P.OwnerUserId
            ORDER BY C_sub.CreationDate ASC
            LIMIT 1
        ) AS FirstOwnerCommentText,
        -- String expression: Extract first 50 chars of the most upvoted comment, or NULL if empty
        NULLIF(SUBSTRING(
            (SELECT C_sub_top.Text FROM Comments C_sub_top WHERE C_sub_top.PostId = C.PostId ORDER BY C_sub_top.Score DESC, C_sub_top.CreationDate DESC LIMIT 1),
            1, 50), '') AS TopCommentExcerpt
    FROM Comments C
    JOIN Posts P ON C.PostId = P.Id -- Join to Posts to get OwnerUserId for correlated subquery
    GROUP BY C.PostId, P.OwnerUserId
)
-- First branch: High-view questions meeting specific criteria
SELECT
    P.Id AS PostIdentifier,
    'Question_HighViews' AS RecordType,
    PT.Name AS PostTypeName,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    UEM_P.DisplayName AS OwnerDisplayName,
    UEM_P.UserTier AS OwnerTier,
    UEM_P.Reputation AS OwnerReputation,
    PHI_P.TotalEditRevertHistoryCount AS TotalEditActivity,
    PHI_P.CloseHistoryCount AS PostCloseCount,
    PHI_P.ReopenHistoryCount AS PostReopenCount,
    TPM.TagName AS PrimaryTagName,
    TPM.AvgTagScore,
    CIA.TotalComments AS CommentCount,
    CIA.PositiveComments,
    CIA.NegativeComments,
    CIA.FirstOwnerCommentText,
    CIA.TopCommentExcerpt,
    -- Complicated calculation/expression: Days active since creation
    CAST(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / (24 * 3600.0) AS NUMERIC(10, 2)) AS DaysActiveSinceCreation,
    COALESCE(P.ClosedDate, '1900-01-01'::timestamp) AS EffectiveClosedDate, -- NULL logic using COALESCE
    -- Window function: Previous post score by the same owner
    LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostScoreByOwner,
    -- Window function: Rank posts by score within each owner's activity
    RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS OwnerPostRankByScoreViews,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavoritesCount, -- Non-correlated subquery
    L.RelatedPostId AS LinkedPostId,
    LT.Name AS LinkTypeDescription,
    P.AnswerCount,
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS AvgCommentScore,
    NULLIF(P.Body, '') AS PostBodyContent, -- NULL logic using NULLIF
    REGEXP_REPLACE(SUBSTRING(COALESCE(P.Title, 'Untitled Post'), 1, 50), '[^a-zA-Z0-9 ]', '', 'g') AS CleanedTitleExcerpt, -- String expression with NULL handling
    (SELECT MAX(A_sub.Score) FROM Posts A_sub WHERE A_sub.ParentId = P.Id) AS MaxAnswerScore, -- Non-correlated subquery
    (SELECT MIN(A_sub.CreationDate) FROM Posts A_sub WHERE A_sub.ParentId = P.Id AND A_sub.AcceptedAnswerId IS NOT NULL) AS FirstAcceptedAnswerDate -- Subquery for specific scenario

FROM Posts P
INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN UserEngagementMetrics UEM_P ON P.OwnerUserId = UEM_P.UserId
LEFT JOIN PostHistoricalInsights PHI_P ON P.Id = PHI_P.PostId
LEFT JOIN CommentInteractionAnalysis CIA ON P.Id = CIA.PostId
LEFT JOIN PostLinks L ON P.Id = L.PostId AND L.LinkTypeId = 1 -- Outer join for linked posts
LEFT JOIN LinkTypes LT ON L.LinkTypeId = LT.Id
LEFT JOIN Tags T ON P.Tags LIKE CONCAT('%<', T.TagName, '>%')
LEFT JOIN TagPerformanceMetrics TPM ON T.TagName = TPM.TagName
WHERE P.PostTypeId = 1 -- Questions only
  AND P.ViewCount > 5000 -- High views
  AND P.CreationDate BETWEEN '2021-01-01' AND '2023-12-31'
  AND (P.OwnerUserId IS NOT NULL OR P.CommunityOwnedDate IS NOT NULL) -- NULL logic for owner existence
  AND UEM_P.UserTier IN ('Legendary', 'Elite', 'Experienced')
  AND PHI_P.TotalEditRevertHistoryCount >= 2
  AND TPM.TagScoreRank <= 10 -- Only top-ranked tags
  AND P.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= P.CreationDate - INTERVAL '1 year') -- Correlated subquery in WHERE
  AND P.AnswerCount > 0
  AND (P.AcceptedAnswerId IS NOT NULL OR P.ClosedDate IS NOT NULL) -- More complex predicate
  AND (CIA.NegativeComments IS NULL OR CIA.NegativeComments < 3) -- NULL logic in WHERE for comment sentiment
  
UNION ALL

-- Second branch: High-scoring accepted answers for highly-ranked tags
SELECT
    P.Id AS PostIdentifier,
    'Answer_HighScore' AS RecordType,
    PT.Name AS PostTypeName,
    NULL AS PostTitle, -- Answers don't have titles directly
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    NULL AS PostViewCount, -- Answers don't have view counts directly
    UEM_P.DisplayName AS OwnerDisplayName,
    UEM_P.UserTier AS OwnerTier,
    UEM_P.Reputation AS OwnerReputation,
    PHI_P.TotalEditRevertHistoryCount AS TotalEditActivity,
    PHI_P.CloseHistoryCount AS PostCloseCount,
    PHI_P.ReopenHistoryCount AS PostReopenCount,
    TPM_Parent.TagName AS PrimaryTagName, -- Use parent question's tag
    TPM_Parent.AvgTagScore,
    CIA.TotalComments AS CommentCount,
    CIA.PositiveComments,
    CIA.NegativeComments,
    CIA.FirstOwnerCommentText,
    CIA.TopCommentExcerpt,
    CAST(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / (24 * 3600.0) AS NUMERIC(10, 2)) AS DaysActiveSinceCreation,
    COALESCE(P.ClosedDate, '1900-01-01'::timestamp) AS EffectiveClosedDate,
    LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostScoreByOwner,
    RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS OwnerPostRankByScoreViews,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavoritesCount,
    L.RelatedPostId AS LinkedPostId,
    LT.Name AS LinkTypeDescription,
    NULL AS AnswerCount, -- This is an answer itself
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS AvgCommentScore,
    NULLIF(P.Body, '') AS PostBodyContent,
    REGEXP_REPLACE(SUBSTRING(COALESCE(QP.Title, 'No Question Title'), 1, 50), '[^a-zA-Z0-9 ]', '', 'g') AS CleanedTitleExcerpt, -- Use parent question title for answers
    (SELECT MAX(A_sub.Score) FROM Posts A_sub WHERE A_sub.ParentId = P.ParentId) AS MaxAnswerScore, -- Max answer score for its *parent question*
    (SELECT MIN(A_sub.CreationDate) FROM Posts A_sub WHERE A_sub.ParentId = P.ParentId AND A_sub.AcceptedAnswerId IS NOT NULL) AS FirstAcceptedAnswerDate

FROM Posts P
INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
INNER JOIN Posts QP ON P.ParentId = QP.Id -- Join to get parent question details
LEFT JOIN UserEngagementMetrics UEM_P ON P.OwnerUserId = UEM_P.UserId
LEFT JOIN PostHistoricalInsights PHI_P ON P.Id = PHI_P.PostId
LEFT JOIN CommentInteractionAnalysis CIA ON P.Id = CIA.PostId
LEFT JOIN PostLinks L ON P.Id = L.PostId AND L.LinkTypeId = 1
LEFT JOIN LinkTypes LT ON L.LinkTypeId = LT.Id
LEFT JOIN Tags T_Parent ON QP.Tags LIKE CONCAT('%<', T_Parent.TagName, '>%') -- Use parent question's tags
LEFT JOIN TagPerformanceMetrics TPM_Parent ON T_Parent.TagName = TPM_Parent.TagName
WHERE P.PostTypeId = 2 -- Answers only
  AND P.Score >= 50 -- High scoring answers
  AND P.CreationDate BETWEEN '2021-01-01' AND '2023-12-31'
  AND P.OwnerUserId IS NOT NULL
  AND UEM_P.Reputation >= 5000
  AND PHI_P.UniqueHistoryContributors >= 1
  AND TPM_Parent.TagScoreRank <= 5 -- Parent question's tag is top-ranked
  AND P.Id = QP.AcceptedAnswerId -- Only accepted answers
  AND (CIA.PositiveComments IS NULL OR CIA.PositiveComments >= 1) -- NULL logic in WHERE
ORDER BY PostCreationDate DESC, PostScore DESC
LIMIT 2000;
