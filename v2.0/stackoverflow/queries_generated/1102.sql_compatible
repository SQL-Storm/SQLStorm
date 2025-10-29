WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COALESCE(U.Location, 'Unspecified') AS UserLocation,
        GREATEST(0, CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) / (60 * 60 * 24) AS INT)) AS DaysSinceUserCreation,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgesCount,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadgesCount,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadgesCount,
        COUNT(B.Id) AS TotalBadges
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes, U.Location
),
PostStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title AS PostTitle,
        P.Tags AS PostTags,
        P.AcceptedAnswerId,
        P.ParentId,
        GREATEST(0, CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - P.CreationDate)) / (60 * 60 * 24) AS INT)) AS PostAgeDays,
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6) AND PH.UserId IS NOT NULL AND PH.UserId <> P.OwnerUserId) AS EditorCount,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS TotalEditEvents,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 WHEN V.VoteTypeId = 3 THEN -1 ELSE 0 END) AS TotalNetVotes,
        COUNT(DISTINCT V.UserId) FILTER (WHERE V.VoteTypeId = 5 AND V.UserId IS NOT NULL) AS UniqueFavoriters
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastEditDate,
        P.LastActivityDate, P.Title, P.Tags, P.AcceptedAnswerId, P.ParentId
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        T.TagName,
        T.Count AS TagGlobalCount,
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
            THEN array_length(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1)
            ELSE 0
        END AS NumTagsOnPost,
        RANK() OVER (ORDER BY T.Count DESC) AS TagPopularityRank
    FROM Posts AS P
    LEFT JOIN LATERAL (
        SELECT tag_name_str
        FROM unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS tag_name_str
        WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    ) AS PostTag ON TRUE
    LEFT JOIN Tags AS T ON PostTag.tag_name_str = T.TagName
    WHERE P.PostTypeId = 1
),
UserPostPerformance AS (
    SELECT
        UA.UserId,
        UA.DisplayName,
        UA.Reputation,
        UA.DaysSinceUserCreation,
        UA.GoldBadgesCount,
        UA.SilverBadgesCount,
        UA.BronzeBadgesCount,
        UA.TotalBadges,
        UA.UserLocation,
        COUNT(PS.PostId) AS TotalPostsCreated,
        SUM(CASE WHEN PS.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCreated,
        SUM(CASE WHEN PS.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCreated,
        SUM(PS.PostScore) AS TotalPostScore,
        SUM(PS.PostViewCount) AS TotalPostViews,
        SUM(PS.PostCommentCount) AS TotalPostComments,
        SUM(PS.FavoriteCount) AS TotalPostFavorites,
        SUM(PS.EditorCount) AS TotalPostEditors,
        SUM(PS.TotalEditEvents) AS TotalPostEditEvents,
        COALESCE(AVG(PS.PostScore), 0) AS AvgPostScore,
        COALESCE(AVG(PS.PostAgeDays), 0) AS AvgPostAgeDays,
        MAX(PS.PostScore) AS MaxPostScore,
        (SELECT P_top.Title FROM Posts P_top WHERE P_top.OwnerUserId = UA.UserId ORDER BY P_top.Score DESC NULLS LAST LIMIT 1) AS TopPostTitleByScore,
        EXISTS (
            SELECT 1
            FROM Posts P_inner
            WHERE P_inner.OwnerUserId = UA.UserId
              AND P_inner.Body ILIKE '%sql%'
              AND P_inner.PostTypeId IN (1, 2)
        ) AS HasSqlRelatedPost,
        AVG(UA.Reputation) OVER (PARTITION BY UA.UserLocation) AS AvgReputationInLocation,
        DENSE_RANK() OVER (ORDER BY SUM(COALESCE(PS.PostScore, 0)) DESC) AS UserScoreRank
    FROM UserActivity AS UA
    LEFT JOIN PostStats AS PS ON UA.UserId = PS.OwnerUserId
    GROUP BY
        UA.UserId, UA.DisplayName, UA.Reputation, UA.DaysSinceUserCreation,
        UA.GoldBadgesCount, UA.SilverBadgesCount, UA.BronzeBadgesCount,
        UA.TotalBadges, UA.UserLocation
),
ClosedQuestionDetails AS (
    SELECT
        PS.PostId,
        PS.PostTitle,
        PS.OwnerUserId,
        PH.CreationDate AS CloseDate,
        CR.Name AS CloseReason,
        MAX(CASE WHEN PH_reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) OVER (PARTITION BY PS.PostId) AS WasReopened
    FROM PostStats AS PS
    INNER JOIN PostHistory AS PH
        ON PS.PostId = PH.PostId
        AND PH.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes AS CR
        ON PH.Comment IS NOT NULL AND PH.Comment ~ '^[0-9]+$'
        AND CR.Id = CAST(PH.Comment AS smallint)
    LEFT JOIN PostHistory AS PH_reopen
        ON PS.PostId = PH_reopen.PostId
        AND PH_reopen.PostHistoryTypeId = 11
    WHERE PS.PostTypeId = 1
)
SELECT
    UPP.UserId,
    UPP.DisplayName,
    UPP.Reputation,
    UPP.GoldBadgesCount,
    UPP.TotalPostsCreated,
    UPP.QuestionsCreated,
    UPP.AnswersCreated,
    UPP.TotalPostScore,
    UPP.TotalPostViews,
    UPP.TotalPostComments,
    UPP.AvgPostScore,
    UPP.AvgReputationInLocation,
    UPP.UserScoreRank,
    UPP.TopPostTitleByScore,
    UPP.HasSqlRelatedPost,
    SUM(CASE WHEN TA.TagName = 'sql' THEN 1 ELSE 0 END) AS SqlTagCount,
    SUM(CASE WHEN TA.TagName = 'performance' THEN 1 ELSE 0 END) AS PerformanceTagCount,
    CAST(
        COALESCE(UPP.AvgPostScore, 0) * 0.5 +
        COALESCE(UPP.TotalPostFavorites, 0) * 0.2 +
        COALESCE(UPP.GoldBadgesCount, 0) * 10 +
        CASE WHEN UPP.HasSqlRelatedPost THEN 5 ELSE 0 END -
        CASE WHEN UPP.TotalPostEditEvents > 5 THEN UPP.TotalPostEditEvents * 0.1 ELSE 0 END
    AS NUMERIC(10, 2)) AS CalculatedQualityScore,
    (
        SELECT COALESCE(AVG(PS_inner.PostAgeDays), 0)
        FROM PostStats AS PS_inner
        LEFT JOIN LATERAL (
            SELECT tag_name_str
            FROM unnest(string_to_array(SUBSTRING(PS_inner.PostTags, 2, LENGTH(PS_inner.PostTags) - 2), '><')) AS tag_name_str
            WHERE PS_inner.PostTags IS NOT NULL AND LENGTH(PS_inner.PostTags) > 2
        ) AS PostTag_inner ON TRUE
        WHERE PS_inner.PostTypeId = 1
          AND PostTag_inner.tag_name_str = 'java'
    ) AS AvgJavaQuestionAge,
    COUNT(DISTINCT CQD.PostId) AS ClosedQuestionsByOwner,
    COUNT(DISTINCT CASE WHEN CQD.WasReopened = 1 THEN CQD.PostId END) AS ReopenedQuestionsByOwner,
    MAX(CQD.CloseReason) FILTER (WHERE CQD.CloseReason IS NOT NULL) AS SampleCloseReason,
    'Primary Analysis' AS AnalysisType
FROM UserPostPerformance AS UPP
LEFT JOIN TagAnalysis AS TA ON UPP.UserId = TA.OwnerUserId
LEFT JOIN ClosedQuestionDetails AS CQD ON UPP.UserId = CQD.OwnerUserId
WHERE
    UPP.Reputation > 1000
    AND UPP.DaysSinceUserCreation >= 365
    AND (UPP.QuestionsCreated > 5 OR UPP.AnswersCreated > 10)
    AND UPP.TotalPostsCreated IS NOT NULL
    AND NOT UPP.HasSqlRelatedPost
    AND UPP.UserLocation IS NOT NULL AND UPP.UserLocation <> 'Unspecified'
    AND COALESCE(UPP.TopPostTitleByScore, '') ILIKE '%design%'
GROUP BY
    UPP.UserId, UPP.DisplayName, UPP.Reputation, UPP.GoldBadgesCount,
    UPP.TotalPostsCreated, UPP.QuestionsCreated, UPP.AnswersCreated,
    UPP.TotalPostScore, UPP.TotalPostViews, UPP.TotalPostComments,
    UPP.AvgPostScore, UPP.AvgReputationInLocation, UPP.UserScoreRank,
    UPP.TopPostTitleByScore, UPP.HasSqlRelatedPost, UPP.TotalPostFavorites, UPP.TotalPostEditEvents
HAVING
    COUNT(DISTINCT TA.PostId) > 0
    AND (SUM(CASE WHEN TA.TagName = 'sql' THEN 1 ELSE 0 END) + SUM(CASE WHEN TA.TagName = 'performance' THEN 1 ELSE 0 END)) >= 1

UNION ALL

SELECT
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.GoldBadgesCount,
    0 AS TotalPostsCreated,
    0 AS QuestionsCreated,
    0 AS AnswersCreated,
    0 AS TotalPostScore,
    0 AS TotalPostViews,
    0 AS TotalPostComments,
    0 AS AvgPostScore,
    AVG(UA.Reputation) OVER (PARTITION BY UA.UserLocation) AS AvgReputationInLocation,
    DENSE_RANK() OVER (ORDER BY UA.Reputation DESC, UA.LastAccessDate DESC) AS UserScoreRank,
    NULL AS TopPostTitleByScore,
    FALSE AS HasSqlRelatedPost,
    0 AS SqlTagCount,
    0 AS PerformanceTagCount,
    CAST(
        COALESCE(UA.Reputation, 0) * 0.1 + COALESCE(UA.GoldBadgesCount, 0) * 5 +
        CASE WHEN UA.DaysSinceUserCreation < 365 THEN 20 ELSE 0 END
    AS NUMERIC(10, 2)) AS CalculatedQualityScore,
    0 AS AvgJavaQuestionAge,
    0 AS ClosedQuestionsByOwner,
    0 AS ReopenedQuestionsByOwner,
    NULL AS SampleCloseReason,
    'Recent High Rep User Analysis' AS AnalysisType
FROM UserActivity AS UA
WHERE
    UA.Reputation > 5000
    AND UA.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
    AND UA.TotalBadges > 0
    AND UA.UserLocation IS NOT NULL
GROUP BY
    UA.UserId, UA.DisplayName, UA.Reputation, UA.GoldBadgesCount,
    UA.UserLocation, UA.TotalBadges, UA.LastAccessDate, UA.DaysSinceUserCreation
ORDER BY
    CalculatedQualityScore DESC, Reputation DESC
LIMIT 200;