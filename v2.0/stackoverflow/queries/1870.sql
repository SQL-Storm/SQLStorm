WITH UserBaseWithBadgeInfo AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.Location,
        U.AboutMe,
        U.Views,
        COALESCE(B.TotalBadges, 0) AS TotalBadges,
        COALESCE(B.GoldBadges, 0) AS GoldBadges,
        COALESCE(B.SilverBadges, 0) AS SilverBadges,
        COALESCE(B.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(B.TagBasedBadges, 0) AS TagBasedBadges
    FROM Users U
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(Id) AS TotalBadges,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            SUM(CASE WHEN TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
        FROM Badges
        GROUP BY UserId
    ) B ON U.Id = B.UserId
    WHERE U.Reputation >= 100
      AND U.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
),
UserEngagementSummary AS (
    SELECT
        UB.UserId,
        UB.DisplayName,
        UB.Reputation,
        UB.UserCreationDate,
        UB.LastAccessDate,
        UB.UserUpVotesGiven,
        UB.UserDownVotesGiven,
        UB.Location,
        UB.AboutMe,
        UB.Views,
        UB.TotalBadges,
        UB.GoldBadges,
        UB.SilverBadges,
        UB.BronzeBadges,
        UB.TagBasedBadges,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ReceivedUpVotesOnPosts,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ReceivedDownVotesOnPosts
    FROM UserBaseWithBadgeInfo UB
    LEFT JOIN Posts P ON UB.UserId = P.OwnerUserId
    LEFT JOIN Comments C ON UB.UserId = C.UserId
    LEFT JOIN Votes PV ON P.Id = PV.PostId
    WHERE (P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR) OR P.CreationDate IS NULL)
      OR (C.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR) OR C.CreationDate IS NULL)
    GROUP BY
        UB.UserId, UB.DisplayName, UB.Reputation, UB.UserCreationDate, UB.LastAccessDate,
        UB.UserUpVotesGiven, UB.UserDownVotesGiven, UB.Location, UB.AboutMe, UB.Views,
        UB.TotalBadges, UB.GoldBadges, UB.SilverBadges, UB.BronzeBadges, UB.TagBasedBadges
),
PostPerformanceMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        COALESCE(P.ViewCount, 0) AS EffectiveViewCount,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 86400.0 AS DaysActive,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - P.CreationDate)) / 86400.0 AS DaysSinceCreation,
        CASE
            WHEN P.PostTypeId = 1 AND COALESCE(P.ViewCount, 0) > 0 THEN CAST(P.Score AS DOUBLE PRECISION) / P.ViewCount
            WHEN P.PostTypeId = 2 AND COALESCE(P.CommentCount, 0) > 0 THEN CAST(P.Score AS DOUBLE PRECISION) / P.CommentCount
            WHEN P.PostTypeId = 2 THEN CAST(P.Score AS DOUBLE PRECISION)
            ELSE 0.0
        END AS PerformanceRatio,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostRankByScore,
        NTILE(10) OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS PostEngagementTier,
        (CASE WHEN P.Tags IS NOT NULL AND (LOWER(P.Tags) LIKE '%<sql>%' OR LOWER(P.Tags) LIKE '%<database>%' OR LOWER(P.Tags) LIKE '%<postgresql>%') THEN TRUE ELSE FALSE END) AS IsSqlOrDbPost,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = P.Id AND C.CreationDate >= P.CreationDate AND C.Score IS NOT NULL) AS AvgCommentScoreOnPost
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2)
      AND P.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3' YEAR)
),
PostHistoryTimeline AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditDateByHistory,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS TotalEditEvents
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 4, 5, 6)
    GROUP BY PH.PostId
),
UserPostAggregates AS (
    SELECT
        PPM.OwnerUserId AS UserId,
        COUNT(PPM.PostId) AS TotalPostsAnalyzed,
        SUM(CASE WHEN PPM.IsSqlOrDbPost THEN 1 ELSE 0 END) AS SqlDbPostCount,
        AVG(PPM.PerformanceRatio) AS AvgPostPerformanceRatio
    FROM PostPerformanceMetrics PPM
    GROUP BY PPM.OwnerUserId
)
SELECT
    UES.UserId,
    COALESCE(UES.DisplayName, 'Anonymous User') AS UserName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.LastAccessDate,
    UES.TotalPosts,
    UES.TotalQuestions,
    UES.TotalAnswers,
    UES.TotalPostScore,
    UES.TotalComments,
    UES.TotalCommentScore,
    UES.ReceivedUpVotesOnPosts,
    UES.ReceivedDownVotesOnPosts,
    UES.TotalBadges,
    UES.GoldBadges,
    UES.SilverBadges,
    UES.BronzeBadges,
    PPM_Q.PostId AS TopQuestionId,
    PPM_Q.PostScore AS TopQuestionScore,
    PPM_Q.ViewCount AS TopQuestionViews,
    PPM_Q.DaysActive AS TopQuestionDaysActive,
    PPM_Q.PerformanceRatio AS TopQuestionPerformanceRatio,
    PPM_Q.AvgCommentScoreOnPost AS TopQuestionAvgCommentScore,
    PPM_Q.Tags AS TopQuestionTags,
    PPM_A.PostId AS TopAnswerId,
    PPM_A.PostScore AS TopAnswerScore,
    PPM_A.DaysActive AS TopAnswerDaysActive,
    PPM_A.PerformanceRatio AS TopAnswerPerformanceRatio,
    PPM_A.AvgCommentScoreOnPost AS TopAnswerAvgCommentScore,
    PHT.LastClosedDate,
    PHT.LastReopenedDate,
    PHT.LastEditDateByHistory,
    COALESCE(PHT.TotalEditEvents, 0) AS TotalEditEventsOnTopPost,
    UPA.SqlDbPostCount AS UserSqlDbPostCount,
    COALESCE(UPA.AvgPostPerformanceRatio, 0.0) AS UserAvgPostPerformanceRatio,
    (UES.Reputation * 0.5 + UES.ReceivedUpVotesOnPosts * 0.3 + UES.GoldBadges * 10 + UES.SilverBadges * 5 + UES.TotalQuestions * 2 + UES.TotalAnswers * 1.5 + COALESCE(UES.TotalCommentScore, 0) * 0.1) /
    (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - UES.UserCreationDate)) / (86400.0 * 365.25) + 1.0) AS InfluenceScore,
    CASE
        WHEN UES.TotalQuestions > 0 AND UES.TotalAnswers = 0 THEN 'Questioner'
        WHEN UES.TotalAnswers > 0 AND UES.TotalQuestions = 0 THEN 'Answerer'
        WHEN UES.TotalQuestions > 0 AND UES.TotalAnswers > 0 AND UES.TotalAnswers >= UES.TotalQuestions THEN 'Contributor (Answer Heavy)'
        WHEN UES.TotalQuestions > 0 AND UES.TotalAnswers > 0 AND UES.TotalQuestions > UES.TotalAnswers THEN 'Contributor (Question Heavy)'
        ELSE 'Passive'
    END AS UserType,
    CASE
        WHEN UES.Location IS NOT NULL AND (LOWER(UES.Location) LIKE '%usa%' OR LOWER(UES.Location) LIKE '%united states%' OR LOWER(UES.Location) LIKE '%uk%' OR LOWER(UES.Location) LIKE '%united kingdom%' OR LOWER(UES.Location) LIKE '%canada%') THEN TRUE
        ELSE FALSE
    END AS IsGeoTargetedEnglishSpeaking,
    (SELECT MAX(B2.Date) FROM Badges B2 WHERE B2.UserId = UES.UserId AND B2.Class = 1) AS LatestGoldBadgeDate,
    (SELECT COUNT(DISTINCT PH2.PostId) FROM PostHistory PH2 WHERE PH2.UserId = UES.UserId AND PH2.PostHistoryTypeId IN (4,5,6) AND PH2.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)) AS RecentEditsByUserCount,
    COALESCE(PPM_Q.DaysSinceCreation, PPM_A.DaysSinceCreation, 0) AS DaysSinceTopPostCreation,
    (CASE WHEN UES.AboutMe IS NOT NULL AND CHAR_LENGTH(UES.AboutMe) > 100 THEN 'Verbose' ELSE 'Concise' END) AS AboutMeStyle
FROM
    UserEngagementSummary UES
LEFT JOIN
    PostPerformanceMetrics PPM_Q ON UES.UserId = PPM_Q.OwnerUserId AND PPM_Q.PostTypeId = 1 AND PPM_Q.PostRankByScore = 1
LEFT JOIN
    PostPerformanceMetrics PPM_A ON UES.UserId = PPM_A.OwnerUserId AND PPM_A.PostTypeId = 2 AND PPM_A.PostRankByScore = 1
LEFT JOIN
    PostHistoryTimeline PHT ON COALESCE(PPM_Q.PostId, PPM_A.PostId) = PHT.PostId
LEFT JOIN
    UserPostAggregates UPA ON UES.UserId = UPA.UserId
WHERE
    UES.Reputation > 500
    AND UES.TotalPosts > 2
    AND (PPM_Q.PostId IS NOT NULL OR PPM_A.PostId IS NOT NULL)
    AND UES.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH)
ORDER BY
    InfluenceScore DESC, UES.Reputation DESC, UES.LastAccessDate DESC
FETCH FIRST 1000 ROWS ONLY;