-- {"query": "1335.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2845} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(P.Score) AS TotalPostScoreReceived,
        SUM(CASE WHEN V.VoteTypeId = 2 AND V.UserId = U.Id THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 AND V.UserId = U.Id THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) AS TitleLength,
        REPLACE(REPLACE(REPLACE(P.Tags, '>', ' '), '<', ' '), ' ', ', ') AS CleanTagsString,
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS DistinctEditorsCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS ReopenEvents,
        (SELECT MAX(PH_INNER.CreationDate) FROM PostHistory PH_INNER WHERE PH_INNER.PostId = P.Id AND PH_INNER.PostHistoryTypeId IN (4, 5, 6)) AS LastEditHistoryDate
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.Body IS NOT NULL AND P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.Body, P.Title, P.Tags
),
TagPerformanceMetrics AS (
    SELECT
        tag_name.tag AS TagName,
        COUNT(DISTINCT P.Id) AS TaggedPostsCount,
        AVG(P.Score) AS AvgScorePerTag,
        AVG(P.ViewCount) AS AvgViewsPerTag,
        SUM(P.AnswerCount) AS TotalAnswersForTag
    FROM Posts P
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS tag_name(tag)
    WHERE P.Tags IS NOT NULL AND P.Tags != ''
    GROUP BY tag_name.tag
    HAVING COUNT(DISTINCT P.Id) > 100
),
AggregatedUserPostStats AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.UserCreationDate,
        UE.TotalPosts,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalComments,
        UE.TotalPostScoreReceived,
        UE.TotalUpvotesGiven,
        UE.TotalDownvotesGiven,
        UE.TotalBadges,
        COALESCE(SUM(PCA.BodyLength), 0) AS TotalBodyLength,
        COALESCE(SUM(PCA.TitleLength), 0) AS TotalTitleLength,
        COALESCE(SUM(PCA.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(PCA.DistinctEditorsCount), 0) AS TotalDistinctEditorsOnPosts,
        COALESCE(SUM(PCA.CloseEvents), 0) AS TotalCloseEvents,
        COALESCE(SUM(PCA.ReopenEvents), 0) AS TotalReopenEvents,
        AVG(PCA.PostScore) AS AvgPostScorePerUser,
        NTILE(10) OVER (ORDER BY UE.Reputation DESC) AS ReputationDecile,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM UE.UserCreationDate) ORDER BY UE.Reputation DESC) AS RankReputationByCreationYear,
        LAG(UE.Reputation, 1, 0) OVER (ORDER BY UE.CreationDate) AS PreviousUserReputation,
        FIRST_VALUE(UE.DisplayName) OVER (PARTITION BY EXTRACT(MONTH FROM UE.UserCreationDate) ORDER BY UE.Reputation DESC) AS TopUserInCreationMonth
    FROM UserEngagement UE
    LEFT JOIN PostContentAnalysis PCA ON UE.UserId = PCA.OwnerUserId
    GROUP BY UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.TotalPosts, UE.TotalQuestions, UE.TotalAnswers, UE.TotalComments,
             UE.TotalPostScoreReceived, UE.TotalUpvotesGiven, UE.TotalDownvotesGiven, UE.TotalBadges
),
ComplexPostRelationshipAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = P.Id) AS TotalCommentsOnPost,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS TotalUpvotesOnPost,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS TotalDownvotesOnPost,
        COALESCE(PL_Linked.LinkedPostCount, 0) AS LinkedPostsCount,
        COALESCE(PL_Duplicate.DuplicatePostCount, 0) AS DuplicatePostsCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserPostSeqNum,
        SUM(P.ViewCount) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS Rolling3PostViewCount,
        MIN(P.Score) OVER (PARTITION BY P.OwnerUserId) AS MinScoreByUser
    FROM Posts P
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS LinkedPostCount
        FROM PostLinks
        WHERE LinkTypeId = 1
        GROUP BY PostId
    ) AS PL_Linked ON P.Id = PL_Linked.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS DuplicatePostCount
        FROM PostLinks
        WHERE LinkTypeId = 3
        GROUP BY PostId
    ) AS PL_Duplicate ON P.Id = PL_Duplicate.PostId
    WHERE P.PostTypeId = 1
    AND P.OwnerUserId IS NOT NULL
),
UserPrimaryTag AS (
    SELECT
        P.OwnerUserId AS UserId,
        tag_name.tag AS TagName,
        COUNT(*) AS TagUsageCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(*) DESC, tag_name.tag) AS rn
    FROM Posts P
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS tag_name(tag)
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId, tag_name.tag
)
SELECT
    AUS.UserId,
    AUS.DisplayName,
    AUS.Reputation,
    AUS.TotalPosts,
    AUS.TotalQuestions,
    AUS.TotalAnswers,
    AUS.TotalComments,
    AUS.TotalPostScoreReceived,
    AUS.TotalUpvotesGiven,
    AUS.TotalDownvotesGiven,
    AUS.TotalBadges,
    AUS.TotalBodyLength,
    AUS.TotalTitleLength,
    AUS.TotalPostViews,
    AUS.TotalDistinctEditorsOnPosts,
    AUS.TotalCloseEvents,
    AUS.TotalReopenEvents,
    AUS.AvgPostScorePerUser,
    AUS.ReputationDecile,
    AUS.RankReputationByCreationYear,
    AUS.PreviousUserReputation,
    AUS.TopUserInCreationMonth,
    CPR.Title AS LatestQuestionTitle,
    CPR.PostCreationDate AS LatestQuestionDate,
    CPR.TotalCommentsOnPost AS LatestQuestionComments,
    CPR.TotalUpvotesOnPost AS LatestQuestionUpvotes,
    CPR.TotalDownvotesOnPost AS LatestQuestionDownvotes,
    CPR.LinkedPostsCount AS LatestQuestionLinkedPosts,
    CPR.DuplicatePostsCount AS LatestQuestionDuplicatePosts,
    CPR.Rolling3PostViewCount AS LatestQuestionRollingViews,
    COALESCE(TPM.AvgScorePerTag, 0.0) AS PrimaryTagAvgScore,
    COALESCE(TPM.AvgViewsPerTag, 0.0) AS PrimaryTagAvgViews,
    UPT.TagName AS PrimaryTagName,
    CASE
        WHEN AUS.TotalPosts > 0 AND AUS.Reputation > 0
        THEN CAST(AUS.Reputation AS NUMERIC) / AUS.TotalPosts
        ELSE NULL
    END AS ReputationPerPostRatio,
    (
        SELECT COUNT(DISTINCT tag_inner.tag)
        FROM Posts P_INNER
        CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P_INNER.Tags, 2, LENGTH(P_INNER.Tags)-2), '><')) AS tag_inner(tag)
        WHERE P_INNER.OwnerUserId = AUS.UserId
    ) AS DistinctTagsUsed,
    (
        SELECT AVG(PH_INNER.Id)
        FROM PostHistory PH_INNER
        WHERE PH_INNER.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = AUS.UserId)
        AND PH_INNER.PostHistoryTypeId = 5
    ) AS AvgPostHistoryIdForBodyEdits,
    COALESCE(U_Details.Location, 'Unknown') AS UserLocation,
    SUBSTRING(U_Details.AboutMe, 1, 100) AS AboutMeSnippet,
    U_Details.WebsiteUrl LIKE '%stackexchange.com%' AS HasStackExchangeWebsite,
    NULLIF(U_Details.Views, 0) AS UserProfileViews
FROM AggregatedUserPostStats AUS
LEFT JOIN ComplexPostRelationshipAnalysis CPR ON AUS.UserId = CPR.OwnerUserId AND CPR.UserPostSeqNum = 1
LEFT JOIN Users U_Details ON AUS.UserId = U_Details.Id
LEFT JOIN UserPrimaryTag UPT ON AUS.UserId = UPT.UserId AND UPT.rn = 1
LEFT JOIN TagPerformanceMetrics TPM ON UPT.TagName = TPM.TagName
WHERE
    AUS.Reputation > 1000
    AND AUS.TotalPosts > 5
    AND (AUS.TotalQuestions > 0 OR AUS.TotalAnswers > 0)
    AND AUS.UserCreationDate > '2010-01-01'
    AND U_Details.AboutMe IS NOT NULL
    AND (
        AUS.TotalCloseEvents > 0
        OR AUS.TotalReopenEvents > 0
        OR AUS.TotalDistinctEditorsOnPosts > 1
    )
ORDER BY AUS.Reputation DESC, AUS.TotalPosts DESC, AUS.UserId
LIMIT 500;
