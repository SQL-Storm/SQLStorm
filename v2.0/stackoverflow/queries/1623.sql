-- {"query": "1623.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2800}
WITH UserActivityStats AS (
    SELECT
        U.Id AS UserId,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(C.Id) AS TotalComments,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.Score) AS AvgPostScore,
        MIN(P.CreationDate) AS FirstPostDate,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT P_Accept.Id) AS AnswersAcceptedForUserQuestions
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Posts P_Accept ON P_Accept.Id = P.AcceptedAnswerId AND P.PostTypeId = 1
    GROUP BY U.Id
),
PostEditActivity AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        COUNT(PH.Id) AS TotalPostHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10,12) THEN 1 ELSE 0 END) AS CloseDeleteCount,
        MAX(PH.CreationDate) AS LastEditDate,
        (SELECT COUNT(C_sub.Id)
         FROM Comments C_sub
         WHERE C_sub.PostId = P.Id
           AND C_sub.CreationDate > (
               SELECT MAX(PH2.CreationDate) FROM PostHistory PH2 WHERE PH2.PostId = P.Id
           )
        ) AS NewCommentsAfterLastEdit,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS UserPostRankByScore
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.OwnerUserId, P.Score, P.CreationDate
),
UserBadgeSummary AS (
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate,
        COALESCE(
          SUM(CASE WHEN B.Class = 1 THEN EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - B.Date)) ELSE 0 END)
          / NULLIF(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0)
        , 0) AS AvgTimeSinceGoldBadgeSeconds
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
),
ProblematicPostIds AS (
    SELECT PH.PostId
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId = 10
      AND EXISTS (SELECT 1 FROM PostHistory PH2 WHERE PH2.PostId = PH.PostId AND PH2.PostHistoryTypeId = 11 AND PH2.CreationDate > PH.CreationDate)
    UNION ALL
    SELECT PH.PostId
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId = 12
      AND EXISTS (SELECT 1 FROM PostHistory PH3 WHERE PH3.PostId = PH.PostId AND PH3.PostHistoryTypeId = 13 AND PH3.CreationDate > PH.CreationDate)
)
SELECT
    U.Id AS UserIdentifier,
    COALESCE(U.DisplayName, 'Anonymous User') AS UserDisplayName,
    U.Reputation,
    U.Views AS UserProfileViews,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalComments,
    COALESCE(UAS.AvgPostScore, 0.0) AS UserAvgPostScore,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    UBS.AvgTimeSinceGoldBadgeSeconds,
    P.Id AS PostId,
    COALESCE(P.Title, 'No Title Provided') AS PostTitle,
    PT.Name AS PostTypeName,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    P.CommentCount AS PostCommentCount,
    P.FavoriteCount AS PostFavoriteCount,
    CASE
        WHEN P.AcceptedAnswerId IS NOT NULL THEN 'HasAcceptedAnswer'
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN P.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
        WHEN P.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7 days') AND P.CommentCount = 0 THEN 'RecentNoEngagement'
        ELSE 'Open'
    END AS PostStatusDetail,
    P.CreationDate AS PostCreationDate,
    P.LastActivityDate AS PostLastActivityDate,
    PEA.TotalPostHistoryEvents,
    PEA.EditCount,
    PEA.CloseDeleteCount,
    PEA.NewCommentsAfterLastEdit AS CommentsAfterLastEdit,
    COALESCE(U.Location, 'Unspecified Location') AS UserLocation,
    SUBSTRING(COALESCE(U.AboutMe, 'No "About Me" provided.'), 1, 150) AS AboutMeSnippet,
    ROW_NUMBER() OVER (PARTITION BY U.Location ORDER BY U.Reputation DESC, U.CreationDate) AS UserRankInSpecificLocation,
    LAG(P.CreationDate) OVER (PARTITION BY U.Id ORDER BY P.CreationDate) AS PreviousPostCreationDateForUser,
    (SELECT AVG(C_sub.Score)
     FROM Comments C_sub
     WHERE C_sub.PostId = P.Id
       AND C_sub.UserId = P.OwnerUserId
       AND C_sub.CreationDate BETWEEN PEA.LastEditDate AND (PEA.LastEditDate + INTERVAL '1 month')) AS AvgOwnerCommentScoreAfterEdit,
    UPPER(SUBSTRING(COALESCE(U.DisplayName, 'UNKNOWN_DISPLAY_NAME'), 1, 5)) AS DisplayNamePrefixFiveChars,
    TRIM(REPLACE(REPLACE(P.Tags, '>', ' '), '<', '')) AS SpaceSeparatedTags,
    CASE WHEN PPI.PostId IS NOT NULL THEN 'TRUE' ELSE 'FALSE' END AS IsProblematicPostFlag,
    DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate) AS UserAgeInDays,
    DATE_PART('hour', P.LastActivityDate - P.CreationDate) AS PostActivityDurationHours,
    COALESCE(PL.LinkTypeId, -1) AS RelatedLinkType
FROM Users U
LEFT JOIN UserActivityStats UAS ON U.Id = UAS.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN PostEditActivity PEA ON P.Id = PEA.PostId
LEFT JOIN ProblematicPostIds PPI ON P.Id = PPI.PostId
LEFT JOIN PostLinks PL ON P.Id = PL.PostId
WHERE U.Reputation > 7500
  AND U.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
  AND (COALESCE(UBS.GoldBadges, 0) >= 3 OR COALESCE(UBS.SilverBadges, 0) >= 7)
  AND P.PostTypeId IN (1, 2)
  AND P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years')
  AND P.Score > 5
  AND P.ViewCount > 500
  AND (P.Tags LIKE '%<performance>%' OR P.Tags LIKE '%<optimization>%' OR P.Tags LIKE '%<benchmark>%')
  AND U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 100
  AND P.Body LIKE '%resource allocation%'
  AND PEA.EditCount > 1
  AND PEA.UserPostRankByScore <= 3
  AND (P.ClosedDate IS NULL OR P.ClosedDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'))
  AND NOT EXISTS (SELECT 1 FROM Comments C_ex WHERE C_ex.PostId = P.Id AND C_ex.Text LIKE '%spam%')
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.Views, U.CreationDate, U.LastAccessDate,
    UAS.TotalPosts, UAS.TotalQuestions, UAS.TotalAnswers, UAS.TotalComments, UAS.AvgPostScore,
    UBS.GoldBadges, UBS.SilverBadges, UBS.BronzeBadges, UBS.AvgTimeSinceGoldBadgeSeconds,
    P.Id, P.Title, PT.Name, P.Score, P.ViewCount, P.CommentCount, P.FavoriteCount,
    P.AcceptedAnswerId, P.ClosedDate, P.CommunityOwnedDate, P.CreationDate, P.LastActivityDate, P.Body, P.Tags,
    PEA.TotalPostHistoryEvents, PEA.EditCount, PEA.CloseDeleteCount, PEA.NewCommentsAfterLastEdit, PEA.LastEditDate, PEA.UserPostRankByScore,
    U.Location, U.AboutMe, P.OwnerUserId, PPI.PostId, PL.LinkTypeId
HAVING
    SUM(PEA.NewCommentsAfterLastEdit) >= 1
    AND AVG(P.Score) > 15
    AND COUNT(P.Id) >= 3
    AND SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) >= 1
ORDER BY
    U.Reputation DESC, UBS.GoldBadges DESC, UserAvgPostScore DESC, PostScore DESC
LIMIT 500;