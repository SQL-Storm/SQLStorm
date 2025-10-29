WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score ELSE NULL END) AS AvgScoreOfOwnedPosts,
        MAX(COALESCE(P.LastActivityDate, U.LastAccessDate)) AS LastKnownActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views
),
PostDetailMetrics AS (
    SELECT
        PQ.Id AS PostId,
        PQ.PostTypeId,
        PQ.Title,
        PQ.Tags,
        PQ.CreationDate AS PostCreationDate,
        PQ.Score AS PostScore,
        PQ.ViewCount,
        PQ.OwnerUserId,
        PQ.AcceptedAnswerId,
        PQ.AnswerCount AS DeclaredAnswerCount,
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostUpvoteCount,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostDownvoteCount,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditCount,
        MAX(PH.CreationDate) AS LastHistoryEditDate,
        (SELECT COUNT(DISTINCT A.Id) FROM Posts A WHERE A.ParentId = PQ.Id AND A.PostTypeId = 2) AS ActualAnswerCount,
        (SELECT AVG(A.Score) FROM Posts A WHERE A.ParentId = PQ.Id AND A.PostTypeId = 2) AS AvgScoreOfAnswers,
        CASE
            WHEN PQ.PostTypeId = 1 AND PQ.AnswerCount > 0 AND PQ.AcceptedAnswerId IS NOT NULL
            THEN CAST(COUNT(CASE WHEN PA.Id = PQ.AcceptedAnswerId THEN 1 ELSE NULL END) AS DECIMAL) / NULLIF(COUNT(PA.Id), 0)
            ELSE NULL
        END AS QuestionAcceptedAnswerRate,
        -- Standard SQL interval calculation: hours between creation and last activity (coerce to timestamp)
        EXTRACT(EPOCH FROM (COALESCE(MAX(PH.CreationDate), PQ.LastActivityDate, PQ.CreationDate) - PQ.CreationDate)) / 3600.0 AS HoursSinceCreationToLastActivity,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasEverClosed
    FROM Posts PQ
    LEFT JOIN Votes PV ON PQ.Id = PV.PostId
    LEFT JOIN PostHistory PH ON PQ.Id = PH.PostId
    LEFT JOIN Posts PA ON PQ.Id = PA.ParentId AND PA.PostTypeId = 2
    WHERE PQ.PostTypeId IN (1, 2)
    GROUP BY PQ.Id, PQ.PostTypeId, PQ.Title, PQ.Tags, PQ.CreationDate, PQ.Score, PQ.ViewCount, PQ.OwnerUserId, PQ.AcceptedAnswerId, PQ.AnswerCount, PQ.LastActivityDate
),
TagUsageAndRanking AS (
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(PD.Tags, 2, LENGTH(PD.Tags) - 2), '><'))) AS TagName,
        PD.PostId,
        PD.OwnerUserId,
        PD.PostScore,
        PD.PostCreationDate,
        PD.PostUpvoteCount,
        PD.PostDownvoteCount
    FROM PostDetailMetrics PD
    WHERE PD.PostTypeId = 1 AND PD.Tags IS NOT NULL AND LENGTH(PD.Tags) > 2
),
AggregatedTagStats AS (
    SELECT
        TU.TagName,
        COUNT(DISTINCT TU.PostId) AS QuestionsTagged,
        COUNT(DISTINCT TU.OwnerUserId) AS UniqueQuestioners,
        AVG(TU.PostScore) AS AvgQuestionScoreForTag,
        MAX(TU.PostCreationDate) AS LatestQuestionForTag,
        SUM(TU.PostUpvoteCount) AS TotalUpvotesForTag,
        SUM(TU.PostDownvoteCount) AS TotalDownvotesForTag,
        RANK() OVER (ORDER BY COUNT(DISTINCT TU.PostId) DESC, AVG(TU.PostScore) DESC) AS TagPopularityRank,
        NTILE(4) OVER (ORDER BY COUNT(DISTINCT TU.PostId) DESC) AS TagPopularityQuartile
    FROM TagUsageAndRanking TU
    GROUP BY TU.TagName
    HAVING COUNT(DISTINCT TU.PostId) >= 5
),
PostLinkInteractions AS (
    SELECT
        PostId,
        SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinksToOtherPosts,
        SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatesOtherPosts,
        0 AS LinkedByOtherPosts,
        0 AS DuplicatedByOtherPosts
    FROM PostLinks
    GROUP BY PostId
    UNION ALL
    SELECT
        RelatedPostId AS PostId,
        0 AS LinksToOtherPosts,
        0 AS DuplicatesOtherPosts,
        SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedByOtherPosts,
        SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatedByOtherPosts
    FROM PostLinks
    GROUP BY RelatedPostId
),
CombinedPostLinkSummary AS (
    SELECT
        PostId,
        SUM(LinksToOtherPosts) AS TotalLinksOut,
        SUM(DuplicatesOtherPosts) AS TotalDuplicatesOut,
        SUM(LinkedByOtherPosts) AS TotalLinksIn,
        SUM(DuplicatedByOtherPosts) AS TotalDuplicatesIn
    FROM PostLinkInteractions
    GROUP BY PostId
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.TotalPostsOwned,
    PDM.PostId,
    PDM.Title,
    PDM.PostScore,
    PDM.ViewCount,
    PDM.PostCreationDate,
    PDM.ActualAnswerCount,
    PDM.AvgScoreOfAnswers,
    PDM.QuestionAcceptedAnswerRate,
    PDM.TotalEditCount,
    PDM.HoursSinceCreationToLastActivity,
    ATS.TagName AS TopAssociatedTag,
    ATS.QuestionsTagged AS TaggedQuestionsCount,
    ATS.AvgQuestionScoreForTag AS TagAvgScore,
    ATS.TagPopularityRank,
    CPS.TotalLinksOut,
    CPS.TotalLinksIn,
    CPS.TotalDuplicatesIn,
    (UPPER(SUBSTRING(COALESCE(UES.DisplayName, 'ANONYMOUS') FROM 1 FOR 4)) || '-' ||
     LOWER(RIGHT(COALESCE(PDM.Title, 'NO TITLE POST'), 5)) || '-' ||
     LPAD(CAST(PDM.PostId AS VARCHAR), 8, '0')) AS ComputedPostHashIdentifier,
    CASE
        WHEN PDM.WasEverClosed = 1 THEN 'Closed'
        WHEN PDM.PostTypeId = 1 AND PDM.ActualAnswerCount = 0 THEN 'Unanswered'
        WHEN PDM.PostTypeId = 1 AND PDM.QuestionAcceptedAnswerRate IS NOT NULL AND PDM.QuestionAcceptedAnswerRate >= 0.7 THEN 'Highly Accepted'
        WHEN PDM.PostTypeId = 1 AND PDM.QuestionAcceptedAnswerRate IS NOT NULL AND PDM.QuestionAcceptedAnswerRate < 0.7 THEN 'Partially Accepted'
        WHEN PDM.PostTypeId = 2 AND PDM.PostScore < 0 THEN 'Negative Answer'
        ELSE 'Other'
    END AS PostStatusCategory,
    (UES.Reputation * 0.05) + (PDM.PostScore * 0.7) + (PDM.ViewCount * 0.001) +
    (COALESCE(PDM.ActualAnswerCount, 0) * 1.5) + (COALESCE(CPS.TotalLinksIn, 0) * 2.0) +
    (CASE WHEN PDM.QuestionAcceptedAnswerRate IS NOT NULL THEN PDM.QuestionAcceptedAnswerRate * 10 ELSE 0 END) AS TotalEngagementScore
FROM UserEngagementSummary UES
INNER JOIN PostDetailMetrics PDM ON UES.UserId = PDM.OwnerUserId
LEFT JOIN LATERAL (
    SELECT TagName, QuestionsTagged, AvgQuestionScoreForTag, TagPopularityRank
    FROM AggregatedTagStats ATS
    WHERE PDM.Tags LIKE '%' || '<' || ATS.TagName || '>' || '%'
    ORDER BY ATS.TagPopularityRank ASC, ATS.QuestionsTagged DESC
    LIMIT 1
) ATS ON TRUE
LEFT JOIN CombinedPostLinkSummary CPS ON PDM.PostId = CPS.PostId
WHERE
    UES.Reputation > 500
    AND PDM.PostCreationDate BETWEEN TIMESTAMP '2022-01-01' AND TIMESTAMP '2023-12-31'
    AND PDM.PostScore > 5
    AND PDM.ViewCount > 100
    AND (PDM.Title LIKE '%performance%' OR PDM.Title LIKE '%benchmark%')
    AND PDM.HoursSinceCreationToLastActivity > 24 * 7
    AND (PDM.QuestionAcceptedAnswerRate IS NULL OR PDM.QuestionAcceptedAnswerRate < 0.9)
    AND ((CPS.TotalLinksIn IS NOT NULL AND CPS.TotalLinksIn > 0) OR (CPS.TotalLinksOut IS NOT NULL AND CPS.TotalLinksOut > 0))
    AND (NOT EXISTS (SELECT 1 FROM PostHistory PH WHERE PH.PostId = PDM.PostId AND PH.PostHistoryTypeId = 12))
ORDER BY TotalEngagementScore DESC, UES.Reputation DESC, PDM.PostCreationDate DESC
LIMIT 5000;