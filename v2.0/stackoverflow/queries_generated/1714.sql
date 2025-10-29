-- {"query": "1714.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3417} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous') AS DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COALESCE(U.Location, 'Unknown') AS Location,
        CAST(U.Reputation AS NUMERIC) / NULLIF(U.Views, 0) AS ReputationPerView,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24) AS DaysActive,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        COUNT(DISTINCT C.Id) AS TotalCommentsByOwner,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1 AND B.TagBased = FALSE) AS GoldBadgesCount,
        RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS UserReputationRank,
        NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile,
        ARRAY_AGG(DISTINCT SUBSTRING(B.Name FROM 1 FOR 10)) FILTER (WHERE B.Class = 1) AS TopGoldBadgesPreview -- Array of top 10 chars of Gold Badges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.CreationDate >= '2015-01-01' -- Filter users to a recent period for relevance
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location
    HAVING COUNT(P.Id) + COUNT(C.Id) > 5 -- Only consider users with at least some activity
),
PostInteraction AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        CASE
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN TRUE
            WHEN P.PostTypeId = 2 AND P.ParentId IS NOT NULL AND P.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = P.ParentId) THEN TRUE
            ELSE FALSE
        END AS IsAcceptedOrHasAcceptedAnswer,
        SUBSTRING(P.Tags FROM POSITION('<' IN P.Tags) + 1 FOR POSITION('>' IN P.Tags) - POSITION('<' IN P.Tags) - 1) AS PrimaryTag,
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Title, Body, Tags edits
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId) AS AvgOwnerPostScore,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS OwnerPostScoreRank,
        LAG(P.LastActivityDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastActivityDate) AS PreviousActivityDate,
        P.Body ILIKE '%performance%' OR P.Title ILIKE '%benchmark%' OR P.Tags ILIKE '%<optimization>%' AS ContainsPerformanceKeywords,
        P.LastEditorUserId IS NOT NULL AND P.LastEditorUserId = P.OwnerUserId AS EditedByOwner,
        (P.Score::NUMERIC / NULLIF(P.ViewCount, 0)) * 100 AS ScorePerViewPercentage,
        COALESCE(P.ParentId, P.Id) AS RootPostId -- For answers, get parent ID; for questions, use own ID
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2) -- Questions and Answers
    AND P.CreationDate >= '2020-01-01' -- Further filter posts for recent activity analysis
    AND P.Score > 0 -- Focus on posts with positive score
    AND NOT EXISTS (SELECT 1 FROM Comments C WHERE C.PostId = P.Id AND C.UserId = P.OwnerUserId AND C.CreationDate < P.CreationDate) -- Exclude posts with owner comments before creation (potential data anomaly or test post)
),
PostModerationAndLinks AS (
    SELECT
        P.Id AS PostId,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeletionVoteCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL THEN CRT.Name ELSE NULL END) AS LastCloseReasonType,
        COUNT(DISTINCT PL_Linked.Id) AS TotalLinkedPosts,
        COUNT(DISTINCT PL_Duplicate.Id) AS TotalDuplicatePosts,
        EXISTS (SELECT 1 FROM PostHistory PH_Mod WHERE PH_Mod.PostId = P.Id AND PH_Mod.PostHistoryTypeId IN (14, 15, 19, 20, 33, 34) AND PH_Mod.UserId IS NULL) AS HasCommunityOrModeratorAction,
        (
            SELECT U_Editor.DisplayName
            FROM PostHistory PH_Editor
            JOIN Users U_Editor ON PH_Editor.UserId = U_Editor.Id
            WHERE PH_Editor.PostId = P.Id
            AND PH_Editor.UserId IS NOT NULL
            GROUP BY U_Editor.DisplayName
            ORDER BY COUNT(PH_Editor.Id) DESC
            LIMIT 1
        ) AS MostFrequentHumanEditorDisplayName,
        AVG(EXTRACT(EPOCH FROM (PH_Close.CreationDate - P.CreationDate))) / (60 * 60 * 24) FILTER (WHERE PH_Close.PostHistoryTypeId = 10) AS AvgDaysToFirstClose,
        CASE
            WHEN P.ClosedDate IS NOT NULL AND PH_LastClose.PostHistoryTypeId = 10 THEN PH_LastClose.CreationDate
            ELSE NULL
        END AS ActualClosedTimestamp
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CRT.Id AS VARCHAR)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 -- For AvgDaysToFirstClose
    LEFT JOIN (
        SELECT PostId, CreationDate, PostHistoryTypeId,
               ROW_NUMBER() OVER(PARTITION BY PostId ORDER BY CreationDate DESC) as rn
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
    ) PH_LastClose ON P.Id = PH_LastClose.PostId AND PH_LastClose.rn = 1
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
    WHERE P.Id IN (SELECT PostId FROM PostInteraction) -- Only consider posts from previous CTE
    GROUP BY P.Id, P.ClosedDate, PH_LastClose.CreationDate, PH_LastClose.PostHistoryTypeId
),
CombinedPostData AS (
    SELECT
        PI.PostId,
        PI.PostTypeId,
        PI.PostTypeName,
        PI.OwnerUserId,
        PI.PostCreationDate,
        PI.Title,
        PI.Score,
        PI.ViewCount,
        PI.PostAgeDays,
        PI.IsAcceptedOrHasAcceptedAnswer,
        PI.PrimaryTag,
        PI.EditCount,
        PI.AvgOwnerPostScore,
        PI.OwnerPostScoreRank,
        PI.ContainsPerformanceKeywords,
        PI.EditedByOwner,
        PI.ScorePerViewPercentage,
        PML.CloseVoteCount,
        PML.ReopenVoteCount,
        PML.DeletionVoteCount,
        PML.LastCloseReasonType,
        PML.TotalLinkedPosts,
        PML.TotalDuplicatePosts,
        PML.HasCommunityOrModeratorAction,
        PML.MostFrequentHumanEditorDisplayName,
        PML.AvgDaysToFirstClose,
        PML.ActualClosedTimestamp,
        -- Weighted popularity score calculation
        (PI.Score * 0.5 + PI.ViewCount * 0.05 + COALESCE(PI.FavoriteCount, 0) * 2 + COALESCE(PI.AnswerCount, 0) * 1.5 - (PML.CloseVoteCount * 10 + PML.DeletionVoteCount * 20)) AS WeightedPostPopularityScore,
        CASE
            WHEN PI.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN PI.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN PI.AnswerCount > 0 THEN 'HasAnswers'
            WHEN PI.PostAgeDays > 365 AND PI.AnswerCount = 0 THEN 'StaleQuestion'
            ELSE 'Open'
        END AS PostStatusCategory,
        -- String expression and NULL logic combination
        COALESCE(UPPER(SUBSTRING(PI.PrimaryTag, 1, 4)), 'NTAG') || '-' || COALESCE(LEFT(PML.LastCloseReasonType, 5), 'N/A') || '-' || LPAD(PI.EditCount::VARCHAR, 2, '0') AS PostFeatureSummary
    FROM PostInteraction PI
    LEFT JOIN PostModerationAndLinks PML ON PI.PostId = PML.PostId
)
-- Main query combining user engagement and post data, with complex filtering and set operations
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ReputationPerView,
    UE.TotalPostsByOwner,
    UE.GoldBadgesCount,
    UE.UserReputationRank,
    CPD.PostId,
    CPD.PostTypeName,
    CPD.Title,
    CPD.Score AS PostScore,
    CPD.ViewCount AS PostViewCount,
    CPD.PostAgeDays,
    CPD.IsAcceptedOrHasAcceptedAnswer,
    CPD.PrimaryTag,
    CPD.EditCount AS PostEditCount,
    CPD.WeightedPostPopularityScore,
    CPD.PostStatusCategory,
    CPD.PostFeatureSummary,
    CPD.ContainsPerformanceKeywords,
    CPD.EditedByOwner,
    CPD.ScorePerViewPercentage,
    CPD.LastCloseReasonType,
    CPD.TotalLinkedPosts,
    CPD.MostFrequentHumanEditorDisplayName,
    AGE(CPD.ActualClosedTimestamp, CPD.PostCreationDate) AS DurationToClose -- Calculation with date interval
FROM UserEngagement UE
JOIN CombinedPostData CPD ON UE.UserId = CPD.OwnerUserId
WHERE UE.Reputation > 1000
AND CPD.PostAgeDays BETWEEN 30 AND 1095 -- Posts between 1 month and 3 years old
AND CPD.Score > 10
AND (CPD.ContainsPerformanceKeywords = TRUE OR CPD.TotalDuplicatePosts > 0 OR CPD.HasCommunityOrModeratorAction = TRUE)
AND NOT EXISTS (
    SELECT 1
    FROM PostHistory PH_Audit
    WHERE PH_Audit.PostId = CPD.PostId
    AND PH_Audit.PostHistoryTypeId = 35 -- Check for posts migrated away
    AND PH_Audit.CreationDate > CPD.PostCreationDate + INTERVAL '1 month' -- Migrated away after at least 1 month
)
AND (UE.ReputationDecile <= 3 OR CPD.WeightedPostPopularityScore > 50) -- High reputation or highly popular posts
UNION ALL
-- Another path for specific analysis: recent, low-scored questions from high-reputation users, possibly needing attention
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ReputationPerView,
    UE.TotalPostsByOwner,
    UE.GoldBadgesCount,
    UE.UserReputationRank,
    CPD.PostId,
    CPD.PostTypeName,
    CPD.Title,
    CPD.Score AS PostScore,
    CPD.ViewCount AS PostViewCount,
    CPD.PostAgeDays,
    CPD.IsAcceptedOrHasAcceptedAnswer,
    CPD.PrimaryTag,
    CPD.EditCount AS PostEditCount,
    CPD.WeightedPostPopularityScore,
    CPD.PostStatusCategory,
    CPD.PostFeatureSummary,
    CPD.ContainsPerformanceKeywords,
    CPD.EditedByOwner,
    CPD.ScorePerViewPercentage,
    CPD.LastCloseReasonType,
    CPD.TotalLinkedPosts,
    CPD.MostFrequentHumanEditorDisplayName,
    AGE(CPD.ActualClosedTimestamp, CPD.PostCreationDate) AS DurationToClose
FROM UserEngagement UE
JOIN CombinedPostData CPD ON UE.UserId = CPD.OwnerUserId
WHERE UE.Reputation > 20000 -- Very high reputation users
AND CPD.PostTypeId = 1 -- Only questions
AND CPD.PostAgeDays BETWEEN 7 AND 90 -- Recent questions (1 week to 3 months old)
AND CPD.Score <= 2 -- Low score
AND CPD.AnswerCount = 0 -- No answers yet
AND CPD.IsAcceptedOrHasAcceptedAnswer = FALSE
AND CPD.ContainsPerformanceKeywords = FALSE -- Not about performance
AND CPD.HasCommunityOrModeratorAction = FALSE -- No moderator action
ORDER BY WeightedPostPopularityScore ASC, UE.Reputation DESC, CPD.PostCreationDate DESC
LIMIT 5000;
