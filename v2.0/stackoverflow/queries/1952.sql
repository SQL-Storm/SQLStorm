WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LastActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
    LEFT JOIN Comments C ON U.Id = C.UserId AND C.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0
),
PostHistoricalMetrics AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditHistoryDate,
        (SELECT PH_inner.Comment
         FROM PostHistory PH_inner
         WHERE PH_inner.PostId = PH.PostId
           AND PH_inner.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
         ORDER BY PH_inner.CreationDate DESC
         LIMIT 1) AS LatestCloseReasonComment
    FROM PostHistory PH
    GROUP BY PH.PostId
),
GlobalTagPerformance AS (
    SELECT
        TagName,
        SUM(QuestionCount) AS TotalQuestionsWithTag,
        SUM(TotalScore) AS SumScoreForTag,
        AVG(AverageScore) AS AvgScoreForTag,
        SUM(TotalViews) AS SumViewsForTag
    FROM (
        SELECT
            tag AS TagName,
            COUNT(P.Id) AS QuestionCount,
            SUM(P.Score) AS TotalScore,
            AVG(CAST(P.Score AS NUMERIC)) AS AverageScore,
            SUM(P.ViewCount) AS TotalViews
        FROM Posts P
        JOIN LATERAL (
               SELECT TRIM(REGEXP_SUBSTR(val, '^([^<>]+)$')) AS tag
               FROM (
                   SELECT
                     CASE
                       WHEN idx = 1 THEN SUBSTR(P.Tags, 2, COALESCE(NULLIF(STRPOS(SUBSTR(P.Tags, 2), '><'),0)-1, LENGTH(P.Tags)-2))
                       ELSE SUBSTR(P.Tags, start_pos, COALESCE(NULLIF(STRPOS(SUBSTR(P.Tags, start_pos), '><'),0)-1, LENGTH(P.Tags)-start_pos+1))
                     END AS val
                   FROM (
                     WITH RECURSIVE seq(idx, start_pos, rest) AS (
                       SELECT 1, 2, SUBSTR(P.Tags, 2)
                       UNION ALL
                       SELECT idx+1,
                              idx_start + 2,
                              SUBSTR(rest, idx_start + 2)
                       FROM (
                         SELECT
                           idx,
                           start_pos,
                           rest,
                           NULLIF(STRPOS(rest, '><'), 0) AS idx_start
                         FROM seq
                       ) s
                       WHERE STRPOS(rest, '><') > 0
                     )
                     SELECT
                       idx,
                       start_pos,
                       rest
                     FROM seq
                   ) parts
               ) substrs(val)
             ) tags_split ON TRUE
        WHERE P.PostTypeId = 1
          AND P.Tags IS NOT NULL
          AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
        GROUP BY tag
        UNION ALL
        SELECT
            T.TagName,
            0 AS QuestionCount,
            0 AS TotalScore,
            0.0 AS AverageScore,
            0 AS TotalViews
        FROM Tags T
        WHERE T.Count > 0
    ) AS CombinedTagData
    GROUP BY TagName
    HAVING SUM(QuestionCount) > 0
),
PostActivitySummary AS (
    SELECT
        P.Id AS PostId,
        P.CreationDate AS ActivityDate,
        'POST_CREATED' AS ActivityType,
        P.OwnerUserId AS InitiatorUserId
    FROM Posts P WHERE P.PostTypeId IN (1,2)
    UNION ALL
    SELECT
        C.PostId AS PostId,
        C.CreationDate AS ActivityDate,
        'COMMENT_ADDED' AS ActivityType,
        C.UserId AS InitiatorUserId
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    UNION ALL
    SELECT
        PH.PostId AS PostId,
        PH.CreationDate AS ActivityDate,
        'POST_EDITED' AS ActivityType,
        PH.UserId AS InitiatorUserId
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId IS NOT NULL
    UNION ALL
    SELECT
        V.PostId AS PostId,
        V.CreationDate AS ActivityDate,
        CASE
            WHEN V.VoteTypeId = 2 THEN 'UPVOTED'
            WHEN V.VoteTypeId = 3 THEN 'DOWNVOTED'
            WHEN V.VoteTypeId = 1 THEN 'ACCEPTED_ANSWER'
            ELSE 'OTHER_VOTE'
        END AS ActivityType,
        V.UserId AS InitiatorUserId
    FROM Votes V
    WHERE V.VoteTypeId IN (1,2,3) AND V.UserId IS NOT NULL
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.TotalComments,
    UE.TotalPostScore,
    UE.TotalCommentScore,
    UE.LastActivity,
    P.Id AS PostId,
    PT.Name AS PostTypeName,
    P.Title,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    P.AnswerCount AS PostAnswerCount,
    P.FavoriteCount AS PostFavoriteCount,
    P.CreationDate AS PostCreationDate,
    P.LastEditDate AS PostLastEditDate,
    P.ClosedDate AS PostClosedDate,
    PHM.EditCount,
    PHM.WasClosed,
    PHM.WasReopened,
    PHM.LastEditHistoryDate,
    PHM.LatestCloseReasonComment,
    B.GoldBadges,
    B.SilverBadges,
    B.BronzeBadges,
    (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvoteCountForPost,
    COALESCE(P.OwnerDisplayName, 'Community User') AS PostOwnerDisplayName,
    (CAST(P.Score AS NUMERIC) * 0.75 +
     COALESCE(P.ViewCount, 0) * 0.05 +
     COALESCE(P.AnswerCount, 0) * 1.5 +
     COALESCE(P.FavoriteCount, 0) * 2.0 +
     COALESCE(PHM.EditCount, 0) * 0.1 +
     (SELECT COUNT(*) FROM PostActivitySummary PAS WHERE PAS.PostId = P.Id AND PAS.ActivityType = 'COMMENT_ADDED') * 0.5
    ) AS CalculatedPostImpactScore,
    SUBSTRING(COALESCE(P.Body, ''), 1, 100) || CASE WHEN LENGTH(COALESCE(P.Body, '')) > 100 THEN '...' ELSE '' END AS PostBodySnippet,
    TRIM(REGEXP_REPLACE(P.Title, '[^a-zA-Z0-9\\s]', '', 'g')) AS CleanedPostTitle,
    ROW_NUMBER() OVER (PARTITION BY UE.UserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostRankByUserType,
    AVG(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score ELSE NULL END) OVER (PARTITION BY UE.UserId) AS AvgRelevantPostScoreByUser,
    SUM(CASE WHEN P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN P.Score ELSE 0 END) OVER (PARTITION BY UE.UserId ORDER BY P.CreationDate ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeRecentUserPostScore,
    CASE
        WHEN UE.Reputation >= 10000 AND COALESCE(B.GoldBadges, 0) >= 1 THEN 'Elite Contributor'
        WHEN UE.Reputation >= 5000 AND COALESCE(B.SilverBadges, 0) >= 2 THEN 'Veteran'
        WHEN UE.Reputation >= 1000 THEN 'Established'
        ELSE 'Novice/Contributor'
    END AS UserReputationTier,
    COALESCE(GTP.SumScoreForTag, 0) AS PrimaryTagTotalScore,
    COALESCE(GTP.TotalQuestionsWithTag, 0) AS PrimaryTagQuestionCount,
    CAST(COALESCE(P.AnswerCount, 0) AS NUMERIC) / NULLIF(P.ViewCount, 0) AS AnswerConversionRate,
    (SELECT COUNT(DISTINCT V_inner.UserId) FROM Votes V_inner WHERE V_inner.PostId = P.Id AND V_inner.UserId IS NOT NULL) AS DistinctVotersCount
FROM UserEngagement UE
INNER JOIN Posts P ON UE.UserId = P.OwnerUserId
INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN PostHistoricalMetrics PHM ON P.Id = PHM.PostId
LEFT JOIN (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) B ON UE.UserId = B.UserId
LEFT JOIN LATERAL (
    SELECT
        GT.TagName,
        GT.TotalQuestionsWithTag,
        GT.SumScoreForTag,
        GT.AvgScoreForTag,
        GT.SumViewsForTag
    FROM GlobalTagPerformance GT
    WHERE GT.TagName = TRIM(SPLIT_PART(SUBSTRING(P.Tags FROM 2 FOR CHAR_LENGTH(P.Tags)-2), '><', 1))
    LIMIT 1
) GTP ON P.Tags IS NOT NULL AND CHAR_LENGTH(P.Tags) > 2
WHERE P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
  AND P.PostTypeId IN (1, 2)
  AND P.Score >= (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1,2) AND CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year'))
  AND (P.FavoriteCount IS NULL OR P.FavoriteCount > 0)
  AND (P.Title LIKE '%SQL%' OR P.Title LIKE '%database%' OR P.Title LIKE '%performance%')
  AND CHAR_LENGTH(COALESCE(P.Body, '')) > 50
ORDER BY
    UE.Reputation DESC,
    CalculatedPostImpactScore DESC,
    UE.LastActivity DESC
LIMIT 2000;