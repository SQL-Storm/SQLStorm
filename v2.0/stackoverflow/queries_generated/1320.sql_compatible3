WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionsAsked,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswersPosted,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(AVG(P.Score) FILTER (WHERE P.Score IS NOT NULL), 0.0) AS AvgPostScore,
        COALESCE(AVG(C.Score) FILTER (WHERE C.Score IS NOT NULL), 0.0) AS AvgCommentScore,
        RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC) AS PostCountRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostsWithTagsExploded AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.PostTypeId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Body,
        P.Tags,
        TRIM(BOTH '<>' FROM Tag.TagName) AS TagName
    FROM Posts P
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS TagName
    ) AS Tag
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.OwnerUserId IS NOT NULL
),
PostSequenceAndBadgeCheck AS (
    SELECT
        PWT.PostId,
        PWT.OwnerUserId,
        PWT.PostCreationDate,
        PWT.PostTypeId,
        PWT.PostScore,
        PWT.ViewCount,
        PWT.AcceptedAnswerId,
        PWT.ParentId,
        PWT.TagName,
        PWT.Title,
        PWT.Body,
        ROW_NUMBER() OVER (PARTITION BY PWT.OwnerUserId ORDER BY PWT.PostCreationDate DESC, PWT.PostId DESC) AS UserPostSeqNum,
        EXISTS (
            SELECT 1
            FROM Badges B
            WHERE B.UserId = PWT.OwnerUserId
              AND B.Class = 1
              AND B.TagBased = TRUE
              AND B.Name = PWT.TagName
        ) AS HasGoldBadgeForTag
    FROM PostsWithTagsExploded PWT
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS LastEditHistoryDate,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 10) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment ELSE NULL END) AS LastCloseReasonId,
        STRING_AGG(DISTINCT PH.Comment, ' || ') FILTER (WHERE PH.PostHistoryTypeId IN (33, 34)) AS PostNoticesComments
    FROM PostHistory PH
    GROUP BY PH.PostId
),
QuestionAnswerChain AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.Title AS QuestionTitle,
        Q.Tags AS QuestionTags,
        A.Id AS AcceptedAnswerId,
        A.OwnerUserId AS AcceptedAnswerOwnerId,
        A.CreationDate AS AcceptedAnswerCreationDate,
        A.Score AS AcceptedAnswerScore,
        LENGTH(A.Body) AS AcceptedAnswerBodyLength,
        U_A.DisplayName AS AcceptedAnswerOwnerDisplayName
    FROM Posts Q
    INNER JOIN Posts A ON Q.AcceptedAnswerId = A.Id
    INNER JOIN Users U_A ON A.OwnerUserId = U_A.Id
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ReputationRank,
    UAS.TotalQuestionsAsked,
    UAS.TotalAnswersPosted,
    UAS.AvgPostScore,
    PSA.PostId,
    PSA.PostCreationDate,
    PSA.PostScore,
    PSA.ViewCount,
    PSA.TagName,
    PSA.HasGoldBadgeForTag,
    PHA.EditCount AS PostEditCount,
    PHA.LastClosedDate,
    CR.Name AS LastCloseReasonName,
    QAC.AcceptedAnswerOwnerDisplayName,
    QAC.AcceptedAnswerScore,
    QAC.AcceptedAnswerBodyLength,
    (PSA.PostScore * 10.0) + (PSA.ViewCount * 0.5) + (COALESCE(QAC.AcceptedAnswerScore, 0) * 5.0) AS PostEngagementScore,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - COALESCE(PHA.LastEditHistoryDate, PSA.PostCreationDate))) AS DaysSinceLastEditOrCreation,
    COALESCE(PHA.PostNoticesComments, 'No specific notices') AS PostNoticesDetails,
    CASE
        WHEN PSA.PostTypeId = 1 AND PSA.ViewCount > 1000 AND PSA.PostScore > 50 AND QAC.AcceptedAnswerId IS NOT NULL THEN 'High-Impact & Solved Question'
        WHEN PSA.PostTypeId = 2 AND PSA.PostScore > 20 AND PSA.ParentId IS NOT NULL AND LENGTH(PSA.Body) > 500 THEN 'Comprehensive Valuable Answer'
        WHEN PSA.HasGoldBadgeForTag THEN 'Expert Contribution in Tag'
        ELSE 'General Contribution'
    END AS ContributionCategory,
    CAST(UAS.TotalQuestionsAsked AS NUMERIC) / NULLIF(UAS.TotalPostsCreated, 0) * 100 AS QuestionPostRatio,
    EXTRACT(DAY FROM (PSA.PostCreationDate - LAG(PSA.PostCreationDate, 1, UAS.UserCreationDate) OVER (PARTITION BY UAS.UserId ORDER BY PSA.PostCreationDate))) AS DaysSincePreviousPost,
    COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS PostUpvoteCount,
    COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS PostDownvoteCount,
    COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 5) AS PostFavoriteCount
FROM UserActivitySummary UAS
INNER JOIN PostSequenceAndBadgeCheck PSA ON UAS.UserId = PSA.OwnerUserId
LEFT JOIN PostHistoryAggregates PHA ON PSA.PostId = PHA.PostId
LEFT JOIN CloseReasonTypes CR ON PHA.LastCloseReasonId IS NOT NULL AND CR.Id = CAST(PHA.LastCloseReasonId AS SMALLINT)
LEFT JOIN QuestionAnswerChain QAC ON PSA.PostId = QAC.QuestionId
LEFT JOIN Votes V ON PSA.PostId = V.PostId
WHERE
    UAS.Reputation > 5000
    AND PSA.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
    AND PSA.UserPostSeqNum <= 10
    AND (
        (PSA.TagName LIKE 'java%' OR PSA.TagName LIKE 'python%' OR PSA.TagName LIKE '%sql%')
        OR
        (PSA.PostScore >= 10 AND PSA.ViewCount >= 500)
    )
    AND (PSA.PostScore >= 5 OR QAC.AcceptedAnswerId IS NOT NULL OR PSA.HasGoldBadgeForTag)
    AND PSA.PostTypeId IN (1, 2)
    AND (
        (UAS.TotalCommentsMade = 0 AND UAS.TotalPostsCreated > 50)
        OR
        (UAS.DisplayName LIKE 'A%' AND UAS.Reputation > 10000)
    )
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.ReputationRank, UAS.TotalQuestionsAsked, UAS.TotalAnswersPosted, UAS.AvgPostScore,
    PSA.PostId, PSA.PostCreationDate, PSA.PostScore, PSA.ViewCount, PSA.TagName, PSA.HasGoldBadgeForTag, PSA.PostTypeId, PSA.ParentId,
    PHA.EditCount, PHA.LastEditHistoryDate, PHA.LastClosedDate, PHA.LastCloseReasonId, PHA.PostNoticesComments,
    CR.Name,
    QAC.AcceptedAnswerOwnerDisplayName, QAC.AcceptedAnswerScore, QAC.AcceptedAnswerBodyLength,
    PSA.Title, PSA.Body, UAS.TotalPostsCreated, UAS.TotalCommentsMade, UAS.UserCreationDate, QAC.AcceptedAnswerId
ORDER BY
    UAS.ReputationRank ASC, PSA.PostCreationDate DESC, PSA.PostId ASC
LIMIT 5000;