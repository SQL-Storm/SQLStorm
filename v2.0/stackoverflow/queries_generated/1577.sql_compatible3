WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPostsWritten,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        MAX(P.LastActivityDate) AS LatestPostActivityDate,
        RANK() OVER (ORDER BY U.Reputation DESC, COUNT(P.Id) DESC) AS ReputationActivityRank
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.Reputation > 5000
      AND U.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
      AND U.Views > 100
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(P.Id) >= 10
),
PostRevisionAndInteraction AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Title,
        P.Body,
        P.Tags,
        P.Score,
        P.ViewCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastEditDate,
        P.ClosedDate,
        COALESCE(P.AnswerCount, 0) AS DirectAnswerCount,
        COUNT(DISTINCT PH.Id) AS RevisionHistoryCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.Id END) AS ContentEditCount,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COALESCE(AVG(C.Score), 0.0) AS AvgCommentScore,
        COUNT(C.Id) AS CommentCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        STRING_AGG(DISTINCT SUBSTRING(T.TagName FROM 1 FOR 30), ',') AS AssociatedTagNames
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Tags T ON P.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 years')
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Title, P.Body, P.Tags, P.Score, P.ViewCount,
             P.FavoriteCount, P.OwnerUserId, P.AcceptedAnswerId, P.ParentId, P.LastEditDate, P.ClosedDate, P.AnswerCount
    HAVING COUNT(P.Id) > 0
),
TagPerformanceMetrics AS (
    SELECT
        TRIM(LOWER(t.value)) AS TagName,
        COUNT(P.Id) AS PostsPerTag,
        SUM(P.Score) AS TotalScorePerTag,
        AVG(P.ViewCount) AS AvgViewCountPerTag,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY P.Score) AS MedianScorePerTag
    FROM Posts P,
         UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR CHAR_LENGTH(P.Tags) - 2), '><')) AS t(value)
    WHERE P.PostTypeId = 1
      AND P.Tags IS NOT NULL
      AND P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 years')
    GROUP BY TRIM(LOWER(t.value))
    HAVING COUNT(P.Id) > 50
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPostsWritten,
    PRI.PostId,
    PRI.Title,
    PRI.PostCreationDate,
    PRI.Score AS PostScore,
    PRI.ViewCount,
    PRI.FavoriteCount,
    PRI.RevisionHistoryCount,
    PRI.ContentEditCount,
    PRI.CommentCount,
    PRI.TotalCommentScore,
    PRI.AssociatedTagNames,
    AVG(PRI.Score) OVER (PARTITION BY UAS.UserId ORDER BY PRI.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserMovingAvgPostScore,
    (
        SELECT MAX(AnsUser.Reputation)
        FROM Posts Ans
        JOIN Users AnsUser ON Ans.OwnerUserId = AnsUser.Id
        WHERE Ans.ParentId = PRI.PostId AND PRI.PostTypeId = 1
    ) AS MaxAnswererReputation,
    CAST(ROUND(
        (
            (PRI.Score * 0.5 + PRI.TotalCommentScore * 0.2 + PRI.FavoriteCount * 0.3) *
            (LOG(GREATEST(PRI.ViewCount, 1)) / LOG(10) + LOG(GREATEST(PRI.RevisionHistoryCount, 1)) / LOG(5)) *
            (CASE WHEN PRI.AcceptedAnswerId IS NOT NULL THEN 1.5 ELSE 1.0 END) *
            (1 + (PRI.ContentEditCount / GREATEST(PRI.RevisionHistoryCount, 1.0)) * 0.5)
        )
    , 3) AS DOUBLE PRECISION) AS CalculatedEngagementFactor,
    COALESCE(
        SUBSTRING(PRI.Tags FROM 2 FOR (POSITION('><' IN PRI.Tags) - 2)),
        SUBSTRING(PRI.Tags FROM 2 FOR (CHAR_LENGTH(PRI.Tags) - 2))
    ) AS PrimaryTag,
    TPM.AvgViewCountPerTag AS PrimaryTagAvgViewCount,
    TPM.MedianScorePerTag AS PrimaryTagMedianScore,
    CASE
        WHEN PRI.ClosedDate IS NOT NULL AND PRI.LastClosedDate < PRI.PostCreationDate + INTERVAL '30 days' THEN 'Closed_Early'
        WHEN PRI.AcceptedAnswerId IS NOT NULL AND PRI.DirectAnswerCount > 0 THEN 'Answered_Accepted'
        WHEN PRI.DirectAnswerCount > 0 AND PRI.AcceptedAnswerId IS NULL THEN 'Answered_Unaccepted'
        WHEN PRI.RevisionHistoryCount > 5 AND PRI.CommentCount > 5 THEN 'Highly_Discussed_Revised'
        WHEN PRI.ViewCount > 1000 AND PRI.Score < 0 THEN 'High_Views_Low_Score'
        ELSE 'Active_Unresolved'
    END AS PostStatusClassification,
    AA.Score AS AcceptedAnswerScore,
    AA.OwnerUserId AS AcceptedAnswerOwnerId,
    AA.CreationDate AS AcceptedAnswerCreationDate,
    COALESCE(ParentQ.Title, LinkedP.Title) AS RelatedPostTitle,
    COALESCE(ParentQ.Score, LinkedP.Score) AS RelatedPostScore
FROM UserActivitySummary UAS
INNER JOIN PostRevisionAndInteraction PRI ON UAS.UserId = PRI.OwnerUserId
LEFT JOIN Posts AA ON PRI.AcceptedAnswerId = AA.Id AND PRI.PostTypeId = 1
LEFT JOIN TagPerformanceMetrics TPM ON TRIM(LOWER(
    COALESCE(
        SUBSTRING(PRI.Tags FROM 2 FOR (POSITION('><' IN PRI.Tags) - 2)),
        SUBSTRING(PRI.Tags FROM 2 FOR (CHAR_LENGTH(PRI.Tags) - 2))
    )
)) = TPM.TagName
LEFT JOIN Posts ParentQ ON PRI.PostTypeId = 2 AND PRI.ParentId = ParentQ.Id
LEFT JOIN PostLinks PL ON PRI.PostTypeId = 1 AND PRI.PostId = PL.PostId AND PL.LinkTypeId = 1
LEFT JOIN Posts LinkedP ON PL.RelatedPostId = LinkedP.Id
WHERE PRI.RevisionHistoryCount > 1
  AND PRI.ViewCount > 50
  AND UAS.ReputationActivityRank <= 1000
  AND (PRI.ClosedDate IS NULL OR PRI.ClosedDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'))
  AND PRI.Title IS NOT NULL
  AND (
       PRI.Title LIKE '%[sql]%'
       OR PRI.Tags LIKE '%<sql>%'
  )
ORDER BY CalculatedEngagementFactor DESC, UAS.Reputation DESC, PRI.PostCreationDate DESC
LIMIT 5000;