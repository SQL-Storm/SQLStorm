-- {"query": "1911.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2905} 

WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(P.Score) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE NULL END) AS AvgQuestionViews,
        MAX(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount ELSE NULL END) AS MaxQuestionAnswers,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id ELSE NULL END) AS GoldBadges,
        NTILE(5) OVER (ORDER BY U.Reputation DESC, U.Id ASC) AS ReputationTier,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id ELSE NULL END) AS EditCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId
    WHERE U.Reputation > 750
      AND U.LastAccessDate >= '2023-01-01'::timestamp
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostTagUnnest AS (
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
PostDetailMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        LENGTH(P.Body) AS BodyLength,
        (CHAR_LENGTH(P.Body) - CHAR_LENGTH(REPLACE(LOWER(P.Body), 'database', ''))) / LENGTH('database') AS DatabaseKeywordCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownvoteCount,
        CASE
            WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 'Closed Question'
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 'Answered Question'
            WHEN P.PostTypeId = 2 AND P.ParentId IS NOT NULL THEN 'Answer Post'
            ELSE 'Other Post Type'
        END AS PostStatusCategory
    FROM Posts P
    WHERE P.CreationDate >= '2022-01-01'::timestamp
      AND (P.PostTypeId = 1 OR P.PostTypeId = 2)
),
PostHistoryEventsWithLag AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS LatestHistoryDate,
        LAG(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS SecondLatestHistoryDate,
        PHT.Name AS LatestHistoryTypeName,
        PH.PostHistoryTypeId AS LatestHistoryTypeId,
        PH.Comment,
        CASE
            WHEN PH.PostHistoryTypeId IN (10, 101) THEN
                (SELECT CR.Name FROM CloseReasonTypes CR WHERE CR.Id = CAST(PH.Comment AS smallint) LIMIT 1)
            ELSE NULL
        END AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn_desc
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.CreationDate >= '2023-01-01'::timestamp
      AND PH.PostHistoryTypeId IN (1, 2, 4, 5, 10, 11, 12, 13)
),
PostTagAggregates AS (
    SELECT
        PTU.TagName,
        COUNT(DISTINCT PTU.PostId) AS TaggedPostsCount,
        AVG(PDM.PostScore) AS AvgPostScoreForTag,
        COUNT(DISTINCT CASE WHEN PDM.PostTypeId = 1 AND PDM.AnswerCount > 0 THEN PDM.PostId ELSE NULL END) AS AnsweredQuestionsWithTag
    FROM PostTagUnnest PTU
    JOIN PostDetailMetrics PDM ON PTU.PostId = PDM.PostId
    GROUP BY PTU.TagName
    HAVING COUNT(DISTINCT PTU.PostId) > 50
),
TopPostTagPerPost AS (
    SELECT
        PTU.PostId,
        PTU.TagName AS DominantTag,
        PTA.AvgPostScoreForTag AS DominantTagAvgScore,
        ROW_NUMBER() OVER (PARTITION BY PTU.PostId ORDER BY PTA.AvgPostScoreForTag DESC NULLS LAST, PTU.TagName ASC) AS rn
    FROM PostTagUnnest PTU
    JOIN PostTagAggregates PTA ON PTU.TagName = PTA.TagName
)
(
    SELECT
        'High_Score_Question_Analysis' AS AnalysisType,
        UCS.UserId,
        UCS.UserName,
        UCS.Reputation,
        UCS.ReputationTier,
        PDM.PostId,
        PDM.Title,
        PDM.PostStatusCategory,
        PDM.PostScore,
        PDM.UpvoteCount,
        PDM.DownvoteCount,
        PDM.FavoriteCount,
        PDM.BodyLength,
        PDM.DatabaseKeywordCount,
        TPT.DominantTag,
        TPT.DominantTagAvgScore,
        PHE.LatestHistoryTypeName AS LastHistoryEvent,
        PHE.LatestHistoryDate AS LastHistoryEventDate,
        COALESCE(PHE.CloseReason, 'Not Closed / N/A') AS PostCloseReason,
        AGE(NOW(), UCS.UserCreationDate) AS UserAccountAge,
        AGE(NOW(), PDM.PostCreationDate) AS PostAge,
        EXTRACT(WEEK FROM PDM.PostCreationDate) AS WeekOfCreation,
        (PDM.UpvoteCount - PDM.DownvoteCount) AS NetVotes,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = PDM.PostId AND C.CreationDate > NOW() - INTERVAL '60 days') AS AvgRecentCommentScore,
        CASE
            WHEN UCS.Reputation > 10000 AND PDM.PostScore > 200 THEN 'Legendary Impact Contributor'
            WHEN UCS.Reputation > 5000 AND PDM.PostScore > 100 THEN 'High Impact Contributor'
            WHEN UCS.Reputation BETWEEN 1000 AND 5000 AND PDM.PostScore > 50 THEN 'Moderate Impact Contributor'
            ELSE 'General Contributor'
        END AS ContributorCategory,
        NULLIF(PDM.ViewCount, 0) AS ViewCountNonNull,
        CASE
            WHEN PDM.ViewCount IS NOT NULL AND PDM.ViewCount > 0
                 AND PDM.AnswerCount IS NOT NULL AND PDM.AnswerCount > 0
            THEN CAST(PDM.AnswerCount AS DECIMAL) / PDM.ViewCount
            ELSE 0
        END AS AnswerToViewRatio,
        (PHE.LatestHistoryDate - PHE.SecondLatestHistoryDate) AS TimeBetweenLastTwoHistoryEvents
    FROM UserContributionSummary UCS
    JOIN PostDetailMetrics PDM ON UCS.UserId = PDM.OwnerUserId
    LEFT JOIN (SELECT * FROM PostHistoryEventsWithLag WHERE rn_desc = 1) PHE ON PDM.PostId = PHE.PostId
    LEFT JOIN (SELECT * FROM TopPostTagPerPost WHERE rn = 1) TPT ON PDM.PostId = TPT.PostId
    WHERE PDM.PostTypeId = 1
      AND PDM.PostScore > 50
      AND PDM.DatabaseKeywordCount > 0
      AND UCS.TotalPosts > 10
      AND UCS.GoldBadges >= 1
      AND EXISTS (SELECT 1 FROM Badges B_INNER WHERE B_INNER.UserId = UCS.UserId AND B_INNER.Name LIKE '%Question%' AND B_INNER.Date > NOW() - INTERVAL '2 year')
      AND PDM.PostCreationDate BETWEEN '2023-01-01'::timestamp AND '2023-12-31'::timestamp
      AND PDM.BodyLength > 500
)
UNION ALL
(
    SELECT
        'Reputable_User_Answer_Analysis' AS AnalysisType,
        UCS.UserId,
        UCS.UserName,
        UCS.Reputation,
        UCS.ReputationTier,
        PDM.PostId,
        PDM.Title,
        PDM.PostStatusCategory,
        PDM.PostScore,
        PDM.UpvoteCount,
        PDM.DownvoteCount,
        PDM.FavoriteCount,
        PDM.BodyLength,
        PDM.DatabaseKeywordCount,
        TPT.DominantTag,
        TPT.DominantTagAvgScore,
        PHE.LatestHistoryTypeName AS LastHistoryEvent,
        PHE.LatestHistoryDate AS LastHistoryEventDate,
        COALESCE(PHE.CloseReason, 'Not Closed / N/A') AS PostCloseReason,
        AGE(NOW(), UCS.UserCreationDate) AS UserAccountAge,
        AGE(NOW(), PDM.PostCreationDate) AS PostAge,
        EXTRACT(WEEK FROM PDM.PostCreationDate) AS WeekOfCreation,
        (PDM.UpvoteCount - PDM.DownvoteCount) AS NetVotes,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = PDM.PostId AND C.CreationDate > NOW() - INTERVAL '60 days') AS AvgRecentCommentScore,
        CASE
            WHEN UCS.Reputation > 10000 AND PDM.PostScore > 200 THEN 'Legendary Impact Contributor'
            WHEN UCS.Reputation > 5000 AND PDM.PostScore > 100 THEN 'High Impact Contributor'
            WHEN UCS.Reputation BETWEEN 1000 AND 5000 AND PDM.PostScore > 50 THEN 'Moderate Impact Contributor'
            ELSE 'General Contributor'
        END AS ContributorCategory,
        NULLIF(PDM.ViewCount, 0) AS ViewCountNonNull,
        CASE
            WHEN PDM.ViewCount IS NOT NULL AND PDM.ViewCount > 0
                 AND PDM.AnswerCount IS NOT NULL AND PDM.AnswerCount > 0
            THEN CAST(PDM.AnswerCount AS DECIMAL) / PDM.ViewCount
            ELSE 0
        END AS AnswerToViewRatio,
        (PHE.LatestHistoryDate - PHE.SecondLatestHistoryDate) AS TimeBetweenLastTwoHistoryEvents
    FROM UserContributionSummary UCS
    JOIN PostDetailMetrics PDM ON UCS.UserId = PDM.OwnerUserId
    LEFT JOIN (SELECT * FROM PostHistoryEventsWithLag WHERE rn_desc = 1) PHE ON PDM.PostId = PHE.PostId
    LEFT JOIN (SELECT * FROM TopPostTagPerPost WHERE rn = 1) TPT ON PDM.PostId = TPT.PostId
    WHERE PDM.PostTypeId = 2
      AND UCS.ReputationTier <= 2
      AND PDM.PostScore > 25
      AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = PDM.ParentId AND Q.AnswerCount > 5)
      AND PDM.PostCreationDate BETWEEN '2023-01-01'::timestamp AND '2023-12-31'::timestamp
      AND PDM.BodyLength > 300
)
ORDER BY Reputation DESC, NetVotes DESC
LIMIT 1000;
