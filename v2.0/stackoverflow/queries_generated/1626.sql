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
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore, -- NULL logic: COALESCE for comment score
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
        -- Complicated calculation: Days between first and last badge, only if more than one badge
        CASE WHEN MAX(BMR.BadgeRank) > 1 THEN EXTRACT(EPOCH FROM (MAX(BMR.Date) - MIN(BMR.Date))) / (60 * 60 * 24) ELSE NULL END AS DaysBetweenFirstAndLastBadge,
        -- Correlated subquery: get the name of the user's first gold badge
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
        TRIM(BOTH '<>' FROM T_unnest.Tag) AS TagName_Cleaned -- String expression: trim '<>'
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.PostTypeId IN (1, 4, 5)
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS T_unnest(Tag) -- String expressions: SUBSTRING, LENGTH, string_to_array
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
        PH_closed.CreationDate AS ActualClosedDate, -- Derived from PostHistory
        CRT.Name AS CloseReason,
        COALESCE(Q.FavoriteCount, 0) + COALESCE(Q.AnswerCount, 0) AS EngagementScore, -- NULL logic: COALESCE for FavoriteCount
        -- Window function: rank questions by score within user's questions
        RANK() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.CreationDate DESC) AS UserQuestionScoreRank,
        LENGTH(Q.Title) AS TitleLength, -- String expression: LENGTH
        (CASE WHEN Q.Title LIKE '%SQL%' OR Q.Title LIKE '%database%' THEN 'DB-Related' ELSE 'General' END) AS TitleCategory, -- String expression: LIKE
        EXTRACT(EPOCH FROM (NOW() - COALESCE(Q.LastEditDate, Q.CreationDate))) / (60 * 60 * 24) AS DaysSinceLastActivity, -- NULL logic: COALESCE for LastEditDate
        -- Correlated subquery: check if an answer by the same owner was accepted
        EXISTS (SELECT 1 FROM Posts A WHERE A.Id = Q.AcceptedAnswerId AND A.OwnerUserId = Q.OwnerUserId) AS SelfAcceptedAnswer,
        -- Correlated subquery: average score of answers to this question
        (SELECT AVG(A2.Score) FROM Posts A2 WHERE A2.ParentId = Q.Id AND A2.PostTypeId = 2) AS AvgAnswerScoreForQuestion
    FROM Posts Q
    LEFT JOIN PostHistory PH_closed ON Q.Id = PH_closed.PostId
        AND PH_closed.PostHistoryTypeId = 10 -- Post Closed event
    LEFT JOIN CloseReasonTypes CRT ON PH_closed.Comment::smallint = CRT.Id -- String to int cast, potential runtime error for non-numeric comments
    WHERE Q.PostTypeId = 1
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
      AND COALESCE(ATP.IsModeratorOnly, FALSE) = FALSE -- NULL logic: COALESCE for IsModeratorOnly
)
-- First main result set: "Top Impactful Users"
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
    -- Complicated calculation: Weighted overall impact score based on posts, comments, and badge class
    (UE.TotalPostScore + UE.TotalCommentScore) * (1 + (COALESCE(BM.GoldBadges, 0) * 0.5 + COALESCE(BM.SilverBadges, 0) * 0.2 + COALESCE(BM.BronzeBadges, 0) * 0.1)) AS OverallImpactScore,
    CASE
        WHEN LENGTH(UE.DisplayName) > 20 THEN LEFT(UE.DisplayName, 17) || '...' -- String expression: LEFT, concatenation
        ELSE UE.DisplayName
    END AS DisplayNameShortened,
    COALESCE(UE.LatestPostDate, UE.UserCreationDate) AS LastEngagementDate, -- NULL logic: COALESCE
    COALESCE(BM.LastBadgeDate, UE.UserCreationDate) AS LastBadgeOrCreationDate -- NULL logic: COALESCE
FROM UserEngagement UE
LEFT JOIN BadgeMilestones BM ON UE.UserId = BM.UserId
LEFT JOIN QuestionDetailedMetrics QDM ON UE.UserId = QDM.OwnerUserId AND QDM.UserQuestionScoreRank = 1
LEFT JOIN ( -- Subquery to aggregate tag performance metrics per user
    SELECT PTA.OwnerUserId AS UserId,
           COUNT(DISTINCT PTA.TagName_Cleaned) AS UniqueTagsContributed,
           AVG(ATP.TotalTagQuestionScore) AS AverageTagQuestionScorePerUser,
           MAX(ATP.AvgTagQuestionViews) AS MaxTagQuestionViewsPerUser
    FROM PostTagAnalysis PTA
    JOIN AggregatedTagPerformance ATP ON PTA.TagName_Cleaned = ATP.TagName
    GROUP BY PTA.OwnerUserId
) AS ATP_UserTags ON UE.UserId = ATP_UserTags.UserId
WHERE UE.Reputation > 5000
  AND UE.QuestionCount > 20
  AND UE.AnswerCount > 50
  AND QDM.QuestionId IS NOT NULL -- Exclude users without a top question in QDM
  AND UE.UserId NOT IN (SELECT UserId FROM ActiveUsersWithHighImpactTags WHERE UserId IS NOT NULL) -- Set operator: NOT IN (excluding from a set)
UNION ALL -- Set operator: UNION ALL
-- Second main result set: "Emerging High Impact Tag Contributors"
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
        WHEN LENGTH(UE.DisplayName) > 20 THEN LEFT(UE.DisplayName, 17) || '...'
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
) AS ATP_UserTags ON UE.UserId = ATP_UserTags.UserId
JOIN ActiveUsersWithHighImpactTags AUHIT ON UE.UserId = AUHIT.UserId -- Explicitly including users from the "high impact tags" set
WHERE UE.Reputation <= 5000 -- Distinguishing filter: lower reputation than the "Top Impactful Users"
  AND UE.QuestionCount > 5
  AND UE.AnswerCount > 10
ORDER BY OverallImpactScore DESC, UserCategory DESC
LIMIT 200; -- Limit applies to the entire UNION ALL result