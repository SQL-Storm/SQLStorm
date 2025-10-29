WITH UserSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotesGiven,
        U.DownVotes AS UserTotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(U.WebsiteUrl, 'N/A') AS UserWebsiteUrl,
        LENGTH(U.AboutMe) AS AboutMeLength
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.WebsiteUrl, U.AboutMe
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.Tags,
        CAST(P.Score * 0.6 + COALESCE(P.FavoriteCount, 0) * 0.2 + P.CommentCount * 0.1 + COALESCE(P.AnswerCount, 0) * 0.1 AS NUMERIC) AS PostImpactScore,
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN
                (
                    SELECT ARRAY_AGG(TRIM(s))
                    FROM (
                        SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')) AS s
                    ) sub
                )
            ELSE ARRAY[]::varchar[]
        END AS TagArray,
        (P.Score > 50 AND P.ViewCount > 10000 AND P.AnswerCount > 5 AND P.FavoriteCount IS NOT NULL) AS IsHighlyEngaged,
        EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - P.LastActivityDate)) AS DaysSinceLastActivity
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2)
),
UserBadgeStats AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(CASE WHEN B.Class = 1 THEN B.Date END) AS LatestGoldBadgeAwardDate,
        RANK() OVER (ORDER BY COUNT(B.Id) DESC, B.UserId ASC) AS OverallBadgeRank
    FROM Badges B
    GROUP BY B.UserId
),
PostHistoricalChanges AS (
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.CreationDate AS HistoryEventDate,
        EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) / 3600.0 AS HoursSincePrevHistory,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalEditEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalCloseEvents,
        REPLACE(COALESCE(PH.Comment, 'No_comment_provided'), ' ', '_') AS FormattedComment
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 11, 12, 13, 35, 36)
),
GlobalPostAverages AS (
    SELECT
        AVG(Score) AS AvgScore,
        AVG(ViewCount) AS AvgViewCount,
        AVG(PostImpactScore) AS AvgPostImpactScore,
        COUNT(DISTINCT PostId) AS TotalIndexedPosts
    FROM PostDetailedMetrics
),
UserTopPosts AS (
    SELECT
        PDM.PostId,
        PDM.OwnerUserId,
        PDM.PostTypeId,
        PDM.PostTypeName,
        PDM.Title,
        PDM.PostImpactScore,
        PDM.Score,
        PDM.ViewCount,
        PDM.AnswerCount,
        PDM.CommentCount,
        PDM.FavoriteCount,
        PDM.PostCreationDate,
        PDM.LastEditDate,
        PDM.DaysSinceLastActivity,
        PDM.TagArray,
        PDM.IsHighlyEngaged,
        PDM.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY PDM.OwnerUserId, PDM.PostTypeId ORDER BY PDM.PostImpactScore DESC, PDM.PostCreationDate DESC) AS rn_post_type_impact
    FROM PostDetailedMetrics PDM
)

SELECT
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.TotalQuestionsPosted,
    US.TotalAnswersPosted,
    US.TotalPostScoreReceived,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    TP.PostId AS TopPostId,
    TP.PostTypeName AS TopPostType,
    TP.Title AS TopPostTitle,
    TP.PostImpactScore AS TopPostCalculatedImpact,
    TP.Score AS TopPostScore,
    TP.ViewCount AS TopPostViewCount,
    TP.AnswerCount AS TopPostAnswerCount,
    TP.CommentCount AS TopPostCommentCount,
    TP.FavoriteCount AS TopPostFavoriteCount,
    TP.PostCreationDate AS TopPostDate,
    TP.DaysSinceLastActivity AS TopPostDaysSinceActivity,
    TP.TagArray AS TopPostTags,
    GPA.AvgPostImpactScore AS GlobalAverageImpact,
    GPA.AvgScore AS GlobalAverageScore,
    EXISTS (
        SELECT 1
        FROM PostHistory PH_corr
        WHERE PH_corr.PostId = TP.PostId
          AND PH_corr.UserId IS NOT NULL
          AND PH_corr.UserId <> US.UserId
          AND PH_corr.PostHistoryTypeId IN (5)
          AND PH_corr.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) AS HasRecentOtherEditor,
    CASE
        WHEN US.Reputation > 50000 AND COALESCE(UBS.GoldBadges, 0) >= 5 THEN 'Legendary Contributor'
        WHEN US.Reputation > 10000 AND (COALESCE(UBS.GoldBadges, 0) >= 1 OR COALESCE(UBS.SilverBadges, 0) >= 5) THEN 'Distinguished Member'
        WHEN US.TotalQuestionsPosted > 50 AND US.TotalAnswersPosted > 100 THEN 'Prodigious All-Rounder'
        ELSE 'Active Participant'
    END AS UserCategory,
    RANK() OVER (ORDER BY TP.PostImpactScore DESC, US.Reputation DESC) AS OverallImpactRank,
    COALESCE(
        array_to_string(
            (CASE WHEN CARDINALITY(TP.TagArray) > 0 THEN (
                SELECT ARRAY_AGG(x)
                FROM (
                    SELECT UNNEST(TP.TagArray) AS x
                    LIMIT LEAST(3, CARDINALITY(TP.TagArray))
                ) t
            ) ELSE ARRAY[]::varchar[] END)
        , ', '),
        'No_Tags'
    ) AS Top3TagsConcatenated,
    CAST(US.TotalPostScoreReceived AS NUMERIC) / (EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - US.UserCreationDate)) + 1) AS ScorePerDaySinceCreation,
    COALESCE(TP.ClosedDate, CAST('9999-12-31' AS timestamp)) AS TopPostClosedDateEffective,
    COALESCE(PHC.TotalEditEvents, 0) AS TopPostTotalEditEvents,
    COALESCE(PHC.TotalCloseEvents, 0) AS TopPostTotalCloseEvents,
    PHC.AvgHoursBetweenHistory AS TopPostAvgHoursBetweenHistoryEvents
FROM UserSummary US
LEFT JOIN UserBadgeStats UBS ON US.UserId = UBS.UserId
JOIN UserTopPosts TP ON US.UserId = TP.OwnerUserId
LEFT JOIN GlobalPostAverages GPA ON 1=1
LEFT JOIN (
    SELECT
        PostId,
        MAX(TotalEditEvents) AS TotalEditEvents,
        MAX(TotalCloseEvents) AS TotalCloseEvents,
        AVG(HoursSincePrevHistory) FILTER (WHERE HoursSincePrevHistory IS NOT NULL) AS AvgHoursBetweenHistory
    FROM PostHistoricalChanges
    GROUP BY PostId
) PHC ON TP.PostId = PHC.PostId
WHERE TP.rn_post_type_impact = 1
  AND TP.PostTypeId = 1
  AND US.Reputation > 1000
  AND US.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
  AND US.AboutMeLength IS NOT NULL
  AND US.AboutMeLength > 50
  AND NOT EXISTS (
      SELECT 1
      FROM PostLinks PL
      WHERE PL.PostId = TP.PostId AND PL.LinkTypeId = 3
  )

UNION ALL

SELECT
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.TotalQuestionsPosted,
    US.TotalAnswersPosted,
    US.TotalPostScoreReceived,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    TP.PostId AS TopPostId,
    TP.PostTypeName AS TopPostType,
    TP.Title AS TopPostTitle,
    TP.PostImpactScore AS TopPostCalculatedImpact,
    TP.Score AS TopPostScore,
    TP.ViewCount AS TopPostViewCount,
    TP.AnswerCount AS TopPostAnswerCount,
    TP.CommentCount AS TopPostCommentCount,
    TP.FavoriteCount AS TopPostFavoriteCount,
    TP.PostCreationDate AS TopPostDate,
    TP.DaysSinceLastActivity AS TopPostDaysSinceActivity,
    TP.TagArray AS TopPostTags,
    GPA.AvgPostImpactScore AS GlobalAverageImpact,
    GPA.AvgScore AS GlobalAverageScore,
    EXISTS (
        SELECT 1
        FROM PostHistory PH_corr
        WHERE PH_corr.PostId = TP.PostId
          AND PH_corr.UserId IS NOT NULL
          AND PH_corr.UserId <> US.UserId
          AND PH_corr.PostHistoryTypeId IN (5)
          AND PH_corr.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) AS HasRecentOtherEditor,
    CASE
        WHEN US.Reputation > 50000 AND COALESCE(UBS.GoldBadges, 0) >= 5 THEN 'Legendary Contributor'
        WHEN US.Reputation > 10000 AND (COALESCE(UBS.GoldBadges, 0) >= 1 OR COALESCE(UBS.SilverBadges, 0) >= 5) THEN 'Distinguished Member'
        WHEN US.TotalQuestionsPosted > 50 AND US.TotalAnswersPosted > 100 THEN 'Prodigious All-Rounder'
        ELSE 'Active Participant'
    END AS UserCategory,
    RANK() OVER (ORDER BY TP.PostImpactScore DESC, US.Reputation DESC) AS OverallImpactRank,
    COALESCE(
        array_to_string(
            (CASE WHEN CARDINALITY(TP.TagArray) > 0 THEN (
                SELECT ARRAY_AGG(x)
                FROM (
                    SELECT UNNEST(TP.TagArray) AS x
                    LIMIT LEAST(3, CARDINALITY(TP.TagArray))
                ) t
            ) ELSE ARRAY[]::varchar[] END)
        , ', '),
        'No_Tags'
    ) AS Top3TagsConcatenated,
    CAST(US.TotalPostScoreReceived AS NUMERIC) / (EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - US.UserCreationDate)) + 1) AS ScorePerDaySinceCreation,
    COALESCE(TP.ClosedDate, CAST('9999-12-31' AS timestamp)) AS TopPostClosedDateEffective,
    COALESCE(PHC.TotalEditEvents, 0) AS TopPostTotalEditEvents,
    COALESCE(PHC.TotalCloseEvents, 0) AS TopPostTotalCloseEvents,
    PHC.AvgHoursBetweenHistory AS TopPostAvgHoursBetweenHistoryEvents
FROM UserSummary US
LEFT JOIN UserBadgeStats UBS ON US.UserId = UBS.UserId
JOIN UserTopPosts TP ON US.UserId = TP.OwnerUserId
LEFT JOIN GlobalPostAverages GPA ON 1=1
LEFT JOIN (
    SELECT
        PostId,
        MAX(TotalEditEvents) AS TotalEditEvents,
        MAX(TotalCloseEvents) AS TotalCloseEvents,
        AVG(HoursSincePrevHistory) FILTER (WHERE HoursSincePrevHistory IS NOT NULL) AS AvgHoursBetweenHistory
    FROM PostHistoricalChanges
    GROUP BY PostId
) PHC ON TP.PostId = PHC.PostId
WHERE TP.rn_post_type_impact = 1
  AND TP.PostTypeId = 2
  AND US.Reputation > 1000
  AND US.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
  AND US.AboutMeLength IS NOT NULL
  AND US.AboutMeLength > 50;