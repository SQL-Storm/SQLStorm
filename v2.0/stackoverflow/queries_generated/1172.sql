-- {"query": "1172.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3074} 

WITH UserPostContribution AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(COALESCE(P.Score, 0)) AS AvgPostScore,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoriteCounts,
        MAX(P.CreationDate) AS LastPostDate,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.Location,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.Location, U.CreationDate, U.LastAccessDate
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserLatestGoldBadge AS (
    SELECT
        UserId,
        Name AS LatestGoldBadgeName,
        Date AS LatestGoldBadgeDate
    FROM (
        SELECT
            B.UserId,
            B.Name,
            B.Date,
            ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Date DESC) AS rn
        FROM Badges B
        WHERE B.Class = 1
    ) AS Sub
    WHERE rn = 1
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.CommentCount AS PostCommentCount,
        P.AnswerCount AS PostAnswerCount,
        P.FavoriteCount AS PostFavoriteCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCountReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCountReceived,
        SUM(CASE WHEN V.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalRegularVotesReceived,
        COUNT(DISTINCT C.Id) AS NumComments,
        COUNT(DISTINCT PH.Id) AS NumPostHistoryEntries
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.CommentCount, P.AnswerCount, P.FavoriteCount
),
TagUsageAnalysisRaw AS (
    SELECT
        P.Id AS PostId,
        unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags != '' AND P.PostTypeId = 1
),
AggregatedTagStats AS (
    SELECT
        TUA.TagName,
        COUNT(DISTINCT TUA.PostId) AS TaggedPostsCount,
        SUM(PEM.PostScore) AS TotalTagScore,
        AVG(PEM.PostViewCount) AS AvgTagViewCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT TUA.PostId) DESC, SUM(PEM.PostScore) DESC) AS TagRank
    FROM TagUsageAnalysisRaw TUA
    JOIN PostEngagementMetrics PEM ON TUA.PostId = PEM.PostId
    GROUP BY TUA.TagName
),
PostClosureAnalysis AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosedEver,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopenedEver,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 END) AS ClosureEventsCount,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)) AS FirstClosureDate,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 11) AS LatestReopenDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 101, 102, 103, 104, 105)
    GROUP BY PH.PostId
),
LocationAvgScore AS (
    SELECT
        U.Location,
        AVG(P.Score) AS AvgScoreForLocation
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 1 AND U.Location IS NOT NULL
    GROUP BY U.Location
),
-- Set Operator: Combining top questions and top answers based on score and view count
TopImpactfulPosts AS (
    -- Top Questions
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        'Question' AS PostCategory,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavorites -- Correlated subquery
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Score > 100 AND P.ViewCount > 5000
    UNION ALL
    -- Top Answers
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        LEFT(COALESCE(P.Body, 'No Body'), 100) AS Title, -- Use part of body for answers, handle NULL
        P.CreationDate,
        P.Score,
        NULL AS ViewCount, -- Answers don't have direct view counts
        P.OwnerUserId,
        'Answer' AS PostCategory,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavorites -- Correlated subquery
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.Score > 50
)
SELECT
    UPC.UserId,
    UPC.UserName,
    UPC.Reputation,
    UPC.TotalPosts,
    UPC.TotalQuestions,
    UPC.TotalAnswers,
    COALESCE(UPC.AvgPostScore, 0.0) AS UserAvgPostScore,
    UPC.TotalFavoriteCounts,
    UPC.LastPostDate,
    UBS.TotalBadges,
    UBS.GoldBadges,
    UBS.SilverBadges,
    ULGB.LatestGoldBadgeName,
    ULGB.LatestGoldBadgeDate,
    UPC.UserCreationDate,
    UPC.LastAccessDate,
    U.WebsiteUrl,
    UPC.Location,
    COALESCE(LAS.AvgScoreForLocation, 0.0) AS LocationAverageQuestionScore, -- Non-correlated CTE result
    U.AboutMe IS NOT NULL AS HasAboutMe,
    UPC.UserProfileViews,
    UPC.UserUpVotesGiven,
    UPC.UserDownVotesGiven,
    SUM(CASE WHEN PEM.PostTypeId = 1 THEN PEM.UpVoteCountReceived ELSE 0 END) AS TotalQuestionUpVotesReceived,
    SUM(CASE WHEN PEM.PostTypeId = 2 THEN PEM.UpVoteCountReceived ELSE 0 END) AS TotalAnswerUpVotesReceived,
    SUM(CASE WHEN PEM.PostTypeId = 1 AND PCA.WasClosedEver = 1 THEN 1 ELSE 0 END) AS QuestionsClosedCount,
    SUM(CASE WHEN PEM.PostTypeId = 1 AND PCA.WasReopenedEver = 1 THEN 1 ELSE 0 END) AS QuestionsReopenedCount,
    -- Window functions for user ranking
    RANK() OVER (ORDER BY UPC.Reputation DESC, UPC.TotalQuestions DESC, UPC.TotalAnswers DESC) AS UserOverallRank,
    NTILE(10) OVER (ORDER BY UPC.Reputation DESC) AS ReputationDecile,
    -- Another correlated subquery
    (SELECT P_Q.Title FROM Posts P_Q WHERE P_Q.OwnerUserId = UPC.UserId AND P_Q.PostTypeId = 1 ORDER BY P_Q.ViewCount DESC, P_Q.Score DESC LIMIT 1) AS MostViewedQuestionTitle,
    -- A complex conditional calculation demonstrating NULL logic and type casting
    CAST(
        CASE
            WHEN UPC.TotalQuestions > 0 AND UPC.TotalAnswers > 0
            THEN (CAST(UPC.TotalAnswers AS DECIMAL) / UPC.TotalQuestions) * (COALESCE(UBS.GoldBadges, 0) + COALESCE(UBS.SilverBadges, 0) * 0.5)
            WHEN UPC.TotalAnswers > 0 THEN UPC.TotalAnswers * 0.1
            ELSE 0
        END AS DECIMAL(10,2)
    ) AS AnswerToQuestionBadgeRatio,
    -- String expression and NULL logic in SELECT
    UPPER(LEFT(COALESCE(UPC.Location, 'UNKNOWN LOCATION'), 15)) AS ProcessedLocationPrefix,
    -- Join with TopImpactfulPosts to see how many high-impact posts a user has
    COUNT(DISTINCT TIP.PostId) AS NumHighImpactPosts,
    SUM(TIP.Score) AS SumHighImpactPostScores,
    -- Example of an elaborate predicate with date functions and string matching
    MAX(CASE WHEN PH_Latest.PostHistoryTypeId = 52 AND AGE(NOW(), PH_Latest.CreationDate) < INTERVAL '3 months' THEN 1 ELSE 0 END) AS HasRecentHotQuestion
FROM Users U
LEFT JOIN UserPostContribution UPC ON U.Id = UPC.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN UserLatestGoldBadge ULGB ON U.Id = ULGB.UserId
LEFT JOIN PostEngagementMetrics PEM ON U.Id = PEM.OwnerUserId
LEFT JOIN PostClosureAnalysis PCA ON PEM.PostId = PCA.PostId AND PEM.PostTypeId = 1 -- Only questions are closed
LEFT JOIN LocationAvgScore LAS ON UPC.Location = LAS.Location
LEFT JOIN TopImpactfulPosts TIP ON U.Id = TIP.OwnerUserId
LEFT JOIN PostHistory PH_Latest ON U.Id = PH_Latest.UserId -- For the "HasRecentHotQuestion" check
WHERE
    UPC.UserCreationDate >= '2015-01-01' -- Filter for more recent users
    AND (UPC.Reputation > 1000 OR UPC.TotalPosts > 50) -- Basic activity filter
    AND (
        (UPC.LastPostDate IS NOT NULL AND UPC.LastPostDate > UPC.LastAccessDate - INTERVAL '6 months') -- Recently active based on posts
        OR UPC.LastAccessDate > '2023-01-01' -- Or accessed recently regardless of posts
    )
    AND U.DisplayName IS NOT NULL AND LENGTH(TRIM(U.DisplayName)) > 3 -- Valid display name and not just spaces
    AND COALESCE(U.WebsiteUrl, '') NOT LIKE '%example.com%' -- Filter out potential spam/test users
    AND (UPC.Location IS NULL OR UPC.Location NOT LIKE '%test%') -- NULL logic and string expression
GROUP BY
    UPC.UserId, UPC.UserName, UPC.Reputation, UPC.TotalPosts, UPC.TotalQuestions, UPC.TotalAnswers, UPC.AvgPostScore,
    UPC.TotalFavoriteCounts, UPC.LastPostDate, UBS.TotalBadges, UBS.GoldBadges, UBS.SilverBadges,
    ULGB.LatestGoldBadgeName, ULGB.LatestGoldBadgeDate, UPC.UserCreationDate, UPC.LastAccessDate, U.WebsiteUrl, UPC.Location,
    LAS.AvgScoreForLocation, U.AboutMe, UPC.UserProfileViews, UPC.UserUpVotesGiven, UPC.UserDownVotesGiven
ORDER BY UserOverallRank ASC, TotalQuestionUpVotesReceived DESC, NumHighImpactPosts DESC
LIMIT 1000;
