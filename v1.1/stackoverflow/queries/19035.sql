WITH UserActivityMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        MAX(B.Date) AS LastBadgeDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    WHERE
        U.CreationDate >= TIMESTAMP '2010-01-01'
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(ph.CreationDate) AS LastHistoryDate,
        MIN(ph.CreationDate) AS FirstHistoryDate,
        AVG(ph.EditGapHours) AS AvgTimeBetweenEditsHours
    FROM (
        SELECT
            PH.PostId,
            PH.Id,
            PH.PostHistoryTypeId,
            PH.CreationDate,
            CASE
                WHEN PH.PostHistoryTypeId IN (4,5,6) THEN
                    EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) / 3600.0
                ELSE NULL
            END AS EditGapHours
        FROM
            PostHistory PH
        WHERE
            PH.CreationDate >= TIMESTAMP '2015-01-01'
    ) ph
    GROUP BY
        ph.PostId
),
PostTagging AS (
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR (CHAR_LENGTH(P.Tags)-2)), '><'))) AS TagName
    FROM
        Posts P
    WHERE
        P.Tags IS NOT NULL AND CHAR_LENGTH(P.Tags) > 2
),
TagPerformance AS (
    SELECT
        PT.TagName,
        COUNT(DISTINCT P.Id) AS TaggedPostsCount,
        SUM(COALESCE(P.Score,0)) AS TotalTagScore,
        AVG(COALESCE(P.ViewCount,0)) AS AvgTagViewCount,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS PostsWithAcceptedAnswer,
        SUM(COALESCE(P.AnswerCount, 0)) AS TotalAnswersToTagPosts
    FROM
        PostTagging PT
    JOIN
        Posts P ON PT.PostId = P.Id
    WHERE
        P.PostTypeId = 1 AND P.CreationDate >= TIMESTAMP '2018-01-01'
    GROUP BY
        PT.TagName
    HAVING
        COUNT(P.Id) > 50
),
RecentHotPosts AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY (P.Score * 0.5 + P.ViewCount * 0.2 + P.CommentCount * 0.3 + COALESCE(P.FavoriteCount, 0) * 1.0) DESC, P.LastActivityDate DESC) AS EngagementRank,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS UserRollingAvgScore
    FROM
        Posts P
    WHERE
        P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years') AND P.PostTypeId IN (1, 2)
        AND (LOWER(P.Body) LIKE '%sql%' OR LOWER(P.Title) LIKE '%database%')
)
SELECT
    UAM.UserId,
    UAM.DisplayName,
    UAM.Reputation,
    UAM.TotalPosts,
    UAM.TotalQuestions,
    UAM.TotalAnswers,
    UAM.GoldBadges,
    UAM.SilverBadges,
    UAM.BronzeBadges,
    RHP.PostId AS TopPostId,
    RHP.PostTypeId AS TopPostType,
    RHP.Score AS TopPostScore,
    RHP.ViewCount AS TopPostViews,
    RHP.UserRollingAvgScore,
    TP.TagName AS MostPopularTagInUserActivity,
    TP.TotalTagScore,
    TP.AvgTagViewCount,
    (SELECT COUNT(DISTINCT PH_sub.PostId)
     FROM PostHistory PH_sub
     WHERE PH_sub.UserId = UAM.UserId
       AND PH_sub.PostHistoryTypeId = 10
       AND PH_sub.Comment IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM CloseReasonTypes CRT WHERE CRT.Id = CAST(PH_sub.Comment AS SMALLINT) AND LOWER(CRT.Name) LIKE '%duplicate%'
       )
    ) AS DuplicateClosedPostCount,
    COALESCE(U.Location, 'Unknown/Private Location') AS UserLocation,
    CASE
        WHEN U.AboutMe IS NULL THEN 'No AboutMe provided'
        WHEN LENGTH(U.AboutMe) < 50 THEN 'Short Bio'
        WHEN LENGTH(U.AboutMe) >= 50 AND LENGTH(U.AboutMe) < 200 THEN 'Medium Bio'
        ELSE 'Detailed Bio'
    END AS AboutMeStatus,
    EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate)) AS DaysSinceAccountCreation,
    CASE
        WHEN UAM.TotalQuestions > UAM.TotalAnswers * 1.5 THEN 'Questioner Dominant'
        WHEN UAM.TotalAnswers > UAM.TotalQuestions * 1.5 THEN 'Answerer Dominant'
        WHEN UAM.TotalPosts = 0 AND UAM.TotalComments = 0 THEN 'Passive User'
        ELSE 'Balanced Contributor/Other'
    END AS UserContributionType,
    (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = RHP.PostId AND V.VoteTypeId = 2 AND V.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 month')) AS RecentUpvotesOnTopPost,
    PHS.EditCount AS TopPostEditCount,
    PHS.AvgTimeBetweenEditsHours AS TopPostAvgTimeBetweenEdits,
    COUNT(DISTINCT PL_Linked.RelatedPostId) AS PostsLinkedFromTopPost,
    COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS DuplicateTargetOfTopPost
FROM
    UserActivityMetrics UAM
JOIN
    Users U ON UAM.UserId = U.Id
LEFT JOIN
    RecentHotPosts RHP ON UAM.UserId = RHP.OwnerUserId AND RHP.EngagementRank <= 5
LEFT JOIN
    PostHistorySummary PHS ON RHP.PostId = PHS.PostId
LEFT JOIN
    TagPerformance TP ON TP.TagName = (
        SELECT PT_sub.TagName
        FROM PostTagging PT_sub
        JOIN Posts P_sub ON PT_sub.PostId = P_sub.Id
        WHERE P_sub.OwnerUserId = UAM.UserId
        AND P_sub.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
        GROUP BY PT_sub.TagName
        ORDER BY COUNT(P_sub.Id) DESC, SUM(COALESCE(P_sub.Score,0)) DESC
        LIMIT 1
    )
LEFT JOIN
    PostLinks PL_Linked ON RHP.PostId = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
LEFT JOIN
    PostLinks PL_Duplicate ON RHP.PostId = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
WHERE
    UAM.Reputation > 1000
    AND U.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    AND (U.WebsiteUrl IS NOT NULL OR U.AboutMe IS NOT NULL)
    AND (RHP.PostId IS NOT NULL OR UAM.GoldBadges > 0)
GROUP BY
    UAM.UserId, UAM.DisplayName, UAM.Reputation, UAM.TotalPosts, UAM.TotalQuestions, UAM.TotalAnswers,
    UAM.GoldBadges, UAM.SilverBadges, UAM.BronzeBadges, RHP.PostId, RHP.PostTypeId, RHP.Score,
    RHP.ViewCount, RHP.UserRollingAvgScore, TP.TagName, TP.TotalTagScore, TP.AvgTagViewCount,
    U.Location, U.AboutMe, U.CreationDate, PHS.EditCount, PHS.AvgTimeBetweenEditsHours, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, UAM.TotalComments
HAVING
    COUNT(DISTINCT RHP.PostId) > 0 OR UAM.GoldBadges > 0

UNION ALL

SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    0 AS TotalPosts,
    0 AS TotalQuestions,
    0 AS TotalAnswers,
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    P.Id AS TopPostId,
    P.PostTypeId AS TopPostType,
    P.Score AS TopPostScore,
    P.ViewCount AS TopPostViews,
    AVG(P.Score) OVER (PARTITION BY U.Id ORDER BY P.CreationDate) AS UserRollingAvgScore,
    NULL AS MostPopularTagInUserActivity,
    NULL AS TotalTagScore,
    NULL AS AvgTagViewCount,
    (SELECT COUNT(PH_mod.Id) FROM PostHistory PH_mod
     WHERE PH_mod.UserId = U.Id AND PH_mod.PostHistoryTypeId IN (14, 15, 19, 20)
     AND PH_mod.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
    ) AS ModeratorActionCount,
    COALESCE(U.Location, 'Moderator HQ') AS UserLocation,
    'Moderator Role' AS AboutMeStatus,
    EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate)) AS DaysSinceAccountCreation,
    'Moderator' AS UserContributionType,
    (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 15 AND V.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 months')) AS RecentModeratorReviews,
    NULL AS TopPostEditCount,
    NULL AS TopPostAvgTimeBetweenEdits,
    0 AS PostsLinkedFromTopPost,
    0 AS DuplicateTargetOfTopPost
FROM
    Users U
LEFT JOIN
    Badges B ON U.Id = B.UserId
JOIN
    Posts P ON U.Id = P.OwnerUserId
WHERE
    U.Reputation > 20000
    AND P.PostTypeId = 6
    AND P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    AND U.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 months')
GROUP BY
    U.Id, U.DisplayName, U.Reputation, P.Id, P.PostTypeId, P.Score, P.ViewCount, U.Location, U.CreationDate
ORDER BY
    Reputation DESC, DaysSinceAccountCreation ASC;