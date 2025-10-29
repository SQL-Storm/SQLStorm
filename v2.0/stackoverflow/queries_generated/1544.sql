-- {"query": "1544.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3355} 

WITH UserActivityMetrics AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        SUM(CASE WHEN P.PostTypeId = 2 THEN LENGTH(P.Body) ELSE 0 END) AS TotalAnswerBodyLength,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS NumAnswersForAvgLength
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostQualityStats AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        COALESCE(AVG(A.Score), 0.0) AS AvgAnswerScore,
        COUNT(DISTINCT A.Id) AS ActualAnswerCount,
        -- Correlated subquery to check for accepted answer existence for this question
        EXISTS (SELECT 1 FROM Posts ACC WHERE ACC.Id = Q.AcceptedAnswerId AND ACC.PostTypeId = 2) AS HasAcceptedAnswer,
        -- String processing for tags
        ARRAY_LENGTH(string_to_array(SUBSTRING(Q.Tags, 2, LENGTH(Q.Tags) - 2), '><'), 1) AS NumTags
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1 -- Only questions
    GROUP BY
        Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount,
        Q.AnswerCount, Q.FavoriteCount, Q.AcceptedAnswerId, Q.Tags
),
RecentActivityRankings AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(P.Id) AS PostsInLastYear,
        SUM(P.Score) AS ScoreInLastYear,
        MAX(P.CreationDate) AS LatestPostDate,
        RANK() OVER (ORDER BY COUNT(P.Id) DESC, SUM(P.Score) DESC) AS PostCountRank,
        -- Window function partitioned by a boolean expression
        ROW_NUMBER() OVER (PARTITION BY (U.Reputation > 10000) ORDER BY U.LastAccessDate DESC) AS RecentAccessRankInRepGroup
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
PostLifecycleEvents AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.CreationDate ELSE NULL END) AS LastDeletedDate,
        -- NULL logic and complex comparison for 'reopened after close'
        (MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) IS NOT NULL AND
         MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) IS NOT NULL AND
         MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) > MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END)) AS WasReopenedAfterClose,
        -- Calculation for time to first body edit
        COALESCE(EXTRACT(EPOCH FROM (MIN(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate ELSE NULL END) - MIN(CASE WHEN PH.PostHistoryTypeId = 2 THEN PH.CreationDate ELSE NULL END))) / 3600.0, 0.0) AS HoursToFirstEdit
    FROM PostHistory PH
    GROUP BY PH.PostId
),
UserQuestionQualitySummary AS (
    SELECT
        QuestionOwnerId AS UserId,
        COUNT(QuestionId) AS TotalQuestionsEver,
        COUNT(CASE WHEN AvgAnswerScore > 5 THEN QuestionId END) AS HighAvgScoreQuestions,
        COUNT(CASE WHEN HasAcceptedAnswer THEN QuestionId END) AS QuestionsWithAcceptedAnswer,
        COALESCE(AVG(QuestionScore), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(QuestionViewCount), 0.0) AS AvgQuestionViews,
        COALESCE(MAX(NumTags), 0) AS MaxTagsPerQuestion,
        SUM(CASE WHEN QuestionViewCount > 1000 AND QuestionAnswerCount > 5 THEN 1 ELSE 0 END) AS HighTrafficHighAnswerQuestionsCount
    FROM PostQualityStats
    WHERE QuestionOwnerId IS NOT NULL
    GROUP BY QuestionOwnerId
),
UserPostLifecycleSummary AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) FILTER (WHERE PLE.WasReopenedAfterClose IS TRUE) AS ReopenedPostsCount,
        COALESCE(AVG(PLE.HoursToFirstEdit), 0.0) AS AvgHoursToFirstEditOnPosts
    FROM Posts P
    JOIN PostLifecycleEvents PLE ON P.Id = PLE.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
)
-- Main complex query
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    COALESCE(UAM.TotalPosts, 0) AS TotalPostsByOwner,
    COALESCE(UAM.TotalQuestions, 0) AS QuestionsAsked,
    COALESCE(UAM.TotalAnswers, 0) AS AnswersGiven,
    COALESCE(UAM.TotalPostScore, 0) AS TotalContributionScore,
    COALESCE(UAM.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(UAM.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(UAM.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(UAM.BronzeBadges, 0) AS UserBronzeBadges,
    (CASE
        WHEN UAM.NumAnswersForAvgLength > 0
        THEN CAST(UAM.TotalAnswerBodyLength AS DECIMAL) / UAM.NumAnswersForAvgLength
        ELSE 0.0
    END) AS AvgAnswerLength, -- Complex calculation with division and NULL handling
    (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (3600 * 24 * 365.25)) AS YearsOnPlatform, -- Date arithmetic
    COALESCE(R.PostsInLastYear, 0) AS RecentPostsCount,
    COALESCE(R.ScoreInLastYear, 0) AS RecentScoreSum,
    R.PostCountRank AS UserRecentActivityRank,
    COALESCE(R.RecentAccessRankInRepGroup, 0) AS RecentAccessRankInSpecificRepGroup,
    COALESCE(UQQS.HighAvgScoreQuestions, 0) AS QuestionsWithHighAvgAnswerScore,
    COALESCE(UQQS.QuestionsWithAcceptedAnswer, 0) AS QuestionsWithAcceptedAnswer,
    COALESCE(UQQS.HighTrafficHighAnswerQuestionsCount, 0) AS HighTrafficHighAnswerQuestions,
    COALESCE(UPLS.ReopenedPostsCount, 0) AS UserReopenedPostsCount,
    COALESCE(UPLS.AvgHoursToFirstEditOnPosts, 0.0) AS UserAvgHoursToFirstEdit,
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile, -- Window function: NTILE
    COALESCE(SUBSTRING(U.WebsiteUrl,
              CASE WHEN POSITION('://' IN U.WebsiteUrl) > 0 THEN POSITION('://' IN U.WebsiteUrl) + 3 ELSE 1 END,
              CASE WHEN POSITION('/' IN SUBSTRING(U.WebsiteUrl, CASE WHEN POSITION('://' IN U.WebsiteUrl) > 0 THEN POSITION('://' IN U.WebsiteUrl) + 3 ELSE 1 END)) > 0
                   THEN POSITION('/' IN SUBSTRING(U.WebsiteUrl, CASE WHEN POSITION('://' IN U.WebsiteUrl) > 0 THEN POSITION('://' IN U.WebsiteUrl) + 3 ELSE 1 END)) - 1
                   ELSE LENGTH(SUBSTRING(U.WebsiteUrl, CASE WHEN POSITION('://' IN U.WebsiteUrl) > 0 THEN POSITION('://' IN U.WebsiteUrl) + 3 ELSE 1 END))
              END), 'N/A') AS WebsiteDomain, -- String expression for domain extraction with NULL handling
    COALESCE(U.Location, 'Unknown') || ' - ' || (CASE WHEN U.Location IS NULL THEN 'No Location Provided' ELSE 'Location Provided' END) AS FormattedLocationInfo, -- Concatenation with NULL logic
    (SELECT STRING_AGG(DISTINCT T.TagName, ', ') FILTER (WHERE T.TagName IS NOT NULL)
     FROM Posts TP
     -- Using LIKE for tag matching, potentially slow but demonstrates string ops
     JOIN Tags T ON TP.Tags LIKE '%' || T.TagName || '%'
     WHERE TP.OwnerUserId = U.Id AND TP.PostTypeId = 1 AND TP.CreationDate >= (CURRENT_DATE - INTERVAL '6 months')
     LIMIT 5) AS RecentQuestionTags, -- Correlated subquery for aggregated tags
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Name ILIKE '%suffrage%') AS SuffrageBadgeCount, -- Correlated subquery for specific badge count
    (CASE
        WHEN COALESCE(UAM.TotalPosts, 0) > 500
         AND COALESCE(UAM.TotalPostScore, 0) > 10000
         AND COALESCE(UAM.GoldBadges, 0) > 5
         AND (UAM.NumAnswersForAvgLength > 0 AND CAST(UAM.TotalAnswerBodyLength AS DECIMAL) / UAM.NumAnswersForAvgLength > 300)
         AND COALESCE(UQQS.HighAvgScoreQuestions, 0) > 10
        THEN TRUE
        ELSE FALSE
    END) AS IsSuperActiveUser, -- Complex predicate expression
    'DetailedUserMetrics' AS MetricGroup
FROM Users U
LEFT JOIN UserActivityMetrics UAM ON U.Id = UAM.UserId
LEFT JOIN RecentActivityRankings R ON U.Id = R.UserId
LEFT JOIN UserQuestionQualitySummary UQQS ON U.Id = UQQS.UserId
LEFT JOIN UserPostLifecycleSummary UPLS ON U.Id = UPLS.UserId
WHERE U.Reputation > 5000 OR COALESCE(UAM.TotalPosts, 0) > 100 -- Filtering for engaged users
AND U.LastAccessDate >= (CURRENT_DATE - INTERVAL '2 years')

UNION ALL

-- Second part of the query using UNION ALL for a different user segment
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    COALESCE(UAM.TotalPosts, 0) AS TotalPostsByOwner,
    COALESCE(UAM.TotalQuestions, 0) AS QuestionsAsked,
    COALESCE(UAM.TotalAnswers, 0) AS AnswersGiven,
    COALESCE(UAM.TotalPostScore, 0) AS TotalContributionScore,
    COALESCE(UAM.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(UAM.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(UAM.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(UAM.BronzeBadges, 0) AS UserBronzeBadges,
    NULL AS AvgAnswerLength, -- NULL values to match column types for UNION ALL
    NULL AS YearsOnPlatform,
    NULL AS RecentPostsCount,
    NULL AS RecentScoreSum,
    NULL AS UserRecentActivityRank,
    NULL AS RecentAccessRankInSpecificRepGroup,
    NULL AS QuestionsWithHighAvgAnswerScore,
    NULL AS QuestionsWithAcceptedAnswer,
    NULL AS HighTrafficHighAnswerQuestions,
    NULL AS UserReopenedPostsCount,
    NULL AS UserAvgHoursToFirstEdit,
    NULL AS ReputationDecile,
    NULL AS WebsiteDomain,
    NULL AS FormattedLocationInfo,
    NULL AS RecentQuestionTags,
    NULL AS SuffrageBadgeCount,
    FALSE AS IsSuperActiveUser,
    'SpecialEngagementUsers' AS MetricGroup
FROM Users U
LEFT JOIN UserActivityMetrics UAM ON U.Id = UAM.UserId
WHERE (COALESCE(UAM.TotalAnswers, 0) > 0 AND COALESCE(UAM.GoldBadges, 0) > 0) -- Users with answers and gold badges
   OR (COALESCE(UAM.TotalQuestions, 0) > COALESCE(UAM.TotalAnswers, 0) * 2 AND U.Reputation > 1000) -- Users who ask significantly more than they answer, with decent rep
ORDER BY Reputation DESC, UserId ASC
LIMIT 1000;
