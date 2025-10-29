-- {"query": "1435.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4157} 

WITH UserPostStats AS (
    -- Aggregates post-related statistics for each user
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS TotalAcceptedAnswersProvided,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersWritten,
        SUM(P.Score) AS TotalPostScoreSum,
        MAX(P.LastActivityDate) AS LastUserPostActivityDate,
        MIN(P.CreationDate) AS FirstUserPostDate,
        MAX(P.ViewCount) AS MaxPostViewCount
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserBadgeStats AS (
    -- Counts badges for each user by class
    SELECT
        B.UserId,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadgesCount,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadgesCount,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadgesCount
    FROM Badges B
    GROUP BY B.UserId
),
UserCommentActivity AS (
    -- Summarizes comment activity for each user
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalCommentsMade,
        MAX(C.CreationDate) AS LastCommentDate,
        AVG(C.Score) AS AvgCommentScore
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
UserHistoryActivity AS (
    -- Summarizes post history edits for each user
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEdits,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) AS TotalContentEdits, -- Title, Body, Tags edits
        COUNT(DISTINCT PH.PostId) AS UniquePostsEdited
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserEngagementSummary AS (
    -- Combines various user-related statistics into a single view
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COALESCE(UPS.TotalPosts, 0) AS TotalPosts,
        COALESCE(UPS.TotalAcceptedAnswersProvided, 0) AS TotalAcceptedAnswersProvided,
        COALESCE(UPS.TotalQuestionsAsked, 0) AS TotalQuestionsAsked,
        COALESCE(UPS.TotalAnswersWritten, 0) AS TotalAnswersWritten,
        COALESCE(UPS.TotalPostScoreSum, 0) AS TotalPostScoreSum,
        COALESCE(UPS.LastUserPostActivityDate, U.LastAccessDate) AS LastUserActivity,
        COALESCE(UPS.FirstUserPostDate, U.CreationDate) AS FirstUserActivity,
        COALESCE(UPS.MaxPostViewCount, 0) AS MaxPostViewCount,
        COALESCE(UBS.GoldBadgesCount, 0) AS GoldBadgesCount,
        COALESCE(UBS.SilverBadgesCount, 0) AS SilverBadgesCount,
        COALESCE(UBS.BronzeBadgesCount, 0) AS BronzeBadgesCount,
        COALESCE(UCA.TotalCommentsMade, 0) AS TotalCommentsMade,
        COALESCE(UCA.LastCommentDate, U.CreationDate) AS LastCommentDate,
        COALESCE(UCA.AvgCommentScore, 0.0) AS AvgCommentScore,
        COALESCE(UHA.TotalHistoryEdits, 0) AS TotalHistoryEdits,
        COALESCE(UHA.TotalContentEdits, 0) AS TotalContentEdits,
        COALESCE(UHA.UniquePostsEdited, 0) AS UniquePostsEdited
    FROM Users U
    LEFT JOIN UserPostStats UPS ON U.Id = UPS.UserId
    LEFT JOIN UserBadgeStats UBS ON U.Id = UBS.UserId
    LEFT JOIN UserCommentActivity UCA ON U.Id = UCA.UserId
    LEFT JOIN UserHistoryActivity UHA ON U.Id = UHA.UserId
),
PostDetailedMetrics AS (
    -- Calculates various metrics for each post using subqueries and joins
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.ParentId,
        P.AcceptedAnswerId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastEditorUserId,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        -- Correlated subqueries for comment statistics
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id) AS TotalComments,
        (SELECT MAX(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id) AS LatestCommentDate,
        (SELECT SUM(C.Score) FROM Comments C WHERE C.PostId = P.Id) AS TotalCommentScore,
        -- Link type aggregates
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostCount,
        COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicatePostCount,
        -- Post history aggregates
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.UserId IS NOT NULL) AS UniqueEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS LastContentEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS ClosedByHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS ReopenedByHistoryDate,
        -- Correlated subqueries for vote counts
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 1) AS AcceptedVoteCount,
        -- Retrieves the specific close reason name if available and applicable
        (SELECT CR.Name FROM CloseReasonTypes CR WHERE CR.Id = CAST(PH_Close.Comment AS SMALLINT) AND PH_Close.PostHistoryTypeId = 10 AND PH_Close.CreationDate = P.ClosedDate LIMIT 1) AS SpecificCloseReason
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 AND P.ClosedDate IS NOT NULL AND PH_Close.CreationDate = P.ClosedDate
    GROUP BY P.Id, P.PostTypeId, P.ParentId, P.AcceptedAnswerId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.LastEditorUserId, P.LastEditDate, P.LastActivityDate, P.Title, P.Tags, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate
),
QuestionPerformanceRankings AS (
    -- Applies various window functions to questions to rank their performance
    SELECT
        PDM.PostId,
        PDM.PostTypeId,
        PDM.Score,
        PDM.ViewCount,
        PDM.AnswerCount,
        PDM.PostCreationDate AS CreationDate,
        ROW_NUMBER() OVER (PARTITION BY PDM.OwnerUserId ORDER BY PDM.Score DESC, PDM.ViewCount DESC) AS RankByOwnerScoreViews,
        DENSE_RANK() OVER (ORDER BY PDM.Score DESC, PDM.ViewCount DESC, PDM.AnswerCount DESC) AS GlobalPerformanceRank,
        NTILE(10) OVER (ORDER BY PDM.ViewCount DESC) AS ViewCountDecile,
        AVG(PDM.Score) OVER (PARTITION BY PDM.OwnerUserId ORDER BY PDM.PostCreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS OwnerRollingAvgScore, -- Rolling average for owner
        LAG(PDM.Score, 1, 0) OVER (PARTITION BY PDM.OwnerUserId ORDER BY PDM.PostCreationDate) AS PreviousPostScore
    FROM PostDetailedMetrics PDM
    WHERE PDM.PostTypeId = 1 -- Only questions are ranked here
),
TopTagsSummary AS (
    -- Extracts and aggregates statistics for frequently used tags
    SELECT
        unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName,
        COUNT(P.Id) AS TotalPostsWithTag,
        AVG(P.Score) AS AverageScoreForTag,
        COUNT(DISTINCT P.OwnerUserId) AS UniqueOwnersForTag
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1
    GROUP BY TagName
    HAVING COUNT(P.Id) > 100 -- Filter for tags with significant usage
    ORDER BY TotalPostsWithTag DESC
    LIMIT 100 -- Focus on top 100 tags for performance
),
MainQueryData AS (
    -- The core dataset combining all previous CTEs and applying complex logic
    SELECT
        P.Id AS Post_ID,
        PT.Name AS Post_Type,
        P.Title AS Post_Title,
        P.Body AS Post_Body_Excerpt, -- Include large text for I/O and text processing
        U_Owner.DisplayName AS Owner_DisplayName,
        U_Owner.Reputation AS Owner_Reputation,
        UES.TotalPosts AS Owner_TotalPosts,
        PDM.Score AS Post_Score,
        PDM.ViewCount AS Post_ViewCount,
        PDM.AnswerCount AS Post_AnswerCount,
        PDM.TotalComments AS Post_TotalComments,
        PDM.UpVoteCount AS Post_UpVotes,
        PDM.DownVoteCount AS Post_DownVotes,
        PDM.FavoriteCount AS Post_FavoriteCount,
        PDM.LinkedPostCount AS Post_LinkedCount,
        PDM.DuplicatePostCount AS Post_DuplicateCount,
        PDM.PostCreationDate,
        PDM.LastActivityDate,
        PDM.LastContentEditDate,
        PDM.ClosedDate,
        PDM.SpecificCloseReason,
        QPR.GlobalPerformanceRank,
        QPR.RankByOwnerScoreViews,
        QPR.ViewCountDecile,
        QPR.OwnerRollingAvgScore,
        QPR.PreviousPostScore,
        TTS.AverageScoreForTag AS MainTagAvgScore,
        TTS.UniqueOwnersForTag AS MainTagUniqueUsers,
        -- Complex calculations and NULL logic
        CASE
            WHEN PDM.TotalComments > 0 AND PDM.TotalCommentScore IS NOT NULL THEN
                CAST(PDM.TotalCommentScore AS DECIMAL) / PDM.TotalComments
            ELSE 0.0
        END AS AvgCommentScorePerPost,
        COALESCE(U_Owner.Location, 'Unknown Location') AS Owner_Location_Coalesced,
        EXTRACT(EPOCH FROM (PDM.LastActivityDate - PDM.PostCreationDate)) / 3600.0 AS HoursSinceCreationToLastActivity, -- Time difference in hours
        LENGTH(PDM.Title) AS TitleLength,
        LENGTH(PDM.Tags) AS TagsStringLength,
        -- String expressions for topic categorization
        CASE
            WHEN P.Title ILIKE '%sql%' OR P.Body ILIKE '%database%' THEN 'DB_Related'
            WHEN P.Title ILIKE '%python%' OR P.Tags LIKE '%<python>%' THEN 'Python_Related'
            WHEN P.Title ILIKE '%javascript%' OR P.Tags LIKE '%<javascript>%' THEN 'JavaScript_Related'
            ELSE 'Other_Topic'
        END AS TopicCategory,
        -- Correlated subquery to compare current post score with owner's average for *other* posts of the same type
        (
            SELECT AVG(P_other.Score)
            FROM Posts P_other
            WHERE P_other.OwnerUserId = P.OwnerUserId
              AND P_other.Id <> P.Id
              AND P_other.PostTypeId = P.PostTypeId
              AND P_other.CreationDate > P.CreationDate - INTERVAL '1 year' -- within past year relative to current post
        ) AS OwnerAvgOtherPostScoreForTypeLastYear,
        -- Detailed post status based on multiple conditions and NULL logic
        CASE
            WHEN PDM.ClosedDate IS NOT NULL AND PDM.SpecificCloseReason IS NOT NULL THEN PDM.SpecificCloseReason
            WHEN PDM.ClosedDate IS NOT NULL THEN 'Generic Closed'
            WHEN PDM.AnswerCount = 0 AND P.CreationDate < NOW() - INTERVAL '30 days' THEN 'Unanswered_Old'
            WHEN PDM.AcceptedAnswerId IS NOT NULL THEN 'Answered_Accepted'
            ELSE 'Active_Open'
        END AS PostStatusDetail,
        ABS(COALESCE(UES.Reputation, 0) - COALESCE(U_Editor.Reputation, 0)) AS OwnerEditorReputationDifference,
        -- Correlated subquery for a boolean check with an aggregate
        (
            SELECT COUNT(C_inner.Id) > 0
            FROM Comments C_inner
            WHERE C_inner.PostId = P.Id
              AND C_inner.CreationDate > COALESCE(P.LastEditDate, P.CreationDate)
              AND C_inner.UserId = P.OwnerUserId
        ) AS HasOwnerCommentAfterLastEditOrCreation,
        -- Correlated subquery for average score of early answers to a question
        CASE WHEN P.PostTypeId = 1 THEN (
            SELECT AVG(A.Score)
            FROM Posts A
            WHERE A.ParentId = P.Id
              AND A.PostTypeId = 2
              AND A.CreationDate < P.CreationDate + INTERVAL '7 days' -- Answers within first 7 days
        ) ELSE NULL END AS AvgAnswerScoreForQuestionEarly,
        -- Calculation involving string manipulation and other attributes
        COALESCE(PDM.FavoriteCount, 0) * (PDM.ViewCount / GREATEST(1.0, PDM.Score)) AS EngagementFactor, -- Avoid division by zero
        GREATEST(0, UES.GoldBadgesCount - UES.SilverBadgesCount) AS GoldSilverBadgeDifference,
        CASE WHEN P.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityWiki
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Users U_Owner ON P.OwnerUserId = U_Owner.Id
    LEFT JOIN Users U_Editor ON P.LastEditorUserId = U_Editor.Id
    LEFT JOIN UserEngagementSummary UES ON U_Owner.Id = UES.UserId
    JOIN PostDetailedMetrics PDM ON P.Id = PDM.PostId -- INNER JOIN to ensure all posts have detailed metrics
    LEFT JOIN QuestionPerformanceRankings QPR ON P.Id = QPR.PostId
    -- Join on the first extracted tag
    LEFT JOIN TopTagsSummary TTS ON P.Tags IS NOT NULL AND SUBSTRING(P.Tags FROM 2 FOR POSITION('>' IN P.Tags) - 2) = TTS.TagName
    WHERE
        P.CreationDate BETWEEN '2020-01-01' AND '2023-01-01'
        -- Subquery in WHERE clause for filtering posts with above-average view counts
        AND P.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = P.PostTypeId AND CreationDate > P.CreationDate - INTERVAL '1 year')
        -- Subquery in WHERE clause for filtering posts with score in top 75th percentile
        AND P.Score >= (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = P.PostTypeId AND CreationDate > P.CreationDate - INTERVAL '6 months')
        -- Complex OR conditions combining tag checks, score, favorite count, and user reputation
        AND (
            (P.Tags LIKE '%<sql>%' AND P.Score > 10 AND PDM.TotalComments > 3)
            OR (P.Tags LIKE '%<python>%' AND P.FavoriteCount > 5 AND U_Owner.Reputation > 500)
            OR (P.PostTypeId = 1 AND PDM.TotalComments > 5 AND U_Owner.Reputation > 1000 AND PDM.AnswerCount > 0)
        )
        AND P.Body IS NOT NULL AND LENGTH(P.Body) > 100 -- Ensure posts have a substantial body for text operations
        AND P.OwnerUserId IS NOT NULL
)
-- Use UNION ALL to combine two sets of filtered results from the MainQueryData CTE
-- This demonstrates a set operator across a complex derived dataset
SELECT * FROM MainQueryData
WHERE Post_Type = 'Question' AND Post_Score > 5 AND Post_ViewCount > 500
UNION ALL
SELECT * FROM MainQueryData
WHERE Post_Type = 'Answer' AND Post_Score > 10 AND HasOwnerCommentAfterLastEditOrCreation
ORDER BY Owner_Reputation DESC, Post_Score DESC, HoursSinceCreationToLastActivity ASC
LIMIT 2000;
