-- {"query": "1005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2996} 

WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPosts,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalComments,
        -- Total votes received on user's posts
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 AND V.PostId = P.Id THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 AND V.PostId = P.Id THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceived,
        -- Accepted answers for user's questions OR user's answers that were accepted
        COALESCE(COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN P.AcceptedAnswerId ELSE NULL END), 0) AS AcceptedAnswerForOwnQuestions,
        COALESCE(COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P_Parent.AcceptedAnswerId = P.Id THEN P.Id ELSE NULL END), 0) AS OwnAnswerAcceptedCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts P_Parent ON P.ParentId = P_Parent.Id -- For checking if an answer by U was accepted
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId -- Votes on user's posts
    GROUP BY U.Id
),
PostHistoryDetails AS (
    -- Aggregates various complex post history events per PostId
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (35, 36) THEN 1 ELSE NULL END) AS MigrationEvents,
        COUNT(DISTINCT CASE WHEN PH.UserId != P.OwnerUserId AND PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.UserId ELSE NULL END) AS UniqueOtherEditors,
        STRING_AGG(DISTINCT U.DisplayName, '; ') FILTER (WHERE PH.UserId != P.OwnerUserId AND PH.PostHistoryTypeId IN (4,5,6)) AS OtherEditorsList
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    LEFT JOIN Users U ON PH.UserId = U.Id
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 35, 36) -- Edit (Title/Body/Tags), Closed, Reopened, Migrated
    GROUP BY PH.PostId
),
UserHistoryAggregates AS (
    -- Summarizes complex post history events per User
    SELECT
        P.OwnerUserId AS UserId,
        COALESCE(SUM(PHD.CloseEvents), 0) AS UserTotalCloseEvents,
        COALESCE(SUM(PHD.ReopenEvents), 0) AS UserTotalReopenEvents,
        COALESCE(SUM(PHD.MigrationEvents), 0) AS UserTotalMigrationEvents,
        COALESCE(SUM(PHD.UniqueOtherEditors), 0) AS UserTotalUniqueOtherEditors,
        STRING_AGG(DISTINCT PHD.OtherEditorsList, '; ') FILTER (WHERE PHD.OtherEditorsList IS NOT NULL AND PHD.OtherEditorsList <> '') AS CombinedOtherEditors
    FROM Posts P
    JOIN PostHistoryDetails PHD ON P.Id = PHD.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserTopTags AS (
    -- Identifies and aggregates the top 3 tags for each user based on post count
    SELECT
        UserId,
        STRING_AGG(TagName, ', ' ORDER BY TagPostCount DESC) AS TopTagsString,
        MAX(TagPostCount) AS MaxPostsInSingleTag
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagName,
            COUNT(P.Id) AS TagPostCount,
            ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(P.Id) DESC, UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) as rn
        FROM Posts P
        WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
        GROUP BY P.OwnerUserId, UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))
    ) AS UserTagCounts
    WHERE rn <= 3
    GROUP BY UserId
),
UserBadgeMetrics AS (
    -- Calculates various badge counts per user
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 ELSE NULL END) AS GoldBadgeCount,
        COUNT(CASE WHEN B.Class = 2 THEN 1 ELSE NULL END) AS SilverBadgeCount,
        COUNT(CASE WHEN B.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadgeCount,
        COUNT(CASE WHEN B.TagBased = TRUE THEN 1 ELSE NULL END) AS TagBasedBadgeCount
    FROM Badges B
    GROUP BY B.UserId
)
-- First population: High-Reputation, Engaged, and Historically Active Users
SELECT
    U.Id AS UserID,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    U.Views AS ProfileViews,
    UEM.TotalPosts,
    UEM.QuestionCount,
    UEM.AnswerCount,
    UEM.TotalPostScore,
    UEM.TotalComments,
    UEM.TotalUpvotesReceived,
    UEM.TotalDownvotesReceived,
    UEM.AcceptedAnswerForOwnQuestions + UEM.OwnAnswerAcceptedCount AS TotalAcceptedAnswers,
    UHA.UserTotalCloseEvents,
    UHA.UserTotalReopenEvents,
    UHA.UserTotalMigrationEvents,
    UHA.UserTotalUniqueOtherEditors,
    UTT.TopTagsString,
    UTT.MaxPostsInSingleTag,
    -- Complex Calculations
    CAST(UEM.TotalPostScore AS NUMERIC) / NULLIF(UEM.TotalPosts + UEM.TotalComments, 0) AS AvgEngagementScore,
    LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
    COALESCE(UPPER(SUBSTRING(U.Location, 1, 10)), 'N/A') AS ShortLocationUpper,
    -- Correlated Subquery: Highest score of an answer posted by this user
    (SELECT COALESCE(MAX(P_Ans.Score), 0) FROM Posts P_Ans WHERE P_Ans.OwnerUserId = U.Id AND P_Ans.PostTypeId = 2) AS CorrelatedMaxPostScore,
    -- Window Functions
    RANK() OVER (ORDER BY U.Reputation DESC, UEM.TotalPostScore DESC) AS RankMetric,
    NTILE(10) OVER (ORDER BY UEM.TotalPosts + UEM.TotalComments DESC, U.LastAccessDate DESC) AS DecileMetric,
    LAG(U.CreationDate, 1, '1970-01-01 00:00:00') OVER (ORDER BY U.Reputation DESC) AS LaggedDateMetric,
    -- NULL Logic & String Expression with CASE
    CASE
        WHEN U.AboutMe IS NULL OR TRIM(U.AboutMe) = '' THEN 'No AboutMe Provided'
        WHEN LENGTH(U.AboutMe) < 50 THEN 'Short AboutMe'
        ELSE 'Detailed AboutMe'
    END AS CategoricalInfo,
    REPLACE(REPLACE(U.DisplayName, ' ', '_'), '-', '__') AS ModifiedDisplayName,
    COALESCE(UBM.GoldBadgeCount, 0) AS BadgeMetric1,
    COALESCE(UBM.SilverBadgeCount, 0) AS BadgeMetric2
FROM Users U
LEFT JOIN UserEngagementMetrics UEM ON U.Id = UEM.UserId
LEFT JOIN UserHistoryAggregates UHA ON U.Id = UHA.UserId
LEFT JOIN UserTopTags UTT ON U.Id = UTT.UserId
LEFT JOIN UserBadgeMetrics UBM ON U.Id = UBM.UserId
WHERE U.Reputation >= 5000
  AND U.LastAccessDate >= CURRENT_DATE - INTERVAL '1 year'
  AND UEM.TotalPosts >= 50
  AND (UHA.UserTotalUniqueOtherEditors >= 3 OR UEM.AcceptedAnswerForOwnQuestions + UEM.OwnAnswerAcceptedCount >= 10)
  AND (U.WebsiteUrl IS NOT NULL OR U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 100)

UNION ALL

-- Second population: Recent, Active Contributors focused on specific tags
SELECT
    U.Id AS UserID,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    U.Views AS ProfileViews,
    UEM.TotalPosts,
    UEM.QuestionCount,
    UEM.AnswerCount,
    UEM.TotalPostScore,
    UEM.TotalComments,
    UEM.TotalUpvotesReceived,
    UEM.TotalDownvotesReceived,
    UEM.AcceptedAnswerForOwnQuestions + UEM.OwnAnswerAcceptedCount AS TotalAcceptedAnswers,
    UHA.UserTotalCloseEvents,
    UHA.UserTotalReopenEvents,
    UHA.UserTotalMigrationEvents,
    UHA.UserTotalUniqueOtherEditors,
    UTT.TopTagsString,
    UTT.MaxPostsInSingleTag,
    CAST(U.UpVotes AS NUMERIC) / NULLIF(U.UpVotes + U.DownVotes, 0) AS AvgUpvoteRatioGiven, -- Different calculation
    LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
    COALESCE(LOWER(SUBSTRING(U.Location, 1, 10)), 'n/a') AS ShortLocationUpper, -- Different string func
    -- Correlated Subquery: Highest score of a question asked by this user
    (SELECT COALESCE(MAX(P_Q.Score), 0) FROM Posts P_Q WHERE P_Q.OwnerUserId = U.Id AND P_Q.PostTypeId = 1) AS CorrelatedMaxPostScore,
    RANK() OVER (ORDER BY UEM.TotalUpvotesReceived DESC, U.CreationDate) AS RankMetric,
    NTILE(5) OVER (ORDER BY UEM.QuestionCount DESC, UEM.AnswerCount DESC) AS DecileMetric,
    LAG(U.LastAccessDate, 1, '1970-01-01 00:00:00') OVER (ORDER BY UEM.TotalPosts ASC) AS LaggedDateMetric,
    CASE
        WHEN U.Views >= 500 THEN 'High Profile Views'
        WHEN U.Views >= 100 THEN 'Moderate Profile Views'
        ELSE 'Low Profile Views'
    END AS CategoricalInfo, -- Different CASE logic
    REPLACE(U.DisplayName, ' ', '-') AS ModifiedDisplayName,
    COALESCE(UBM.BronzeBadgeCount, 0) AS BadgeMetric1,
    COALESCE(UBM.TagBasedBadgeCount, 0) AS BadgeMetric2
FROM Users U
LEFT JOIN UserEngagementMetrics UEM ON U.Id = UEM.UserId
LEFT JOIN UserHistoryAggregates UHA ON U.Id = UHA.UserId
LEFT JOIN UserTopTags UTT ON U.Id = UTT.UserId
LEFT JOIN UserBadgeMetrics UBM ON U.Id = UBM.UserId
WHERE U.Reputation BETWEEN 500 AND 4999
  AND U.CreationDate >= CURRENT_DATE - INTERVAL '2 year'
  AND UEM.TotalPosts >= 10
  AND UTT.TopTagsString IS NOT NULL AND (UTT.TopTagsString LIKE '%sql%' OR UTT.TopTagsString LIKE '%python%')
  AND (U.AboutMe IS NOT NULL AND U.AboutMe LIKE '%developer%')
ORDER BY Reputation DESC, UserID
LIMIT 2000;
