WITH ImportantPostsBase AS (
    SELECT
        Id,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        Title,
        Tags,
        AnswerCount,
        FavoriteCount,
        ClosedDate
    FROM Posts
    WHERE PostTypeId = 1
      AND ViewCount > 50000
      AND FavoriteCount IS NOT NULL
      AND FavoriteCount >= 5
    UNION ALL
    SELECT
        Id,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        NULL AS Title,
        NULL AS Tags,
        NULL AS AnswerCount,
        FavoriteCount,
        ClosedDate
    FROM Posts
    WHERE PostTypeId = 2
      AND Score > 100
      AND AcceptedAnswerId IS NOT NULL
),
UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        COUNT(DISTINCT IPB.Id) FILTER (WHERE IPB.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT IPB.Id) FILTER (WHERE IPB.PostTypeId = 2) AS AnswerCount,
        SUM(IPB.Score) AS TotalPostScore,
        AVG(CASE WHEN IPB.PostTypeId = 1 THEN IPB.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(IPB.CreationDate) AS LastPostActivityDate,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        DATE_PART('year', U.CreationDate) AS UserCreationYear,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.UserId = U.Id AND C.CreationDate > U.LastAccessDate - INTERVAL '60 days') AS RecentCommentCount,
        SUM(IPB.Score) / NULLIF(COUNT(DISTINCT IPB.Id), 0) AS AvgScorePerContribution
    FROM Users U
    LEFT JOIN ImportantPostsBase IPB ON U.Id = IPB.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Location
    HAVING COUNT(DISTINCT IPB.Id) > 0
       AND U.Reputation > 500
),
PostRevisionMetrics AS (
    SELECT
        IPB.Id AS PostId,
        IPB.PostTypeId,
        IPB.CreationDate AS PostCreationDate,
        IPB.Score AS PostScore,
        IPB.ViewCount AS PostViewCount,
        IPB.AnswerCount,
        IPB.FavoriteCount,
        IPB.OwnerUserId,
        COALESCE(IPB.Title, 'No Title (Answer)') AS PostTitle,
        IPB.Tags,
        COALESCE(IPB.ClosedDate IS NOT NULL, FALSE) AS IsClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditDate,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS FirstEditDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS EditRevisionCount,
        ARRAY_AGG(DISTINCT SUBSTRING(PH.Text FROM 1 FOR 100)) FILTER (WHERE PH.PostHistoryTypeId = 5 AND PH.Text IS NOT NULL) AS RecentBodyChanges,
        (SELECT MAX(V.CreationDate) FROM Votes V WHERE V.PostId = IPB.Id AND V.VoteTypeId = 2 AND V.CreationDate < CAST('2024-10-01 12:34:56' AS timestamp)) AS LastUpvoteDate
    FROM ImportantPostsBase IPB
    LEFT JOIN PostHistory PH ON IPB.Id = PH.PostId
    GROUP BY IPB.Id, IPB.PostTypeId, IPB.CreationDate, IPB.Score, IPB.ViewCount, IPB.AnswerCount, IPB.FavoriteCount, IPB.OwnerUserId, IPB.Title, IPB.Tags, IPB.ClosedDate
    HAVING SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) > 0
),
TagAnalysis AS (
    SELECT
        PRM.PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(PRM.Tags FROM 2 FOR LENGTH(PRM.Tags) - 2), '><'))) AS TagName
    FROM PostRevisionMetrics PRM
    WHERE PRM.Tags IS NOT NULL AND LENGTH(PRM.Tags) > 2 AND PRM.PostTypeId = 1
),
PostCommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS CommentCount,
        AVG(C.Score) AS AverageCommentScore,
        MAX(C.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT C.UserId) AS DistinctCommenters,
        SUM(CASE WHEN C.Text ILIKE '%thank%' OR C.Text ILIKE '%useful%' OR C.Text ILIKE '%great%' THEN 1 ELSE 0 END) AS PositiveSentimentComments
    FROM Comments C
    GROUP BY C.PostId
)
SELECT
    UE.UserId,
    UE.UserName,
    UE.Reputation,
    UE.UserLocation,
    UE.QuestionCount,
    UE.AnswerCount AS UserAnswerCount,
    UE.AvgScorePerContribution,
    PRM.PostId,
    PRM.PostTypeId,
    PRM.PostTitle,
    PRM.PostScore,
    PRM.PostViewCount,
    PRM.AnswerCount AS QuestionAnswerCount,
    PRM.FavoriteCount,
    PRM.IsClosed,
    PRM.PostCreationDate,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PRM.PostCreationDate)) AS DaysSincePostCreation,
    COALESCE(EXTRACT(HOUR FROM (PRM.LastEditDate - PRM.FirstEditDate)), 0) AS HoursBetweenFirstAndLastEdit,
    PRM.EditRevisionCount,
    PCS.CommentCount,
    PCS.AverageCommentScore,
    PCS.DistinctCommenters,
    PCS.PositiveSentimentComments,
    ARRAY_TO_STRING(PRM.RecentBodyChanges, ' ||| ') AS CombinedRecentBodyChanges,
    STRING_AGG(DISTINCT TA.TagName, ', ') AS RelatedTags,
    FIRST_VALUE(PRM.PostTitle) OVER (PARTITION BY UE.UserCreationYear ORDER BY PRM.PostScore DESC, PRM.PostViewCount DESC) AS TopPostInCreationYearByScoreViews,
    DENSE_RANK() OVER (PARTITION BY UE.UserCreationYear ORDER BY UE.Reputation DESC) AS UserReputationRankInYear,
    AVG(PRM.PostScore) OVER (PARTITION BY PRM.PostTypeId) AS AvgScoreForPostType,
    (
        SELECT AVG(P_INNER.Score)
        FROM Posts P_INNER
        WHERE P_INNER.OwnerUserId = UE.UserId
          AND P_INNER.Id != PRM.PostId
          AND P_INNER.PostTypeId = PRM.PostTypeId
          AND P_INNER.CreationDate < PRM.PostCreationDate
    ) AS AvgOtherPriorPostScoreByOwner,
    CASE
        WHEN PRM.PostScore >= 200 AND PRM.EditRevisionCount >= 5 AND PCS.CommentCount >= 15 THEN 'Highly Engaged & Evolved'
        WHEN PRM.PostScore >= 75 AND PRM.EditRevisionCount >= 2 AND PCS.CommentCount >= 5 THEN 'Moderately Engaged'
        ELSE 'Lower Engagement'
    END AS EngagementCategory,
    PRM.LastUpvoteDate,
    (
        SELECT
            CASE
                WHEN EXISTS (SELECT 1 FROM Badges B_INNER WHERE B_INNER.UserId = UE.UserId AND B_INNER.Name ILIKE '%Pundit%' AND B_INNER.Date < PRM.PostCreationDate) THEN 'Pundit Badge Before Post'
                WHEN EXISTS (SELECT 1 FROM Badges B_INNER WHERE B_INNER.UserId = UE.UserId AND B_INNER.Name ILIKE '%Editor%' AND B_INNER.Date < COALESCE(PRM.LastEditDate, PRM.PostCreationDate)) THEN 'Editor Badge Before Last Edit'
                ELSE 'No Relevant Badge Found'
            END
    ) AS OwnerBadgeStatusAtPostContext,
    (PRM.PostScore * 0.5 + PRM.PostViewCount * 0.01 + COALESCE(PRM.FavoriteCount, 0) * 2 + COALESCE(PCS.CommentCount, 0) * 0.8) / NULLIF(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PRM.PostCreationDate)), 0.1) AS PostImpactScoreDaily
FROM UserEngagement UE
INNER JOIN PostRevisionMetrics PRM ON UE.UserId = PRM.OwnerUserId
LEFT JOIN PostCommentSummary PCS ON PRM.PostId = PCS.PostId
LEFT JOIN TagAnalysis TA ON PRM.PostId = TA.PostId
WHERE
    PRM.PostViewCount > 5000
    AND PRM.PostScore > (SELECT AVG(P_SUB.Score) FROM Posts P_SUB WHERE P_SUB.PostTypeId = PRM.PostTypeId AND P_SUB.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    AND (
        (UE.GoldBadges > 0 AND UE.Reputation > 20000)
        OR (PRM.FavoriteCount IS NOT NULL AND PRM.FavoriteCount > 20)
        OR (PCS.DistinctCommenters > 5 AND PCS.AverageCommentScore > 1.5)
        OR (PRM.PostTypeId = 2 AND PRM.AnswerCount IS NULL AND UE.AnswerCount > 0 AND PRM.PostScore > 150)
    )
GROUP BY
    UE.UserId, UE.UserName, UE.Reputation, UE.UserLocation, UE.QuestionCount, UE.AnswerCount, UE.AvgScorePerContribution, UE.UserCreationYear,
    PRM.PostId, PRM.PostTypeId, PRM.PostTitle, PRM.PostScore, PRM.PostViewCount, PRM.AnswerCount, PRM.FavoriteCount, PRM.IsClosed,
    PRM.PostCreationDate, PRM.LastEditDate, PRM.FirstEditDate, PRM.EditRevisionCount,
    PCS.CommentCount, PCS.AverageCommentScore, PCS.DistinctCommenters, PCS.PositiveSentimentComments,
    PRM.RecentBodyChanges, PRM.LastUpvoteDate
ORDER BY
    UE.Reputation DESC, PRM.PostScore DESC, PostImpactScoreDaily DESC
LIMIT 200;