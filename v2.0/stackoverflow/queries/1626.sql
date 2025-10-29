-- {"query": "1626.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3264}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswerCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(P.Score) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN P.Id END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionCount,
        MAX(P.CreationDate) AS LatestPostDate,
        MIN(P.CreationDate) AS EarliestPostDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
BadgeMilestonesRaw AS (
    SELECT
        UserId,
        Name,
        Class,
        Date,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date) AS BadgeRank,
        LAG(Date) OVER (PARTITION BY UserId ORDER BY Date) AS PreviousBadgeDate,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY UserId ORDER BY Date) AS RunningGoldBadgesCount
    FROM Badges
),
BadgeMilestones AS (
    SELECT
        BMR.UserId,
        COUNT(CASE WHEN BMR.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN BMR.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN BMR.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(BMR.Date) AS LastBadgeDate,
        CASE WHEN MAX(BMR.BadgeRank) > 1 THEN EXTRACT(EPOCH FROM (MAX(BMR.Date) - MIN(BMR.Date))) / (60 * 60 * 24) ELSE NULL END AS DaysBetweenFirstAndLastBadge,
        (SELECT Name FROM Badges WHERE UserId = BMR.UserId AND Class = 1 ORDER BY Date ASC LIMIT 1) AS FirstGoldBadgeName,
        MAX(BMR.RunningGoldBadgesCount) AS PeakRunningGoldBadges
    FROM BadgeMilestonesRaw BMR
    GROUP BY BMR.UserId
),
PostTagAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        TRIM(BOTH '<>' FROM tag_part) AS TagName_Cleaned
    FROM Posts P,
    LATERAL (
      SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR CHAR_LENGTH(P.Tags) - 2), '><')) AS tag_part
    ) unn
    WHERE P.Tags IS NOT NULL AND P.PostTypeId IN (1, 4, 5)
),
AggregatedTagPerformance AS (
    SELECT
        PTA.TagName_Cleaned AS TagName,
        COUNT(DISTINCT CASE WHEN PTA.PostTypeId = 1 THEN PTA.PostId END) AS TaggedQuestionCount,
        SUM(CASE WHEN PTA.PostTypeId = 1 THEN PTA.Score ELSE 0 END) AS TotalTagQuestionScore,
        AVG(CASE WHEN PTA.PostTypeId = 1 THEN PTA.ViewCount ELSE NULL END) AS AvgTagQuestionViews,
        T.IsModeratorOnly
    FROM PostTagAnalysis PTA
    LEFT JOIN Tags T ON PTA.TagName_Cleaned = T.TagName
    GROUP BY PTA.TagName_Cleaned, T.IsModeratorOnly
),
QuestionDetailedMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.Title,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.FavoriteCount,
        Q.ClosedDate,
        Q.LastEditDate,
        PH_closed.CreationDate AS ActualClosedDate,
        CRT.Name AS CloseReason,
        COALESCE(Q.FavoriteCount, 0) + COALESCE(Q.AnswerCount, 0) AS EngagementScore,
        RANK() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.CreationDate DESC) AS UserQuestionScoreRank,
        CHAR_LENGTH(Q.Title) AS TitleLength,
        (CASE WHEN Q.Title LIKE '%SQL%' OR Q.Title LIKE '%database%' THEN 'DB-Related' ELSE 'General' END) AS TitleCategory,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - COALESCE(Q.LastEditDate, Q.CreationDate))) / (60 * 60 * 24) AS DaysSinceLastActivity,
        EXISTS (SELECT 1 FROM Posts A WHERE A.Id = Q.AcceptedAnswerId AND A.OwnerUserId = Q.OwnerUserId) AS SelfAcceptedAnswer,
        (SELECT AVG(A2.Score) FROM Posts A2 WHERE A2.ParentId = Q.Id AND A2.PostTypeId = 2) AS AvgAnswerScoreForQuestion
    FROM Posts Q
    LEFT JOIN PostHistory PH_closed ON Q.Id = PH_closed.PostId AND PH_closed.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CRT ON NULLIF(PH_closed.Comment, '') IS NOT NULL AND CAST(NULLIF(PH_closed.Comment, '') AS integer) = CRT.Id
    WHERE Q.PostTypeId = 1
    GROUP BY
        Q.Id, Q.OwnerUserId, Q.Title, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount,
        Q.ClosedDate, Q.LastEditDate, PH_closed.CreationDate, CRT.Name, Q.LastEditDate, Q.CreationDate, Q.AcceptedAnswerId
),
ActiveUsersWithHighImpactTags AS (
    SELECT DISTINCT
        UE.UserId
    FROM UserEngagement UE
    JOIN PostTagAnalysis PTA ON UE.UserId = PTA.OwnerUserId
    JOIN AggregatedTagPerformance ATP ON PTA.TagName_Cleaned = ATP.TagName
    WHERE UE.QuestionCount > 50
      AND UE.AnswerCount > 100
      AND UE.Reputation > 10000
      AND ATP.TaggedQuestionCount > 1000
      AND ATP.AvgTagQuestionViews > 5000
      AND COALESCE(ATP.IsModeratorOnly, FALSE) = FALSE
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    'Top Impactful User' AS UserCategory,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.TotalPostScore,
    UE.TotalCommentScore,
    BM.GoldBadges,
    BM.SilverBadges,
    BM.BronzeBadges,
    BM.DaysBetweenFirstAndLastBadge,
    BM.FirstGoldBadgeName,
    QDM.QuestionId AS TopQuestionId,
    QDM.Title AS TopQuestionTitle,
    QDM.QuestionScore AS TopQuestionScore,
    QDM.QuestionViewCount AS TopQuestionViews,
    QDM.EngagementScore AS TopQuestionEngagementScore,
    QDM.TitleLength AS TopQuestionTitleLength,
    QDM.TitleCategory AS TopQuestionTitleCategory,
    QDM.DaysSinceLastActivity AS TopQuestionDaysSinceLastActivity,
    QDM.SelfAcceptedAnswer AS TopQuestionSelfAcceptedAnswer,
    QDM.AvgAnswerScoreForQuestion AS TopQuestionAvgAnswerScore,
    ATP_UserTags.UniqueTagsContributed,
    ATP_UserTags.AverageTagQuestionScorePerUser,
    ATP_UserTags.MaxTagQuestionViewsPerUser,
    (UE.TotalPostScore + UE.TotalCommentScore) * (1 + (COALESCE(BM.GoldBadges, 0) * 0.5 + COALESCE(BM.SilverBadges, 0) * 0.2 + COALESCE(BM.BronzeBadges, 0) * 0.1)) AS OverallImpactScore,
    CASE
        WHEN CHAR_LENGTH(UE.DisplayName) > 20 THEN SUBSTRING(UE.DisplayName FROM 1 FOR 17) || '...'
        ELSE UE.DisplayName
    END AS DisplayNameShortened,
    COALESCE(UE.LatestPostDate, UE.UserCreationDate) AS LastEngagementDate,
    COALESCE(BM.LastBadgeDate, UE.UserCreationDate) AS LastBadgeOrCreationDate
FROM UserEngagement UE
LEFT JOIN BadgeMilestones BM ON UE.UserId = BM.UserId
LEFT JOIN QuestionDetailedMetrics QDM ON UE.UserId = QDM.OwnerUserId AND QDM.UserQuestionScoreRank = 1
LEFT JOIN (
    SELECT PTA.OwnerUserId AS UserId,
           COUNT(DISTINCT PTA.TagName_Cleaned) AS UniqueTagsContributed,
           AVG(ATP.TotalTagQuestionScore) AS AverageTagQuestionScorePerUser,
           MAX(ATP.AvgTagQuestionViews) AS MaxTagQuestionViewsPerUser
    FROM PostTagAnalysis PTA
    JOIN AggregatedTagPerformance ATP ON PTA.TagName_Cleaned = ATP.TagName
    GROUP BY PTA.OwnerUserId
) ATP_UserTags ON UE.UserId = ATP_UserTags.UserId
WHERE UE.Reputation > 5000
  AND UE.QuestionCount > 20
  AND UE.AnswerCount > 50
  AND QDM.QuestionId IS NOT NULL
  AND UE.UserId NOT IN (SELECT UserId FROM ActiveUsersWithHighImpactTags WHERE UserId IS NOT NULL)
UNION ALL
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    'Emerging High Impact Tag Contributor' AS UserCategory,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.TotalPostScore,
    UE.TotalCommentScore,
    BM.GoldBadges,
    BM.SilverBadges,
    BM.BronzeBadges,
    BM.DaysBetweenFirstAndLastBadge,
    BM.FirstGoldBadgeName,
    QDM.QuestionId AS TopQuestionId,
    QDM.Title AS TopQuestionTitle,
    QDM.QuestionScore AS TopQuestionScore,
    QDM.QuestionViewCount AS TopQuestionViews,
    QDM.EngagementScore AS TopQuestionEngagementScore,
    QDM.TitleLength AS TopQuestionTitleLength,
    QDM.TitleCategory AS TopQuestionTitleCategory,
    QDM.DaysSinceLastActivity AS TopQuestionDaysSinceLastActivity,
    QDM.SelfAcceptedAnswer AS TopQuestionSelfAcceptedAnswer,
    QDM.AvgAnswerScoreForQuestion AS TopQuestionAvgAnswerScore,
    ATP_UserTags.UniqueTagsContributed,
    ATP_UserTags.AverageTagQuestionScorePerUser,
    ATP_UserTags.MaxTagQuestionViewsPerUser,
    (UE.TotalPostScore + UE.TotalCommentScore) * (1 + (COALESCE(BM.GoldBadges, 0) * 0.5 + COALESCE(BM.SilverBadges, 0) * 0.2 + COALESCE(BM.BronzeBadges, 0) * 0.1)) AS OverallImpactScore,
    CASE
        WHEN CHAR_LENGTH(UE.DisplayName) > 20 THEN SUBSTRING(UE.DisplayName FROM 1 FOR 17) || '...'
        ELSE UE.DisplayName
    END AS DisplayNameShortened,
    COALESCE(UE.LatestPostDate, UE.UserCreationDate) AS LastEngagementDate,
    COALESCE(BM.LastBadgeDate, UE.UserCreationDate) AS LastBadgeOrCreationDate
FROM UserEngagement UE
LEFT JOIN BadgeMilestones BM ON UE.UserId = BM.UserId
LEFT JOIN QuestionDetailedMetrics QDM ON UE.UserId = QDM.OwnerUserId AND QDM.UserQuestionScoreRank = 1
LEFT JOIN (
    SELECT PTA.OwnerUserId AS UserId,
           COUNT(DISTINCT PTA.TagName_Cleaned) AS UniqueTagsContributed,
           AVG(ATP.TotalTagQuestionScore) AS AverageTagQuestionScorePerUser,
           MAX(ATP.AvgTagQuestionViews) AS MaxTagQuestionViewsPerUser
    FROM PostTagAnalysis PTA
    JOIN AggregatedTagPerformance ATP ON PTA.TagName_Cleaned = ATP.TagName
    GROUP BY PTA.OwnerUserId
) ATP_UserTags ON UE.UserId = ATP_UserTags.UserId
JOIN ActiveUsersWithHighImpactTags AUHIT ON UE.UserId = AUHIT.UserId
WHERE UE.Reputation <= 5000
  AND UE.QuestionCount > 5
  AND UE.AnswerCount > 10
ORDER BY OverallImpactScore DESC, UserCategory DESC
LIMIT 200;