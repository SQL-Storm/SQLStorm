-- {"query": "1474.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3745} 

WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(COALESCE(P.Score, 0)) AS SumOfPostScoresOwned,
        SUM(COALESCE(C.Score, 0)) AS SumOfCommentScoresMade,
        -- Calculate user activity score based on various factors
        (CAST(U.Reputation AS REAL) * 0.1
         + COUNT(DISTINCT P.Id) * 0.5
         + COUNT(DISTINCT C.Id) * 0.3
         + U.UpVotes * 0.05
         - U.DownVotes * 0.02
         + COUNT(DISTINCT B.Id) * 2.0) AS UserActivityScore,
        NTILE(4) OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationQuartile,
        CASE
            WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 250 THEN 'Highly Detailed Bio'
            WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 50 THEN 'Moderate Bio'
            WHEN U.AboutMe IS NOT NULL THEN 'Minimal Bio'
            ELSE 'No Bio Provided'
        END AS AboutMeCategory,
        -- Check if user has an accepted answer (correlated subquery for existence)
        (SELECT CASE WHEN EXISTS (SELECT 1 FROM Posts A WHERE A.OwnerUserId = U.Id AND A.PostTypeId = 2 AND A.AcceptedAnswerId IS NOT NULL) THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location,
        U.Views, U.UpVotes, U.DownVotes, U.AboutMe
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS ActualCommentCount, -- From Posts table
        P.FavoriteCount,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyCharacterCount,
        (CAST(JULIANDAY(P.LastActivityDate) - JULIANDAY(P.CreationDate) AS INTEGER)) AS DaysSinceCreationActivity,
        -- Window function to count distinct editors by UserID for each post
        COUNT(DISTINCT PH.UserId) OVER (PARTITION BY P.Id) AS DistinctEditorsCount,
        -- Window function to find the time difference between the first and last edit for a post
        (JULIANDAY(MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) OVER (PARTITION BY P.Id))
         - JULIANDAY(MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) OVER (PARTITION BY P.Id))) * 24 AS HoursBetweenFirstLastEdit,
        -- Complex calculation for Post Engagement Score
        (COALESCE(P.Score, 0) * 2.5 + COALESCE(P.ViewCount, 0) * 0.1 + COALESCE(P.AnswerCount, 0) * 1.5 + COALESCE(P.CommentCount, 0) * 0.75 + COALESCE(P.FavoriteCount, 0) * 3.0)
        / (1.0 + (CAST(JULIANDAY('now') - JULIANDAY(P.CreationDate) AS REAL) / 365.0)) AS DynamicEngagementScore,
        -- Check if the post contains specific keywords (case-insensitive)
        CASE
            WHEN LOWER(P.Body) LIKE '%performance%' OR LOWER(P.Title) LIKE '%benchmark%' THEN 'PerformanceRelated'
            WHEN LOWER(P.Body) LIKE '%security%' OR LOWER(P.Title) LIKE '%vulnerability%' THEN 'SecurityRelated'
            WHEN LOWER(P.Body) LIKE '%database%' OR LOWER(P.Tags) LIKE '%<sql>%' THEN 'DatabaseSpecific'
            ELSE 'General'
        END AS ContentKeywordCategory,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        -- Correlated subquery to check if this specific answer was accepted
        (SELECT CASE WHEN EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = P.ParentId AND Q.AcceptedAnswerId = P.Id) THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts P
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4, 5, 6) -- Filter for edit history types
),
PostVoteHistory AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesFromVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesFromVotes,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotesFromVotes,
        SUM(CASE WHEN V.VoteTypeId IN (6, 10, 12) THEN 1 ELSE 0 END) AS ModerationVotesCount, -- Close, Deletion, Spam
        COUNT(DISTINCT V.UserId) AS DistinctVotersCount,
        -- Calculate average vote score (Up - Down)
        AVG(CASE WHEN V.VoteTypeId = 2 THEN 1 WHEN V.VoteTypeId = 3 THEN -1 ELSE 0 END) AS AvgVoteImpact,
        MIN(V.CreationDate) AS FirstVoteDate
    FROM Votes V
    GROUP BY V.PostId
),
ModerationAndClosureEvents AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.CreationDate END) AS LastDeletedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 13 THEN PH.CreationDate END) AS LastUndeletedDate,
        -- Extract the actual close reason name by joining to CloseReasonTypes based on Comment field
        CR.Name AS CloseReasonName,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.UserId END) AS DistinctClosersCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.UserId END) AS DistinctDeletersCount,
        -- Use LAG to find the time difference between a close and a reopen event if available
        (JULIANDAY(MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END))
         - JULIANDAY(LAG(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END), 1, MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END))
                      OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC))) * 24 AS HoursUntilReopened
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND CAST(PH.Comment AS SMALLINT) = CR.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13)
    GROUP BY PH.PostId, CR.Name
),
TagPerformance AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT P.Id) AS TaggedPostCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TaggedQuestionCount,
        AVG(P.Score) AS AvgScoreInTag,
        AVG(P.ViewCount) AS AvgViewCountInTag,
        -- Calculate the "Tag Vigor" (sum of scores for posts created within the last year)
        SUM(CASE WHEN P.CreationDate >= DATE('now', '-1 year') THEN P.Score ELSE 0 END) AS RecentTagVigor,
        MAX(P.CreationDate) AS LatestPostInTag
    FROM Tags T
    JOIN Posts P ON P.Tags LIKE '%<' || T.TagName || '>%' -- String matching for tags
    GROUP BY T.TagName
)
-- Main Query: Combine and analyze user, post, and moderation data
SELECT
    UEM.DisplayName AS User_DisplayName,
    UEM.Reputation AS User_Reputation,
    UEM.ReputationQuartile AS User_ReputationQuartile,
    UEM.TotalPostsOwned AS User_TotalPosts,
    UEM.TotalQuestionsOwned AS User_TotalQuestions,
    UEM.TotalAnswersOwned AS User_TotalAnswers,
    UEM.UserActivityScore AS User_CalculatedActivityScore,
    UEM.AboutMeCategory AS User_AboutMeDetail,
    UEM.HasAcceptedAnswer AS User_HasAcceptedAnswer,
    PCA.PostId AS Post_ID,
    PCA.PostTypeName AS Post_Type,
    PCA.Title AS Post_Title,
    PCA.PostScore AS Post_Score,
    PCA.ViewCount AS Post_ViewCount,
    PCA.DynamicEngagementScore AS Post_EngagementScore,
    PCA.DistinctEditorsCount AS Post_DistinctEditors,
    PCA.ContentKeywordCategory AS Post_KeywordCategory,
    PVA.UpVotesFromVotes AS Post_UpVotes,
    PVA.DownVotesFromVotes AS Post_DownVotes,
    PVA.ModerationVotesCount AS Post_ModerationVotes,
    PVA.AvgVoteImpact AS Post_AvgVoteImpact,
    MA.LastClosedDate AS Post_LastClosedDate,
    MA.CloseReasonName AS Post_CloseReason,
    MA.DistinctClosersCount AS Post_DistinctClosers,
    MA.HoursUntilReopened AS Post_HoursToReopen,
    TP.TagName AS Primary_Tag_Name,
    TP.AvgScoreInTag AS Primary_Tag_AvgScore,
    TP.RecentTagVigor AS Primary_Tag_RecentVigor,
    -- Complex calculated field using COALESCE for potential NULLs
    ROUND(
        (COALESCE(UEM.UserActivityScore, 0) * 0.3)
        + (COALESCE(PCA.DynamicEngagementScore, 0) * 0.5)
        + (COALESCE(PVA.AvgVoteImpact, 0) * 10.0)
        - (COALESCE(MA.DistinctClosersCount, 0) * 5.0)
        + (CASE WHEN UEM.HasAcceptedAnswer = 1 THEN 20 ELSE 0 END)
        + (CASE WHEN PCA.IsAcceptedAnswer = 1 THEN 15 ELSE 0 END)
        + (CASE WHEN PCA.ContentKeywordCategory = 'PerformanceRelated' THEN 10 ELSE 0 END)
        + (CASE WHEN PCA.PostTypeName = 'Question' AND PCA.AnswerCount IS NOT NULL AND PCA.AnswerCount > 5 THEN 5 ELSE 0 END)
        , 2
    ) AS Overall_CombinedRankScore,
    -- NULL logic and string manipulation for a "Moderation Status"
    CASE
        WHEN MA.LastClosedDate IS NOT NULL AND MA.LastReopenedDate IS NULL THEN 'ClosedPermanently'
        WHEN MA.LastClosedDate IS NOT NULL AND MA.LastReopenedDate IS NOT NULL AND MA.LastReopenedDate > MA.LastClosedDate THEN 'ClosedThenReopened'
        WHEN MA.LastDeletedDate IS NOT NULL THEN 'Deleted'
        WHEN PCA.ClosedDate IS NOT NULL AND MA.LastClosedDate IS NULL THEN 'Closed_Legacy' -- If CloseDate exists but no explicit history
        ELSE 'ActiveOrOpen'
    END AS Post_ModerationStatus,
    -- Elaborate string expression: Concatenate owner display name and primary tag name, handling NULLs
    COALESCE(UEM.DisplayName, 'Community User') || ' posted on ' || COALESCE(TP.TagName, 'General') AS User_Tag_Summary
FROM UserEngagementMetrics UEM
INNER JOIN PostContentAnalysis PCA ON UEM.UserId = PCA.OwnerUserId
LEFT JOIN PostVoteHistory PVA ON PCA.PostId = PVA.PostId
LEFT JOIN ModerationAndClosureEvents MA ON PCA.PostId = MA.PostId
-- For TagPerformance, we attempt to join on the first tag found in the Tags string
LEFT JOIN Tags temp_tags ON PCA.Tags LIKE '%<' || temp_tags.TagName || '>%'
LEFT JOIN TagPerformance TP ON temp_tags.TagName = TP.TagName
WHERE
    UEM.Reputation >= 5000 -- Filter for higher reputation users
    AND PCA.PostScore >= 10 -- Filter for posts with reasonable scores
    AND PCA.PostTypeId IN (1, 2) -- Only Questions and Answers
    AND PCA.PostCreationDate BETWEEN DATE('2021-01-01') AND DATE('2023-12-31') -- Date range for posts
    AND (
        (PCA.ContentKeywordCategory = 'PerformanceRelated' AND PCA.DynamicEngagementScore > 50)
        OR
        (UEM.HasAcceptedAnswer = 1 AND PCA.IsAcceptedAnswer = 1)
        OR
        (MA.DistinctClosersCount > 0 AND MA.HoursUntilReopened IS NOT NULL AND MA.HoursUntilReopened < 72) -- Closed and reopened within 72 hours
    ) -- Complex predicate with OR logic
    AND EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UEM.UserId AND B.Class = 1 AND B.Date >= UEM.UserCreationDate) -- Correlated Subquery: user has at least one gold badge earned after account creation
GROUP BY
    UEM.DisplayName, UEM.Reputation, UEM.ReputationQuartile, UEM.TotalPostsOwned, UEM.TotalQuestionsOwned,
    UEM.TotalAnswersOwned, UEM.UserActivityScore, UEM.AboutMeCategory, UEM.HasAcceptedAnswer,
    PCA.PostId, PCA.PostTypeName, PCA.Title, PCA.PostScore, PCA.ViewCount, PCA.DynamicEngagementScore,
    PCA.DistinctEditorsCount, PCA.ContentKeywordCategory, PVA.UpVotesFromVotes, PVA.DownVotesFromVotes,
    PVA.ModerationVotesCount, PVA.AvgVoteImpact, MA.LastClosedDate, MA.CloseReasonName,
    MA.DistinctClosersCount, MA.HoursUntilReopened, TP.TagName, TP.AvgScoreInTag, TP.RecentTagVigor,
    PCA.AnswerCount, MA.LastDeletedDate, PCA.ClosedDate, PCA.IsAcceptedAnswer
HAVING Overall_CombinedRankScore > 100 -- Filter based on final calculated score
ORDER BY Overall_CombinedRankScore DESC, UEM.Reputation DESC NULLS LAST, Post_ID ASC
;
