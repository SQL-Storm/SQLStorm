WITH UserPostStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(P.Id) AS TotalPostsOwned,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsOwned,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersOwned,
        SUM(P.Score) AS TotalPostsScore,
        AVG(P.Score) AS AvgPostScoreOwned,
        MAX(P.LastActivityDate) AS LastActivityOnOwnedPost
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementSummary AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score AS PostInitialScore,
        P.ViewCount,
        P.FavoriteCount AS DeclaredFavoriteCount,
        P.AnswerCount,
        P.CreationDate AS PostCreationDate,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.Id END) AS UpVotesReceived,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.Id END) AS DownVotesReceived,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 5 THEN V.Id END) AS ActualFavoriteVotes,
        COUNT(DISTINCT C.Id) AS CommentCount
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.Score, P.ViewCount, P.FavoriteCount, P.AnswerCount, P.CreationDate
),
ParsedPostTags AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'))) AS TagName,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.Tags IS NOT NULL
      AND LENGTH(P.Tags) > 2
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        STRING_AGG(DISTINCT B.Name, ', ') AS AllBadges,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
RecentPostHistory AS (
    SELECT
        PH.UserId,
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        ROW_NUMBER() OVER(PARTITION BY PH.PostId, PH.UserId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC) as rn
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
      AND PH.UserId IS NOT NULL
),
HighlyEngagingPosts AS (
    SELECT PostId
    FROM PostEngagementSummary
    WHERE PostInitialScore > 50 AND PostTypeId = 1
    INTERSECT
    SELECT PostId
    FROM PostEngagementSummary
    WHERE ViewCount > 10000 AND PostTypeId = 1
)
SELECT
    UPS.UserId,
    UPS.DisplayName,
    UPS.Reputation,
    UPS.TotalPostsOwned,
    UPS.QuestionsOwned,
    UPS.AnswersOwned,
    UPS.TotalPostsScore,
    DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM UPS.UserCreationDate) ORDER BY UPS.AvgPostScoreOwned DESC NULLS LAST) AS AvgPostScoreRankInCreationYear,
    SUM(UPS.Reputation) OVER (ORDER BY UPS.UserCreationDate ASC, UPS.UserId ASC) AS CumulativeReputationByCreationDate,
    (
        (UPS.UserUpVotesGiven * 0.5) + (UPS.TotalPostsScore * 0.3) - (UPS.UserDownVotesGiven * 0.2) + (UPS.AnswersOwned * 0.1)
    ) / NULLIF(UPS.UserProfileViews + 1, 0) AS EngagementEfficiencyScore,
    EXISTS (
        SELECT 1
        FROM RecentPostHistory RPH_Corr
        WHERE RPH_Corr.UserId = UPS.UserId
          AND RPH_Corr.PostHistoryTypeId IN (10, 101)
          AND RPH_Corr.HistoryDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    ) AS HasRecentClosureParticipation,
    COALESCE(UPPER(LEFT(UPS.DisplayName, 5)), MD5(CAST(UPS.UserId AS TEXT))) AS ResolvedDisplayNamePrefix,
    LOWER(U.Location) AS UserLocationLowerCase,
    TRIM(U.WebsiteUrl) AS UserWebsiteTrimmed,
    COALESCE(SUM(PES.UpVotesReceived), 0) AS TotalUpVotesOnOwnedContent,
    COALESCE(SUM(PES.DownVotesReceived), 0) AS TotalDownVotesOnOwnedContent,
    COALESCE(SUM(PES.CommentCount), 0) AS TotalCommentsOnOwnedContent,
    STRING_AGG(DISTINCT T.TagName, ' || ' ORDER BY T.TagName) AS UserTopTags,
    COUNT(DISTINCT T.TagName) AS UniqueTagCount,
    CASE
        WHEN STRING_AGG(DISTINCT T.TagName, ' ') ILIKE '%<sql>%'
             AND STRING_AGG(DISTINCT T.TagName, ' ') ILIKE '%<performance>%'
        THEN 'SQL_Performance_Expert'
        WHEN STRING_AGG(DISTINCT T.TagName, ' ') ILIKE '%<javascript>%'
             OR STRING_AGG(DISTINCT T.TagName, ' ') ILIKE '%<react>%'
        THEN 'Frontend_Developer'
        WHEN COUNT(DISTINCT T.TagName) > 10 AND UPS.QuestionsOwned > 20 THEN 'Generalist_Contributor'
        ELSE 'Other_Tag_Focus'
    END AS TagBasedExpertiseCategory,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadgesAwarded,
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - UBS.LastBadgeDate)) / (60 * 60 * 24)) AS DaysSinceLastBadge,
    COUNT(DISTINCT HEP.PostId) AS HighlyEngagingPostsCount,
    MAX(CASE WHEN HEP.PostId IS NOT NULL THEN 'TRUE' ELSE 'FALSE' END) AS HasHighlyEngagingPost,
    (
        SELECT COUNT(DISTINCT PH2.PostId)
        FROM PostHistory PH2
        WHERE PH2.UserId = UPS.UserId
          AND PH2.PostHistoryTypeId IN (5)
          AND PH2.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
          AND PH2.Comment IS NOT NULL
    ) AS RecentBodyEditCommentCount,
    (
        SELECT AVG(EXTRACT(EPOCH FROM (C.CreationDate - P.CreationDate)))
        FROM Posts P
        INNER JOIN Comments C ON P.Id = C.PostId
        WHERE P.OwnerUserId = UPS.UserId
          AND P.PostTypeId = 1
        GROUP BY P.OwnerUserId
    ) AS AvgTimeUntilFirstCommentSeconds,
    CASE
        WHEN UPS.Reputation > 20000 THEN
            (SELECT AVG(PES_Corr.PostInitialScore) FROM PostEngagementSummary PES_Corr WHERE PES_Corr.OwnerUserId = UPS.UserId AND PES_Corr.PostTypeId = 1)
        ELSE
            (SELECT AVG(PES_Corr.PostInitialScore) FROM PostEngagementSummary PES_Corr WHERE PES_Corr.OwnerUserId = UPS.UserId AND PES_Corr.PostTypeId = 2)
    END AS ConditionalAvgPostScore,
    COALESCE(NULLIF(TRIM(U.AboutMe), ''), 'No "About Me" provided') AS AboutMeContent,
    LEAD(UPS.Reputation) OVER (ORDER BY UPS.Reputation DESC) - UPS.Reputation AS ReputationDiffToNextHigher
FROM UserPostStats UPS
INNER JOIN Users U ON UPS.UserId = U.Id
LEFT JOIN PostEngagementSummary PES ON UPS.UserId = PES.OwnerUserId
LEFT JOIN ParsedPostTags T ON UPS.UserId = T.OwnerUserId
LEFT JOIN UserBadgeSummary UBS ON UPS.UserId = UBS.UserId
LEFT JOIN HighlyEngagingPosts HEP ON PES.PostId = HEP.PostId
WHERE UPS.Reputation >= 1000
  AND UPS.TotalPostsOwned > 0
  AND UPS.UserCreationDate <= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
GROUP BY
    UPS.UserId, UPS.DisplayName, UPS.Reputation, UPS.TotalPostsOwned, UPS.QuestionsOwned,
    UPS.AnswersOwned, UPS.TotalPostsScore, UPS.AvgPostScoreOwned, UPS.UserCreationDate,
    UPS.UserProfileViews, UPS.UserUpVotesGiven, UPS.UserDownVotesGiven,
    UBS.GoldBadges, UBS.SilverBadges, UBS.BronzeBadges, UBS.TotalBadges, UBS.LastBadgeDate,
    U.Location, U.WebsiteUrl, U.AboutMe
ORDER BY
    UPS.Reputation DESC, EngagementEfficiencyScore DESC
LIMIT 5000;