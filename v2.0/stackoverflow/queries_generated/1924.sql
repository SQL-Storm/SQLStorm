-- {"query": "1924.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3461} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        SUM(P.ViewCount) AS TotalPostViews,
        SUM(P.FavoriteCount) AS TotalPostFavorites,
        MAX(P.LastActivityDate) AS LastPostActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.CreationDate >= '2020-01-01' -- Focus on recent activity
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.Id END) AS EditCount, -- Title, Body, Tags edits/rollbacks
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS ClosedHistoryCount, -- Post closed event
        MAX(PH.CreationDate) AS LastEditDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15) -- Include various history types
    GROUP BY PH.PostId
),
UserPostEditSummary AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(COALESCE(PEA.EditCount, 0)) AS TotalPostsEdited,
        SUM(COALESCE(PEA.ClosedHistoryCount, 0)) AS TotalPostsClosedByHistory
    FROM Posts P
    LEFT JOIN PostEditActivity PEA ON P.Id = PEA.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT B.Name) AS DistinctBadges
    FROM Badges B
    GROUP BY B.UserId
),
AggregatedPostTags AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Ensure tags exist and are not empty
),
TagPopularity AS (
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TaggedPostsCount,
        SUM(P.ViewCount) AS TotalTagViewCount,
        SUM(P.Score) AS TotalTagScore
    FROM AggregatedPostTags APT
    JOIN Posts P ON APT.PostId = P.Id
    GROUP BY TagName
),
UserPostTagAggregates AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT APT.TagName) AS UniqueTagsContributed,
        SUM(CASE WHEN TP.TaggedPostsCount > 5000 THEN 1 ELSE 0 END) AS PostsInVeryPopularTags,
        SUM(TP.TotalTagScore) AS TotalScoreFromPopularTags
    FROM Posts P
    JOIN AggregatedPostTags APT ON P.Id = APT.PostId
    JOIN TagPopularity TP ON APT.TagName = TP.TagName
    WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
HighReputationEngagers AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        U.Reputation,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalPostScore,
        UE.TotalPostViews,
        COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
        UE.UserTotalUpVotes,
        UE.UserTotalDownVotes,
        CAST(COALESCE(UE.UserTotalUpVotes, 0) AS DECIMAL) / NULLIF(COALESCE(UE.UserTotalUpVotes, 0) + COALESCE(UE.UserTotalDownVotes, 0), 0) AS UpvoteRatio,
        (SELECT AVG(P_INNER.Score) FROM Posts P_INNER WHERE P_INNER.OwnerUserId = UE.UserId AND P_INNER.PostTypeId IN (1,2) AND P_INNER.CreationDate >= '2020-01-01') AS AveragePostScoreByUser, -- Correlated Subquery
        COALESCE(UPES.TotalPostsEdited, 0) AS TotalPostsEdited,
        COALESCE(UPES.TotalPostsClosedByHistory, 0) AS TotalPostsClosedByHistory,
        COALESCE(UPTA.UniqueTagsContributed, 0) AS UniqueTagsContributed,
        COALESCE(UPTA.PostsInVeryPopularTags, 0) AS PostsInVeryPopularTags,
        UE.LastPostActivityDate,
        U.Location,
        U.AboutMe,
        REPLACE(REPLACE(REPLACE(U.AboutMe, '<p>', ''), '</p>', ''), '<b>', '') AS CleanedAboutMeExcerpt, -- String manipulation
        CASE
            WHEN U.Location LIKE '%United States%' OR U.Location LIKE '%USA%' THEN 'USA'
            WHEN U.Location LIKE '%Canada%' THEN 'Canada'
            WHEN U.Location LIKE '%Germany%' THEN 'Germany'
            WHEN U.Location LIKE '%India%' THEN 'India'
            WHEN U.Location LIKE '%United Kingdom%' OR U.Location LIKE '%UK%' THEN 'UK'
            ELSE 'Other'
        END AS CountryGroup,
        CASE
            WHEN UE.TotalQuestions > 0 AND UE.TotalAnswers = 0 THEN 'Questioner'
            WHEN UE.TotalQuestions = 0 AND UE.TotalAnswers > 0 THEN 'Answerer'
            WHEN UE.TotalQuestions > 0 AND UE.TotalAnswers > 0 THEN 'Hybrid'
            ELSE 'NoPosts'
        END AS UserContributionType,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, UE.TotalPostScore DESC) AS OverallEngagementRank, -- Window function
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.UserId = UE.UserId AND C.CreationDate > UE.LastPostActivityDate - INTERVAL '30 days') AS RecentCommentsCount, -- Another correlated subquery
        LAG(U.Reputation, 1, 0) OVER (ORDER BY U.Reputation DESC, UE.TotalPostScore DESC) AS PrevRankReputation, -- Window function
        'High Reputation Contributor' AS ProfileType
    FROM UserEngagement UE
    JOIN Users U ON UE.UserId = U.Id
    LEFT JOIN UserPostEditSummary UPES ON UE.UserId = UPES.UserId
    LEFT JOIN UserBadgeSummary UBS ON UE.UserId = UBS.UserId
    LEFT JOIN UserPostTagAggregates UPTA ON UE.UserId = UPTA.UserId
    WHERE
        U.Reputation >= 5000
        AND UE.TotalQuestions + UE.TotalAnswers > 10
        AND COALESCE(UPTA.UniqueTagsContributed, 0) >= 3
    GROUP BY
        UE.UserId, UE.DisplayName, U.Reputation, UE.TotalQuestions, UE.TotalAnswers,
        UE.TotalPostScore, UE.TotalPostViews, UBS.GoldBadges, UBS.SilverBadges,
        UBS.BronzeBadges, UE.UserTotalUpVotes, UE.UserTotalDownVotes, UE.LastPostActivityDate,
        U.Location, U.AboutMe, UPES.TotalPostsEdited, UPES.TotalPostsClosedByHistory,
        UPTA.UniqueTagsContributed, UPTA.PostsInVeryPopularTags
),
NicheExperts AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        U.Reputation,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalPostScore,
        UE.TotalPostViews,
        COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
        UE.UserTotalUpVotes,
        UE.UserTotalDownVotes,
        CAST(COALESCE(UE.UserTotalUpVotes, 0) AS DECIMAL) / NULLIF(COALESCE(UE.UserTotalUpVotes, 0) + COALESCE(UE.UserTotalDownVotes, 0), 0) AS UpvoteRatio,
        (SELECT AVG(P_INNER.Score) FROM Posts P_INNER WHERE P_INNER.OwnerUserId = UE.UserId AND P_INNER.PostTypeId IN (1,2) AND P_INNER.CreationDate >= '2020-01-01') AS AveragePostScoreByUser,
        COALESCE(UPES.TotalPostsEdited, 0) AS TotalPostsEdited,
        COALESCE(UPES.TotalPostsClosedByHistory, 0) AS TotalPostsClosedByHistory,
        COALESCE(UPTA.UniqueTagsContributed, 0) AS UniqueTagsContributed,
        COALESCE(UPTA.PostsInVeryPopularTags, 0) AS PostsInVeryPopularTags,
        UE.LastPostActivityDate,
        U.Location,
        U.AboutMe,
        REPLACE(REPLACE(REPLACE(U.AboutMe, '<p>', ''), '</p>', ''), '<b>', '') AS CleanedAboutMeExcerpt,
        CASE
            WHEN U.Location LIKE '%United States%' OR U.Location LIKE '%USA%' THEN 'USA'
            WHEN U.Location LIKE '%Canada%' THEN 'Canada'
            WHEN U.Location LIKE '%Germany%' THEN 'Germany'
            WHEN U.Location LIKE '%India%' THEN 'India'
            WHEN U.Location LIKE '%United Kingdom%' OR U.Location LIKE '%UK%' THEN 'UK'
            ELSE 'Other'
        END AS CountryGroup,
        CASE
            WHEN UE.TotalQuestions > 0 AND UE.TotalAnswers = 0 THEN 'Questioner'
            WHEN UE.TotalQuestions = 0 AND UE.TotalAnswers > 0 THEN 'Answerer'
            WHEN UE.TotalQuestions > 0 AND UE.TotalAnswers > 0 THEN 'Hybrid'
            ELSE 'NoPosts'
        END AS UserContributionType,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, UE.TotalPostScore DESC) AS OverallEngagementRank,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.UserId = UE.UserId AND C.CreationDate > UE.LastPostActivityDate - INTERVAL '30 days') AS RecentCommentsCount,
        LAG(U.Reputation, 1, 0) OVER (ORDER BY U.Reputation DESC, UE.TotalPostScore DESC) AS PrevRankReputation,
        'Niche Expert' AS ProfileType
    FROM UserEngagement UE
    JOIN Users U ON UE.UserId = U.Id
    LEFT JOIN UserPostEditSummary UPES ON UE.UserId = UPES.UserId
    LEFT JOIN UserBadgeSummary UBS ON UE.UserId = UBS.UserId
    LEFT JOIN UserPostTagAggregates UPTA ON UE.UserId = UPTA.UserId
    WHERE
        U.Reputation BETWEEN 1000 AND 4999
        AND COALESCE(UE.TotalAnswers, 0) > 5
        AND COALESCE(UPTA.UniqueTagsContributed, 0) BETWEEN 1 AND 5
        AND COALESCE(UE.UserTotalUpVotes, 0) > 50
    GROUP BY
        UE.UserId, UE.DisplayName, U.Reputation, UE.TotalQuestions, UE.TotalAnswers,
        UE.TotalPostScore, UE.TotalPostViews, UBS.GoldBadges, UBS.SilverBadges,
        UBS.BronzeBadges, UE.UserTotalUpVotes, UE.UserTotalDownVotes, UE.LastPostActivityDate,
        U.Location, U.AboutMe, UPES.TotalPostsEdited, UPES.TotalPostsClosedByHistory,
        UPTA.UniqueTagsContributed, UPTA.PostsInVeryPopularTags
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    TotalQuestions,
    TotalAnswers,
    TotalPostScore,
    TotalPostViews,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    UserTotalUpVotes,
    UserTotalDownVotes,
    UpvoteRatio,
    AveragePostScoreByUser,
    TotalPostsEdited,
    TotalPostsClosedByHistory,
    UniqueTagsContributed,
    PostsInVeryPopularTags,
    LastPostActivityDate,
    Location,
    AboutMe,
    CleanedAboutMeExcerpt,
    CountryGroup,
    UserContributionType,
    OverallEngagementRank,
    RecentCommentsCount,
    PrevRankReputation,
    ProfileType
FROM HighReputationEngagers
UNION ALL -- Set operator
SELECT
    UserId,
    DisplayName,
    Reputation,
    TotalQuestions,
    TotalAnswers,
    TotalPostScore,
    TotalPostViews,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    UserTotalUpVotes,
    UserTotalDownVotes,
    UpvoteRatio,
    AveragePostScoreByUser,
    TotalPostsEdited,
    TotalPostsClosedByHistory,
    UniqueTagsContributed,
    PostsInVeryPopularTags,
    LastPostActivityDate,
    Location,
    AboutMe,
    CleanedAboutMeExcerpt,
    CountryGroup,
    UserContributionType,
    OverallEngagementRank,
    RecentCommentsCount,
    PrevRankReputation,
    ProfileType
FROM NicheExperts
ORDER BY Reputation DESC, TotalPostScore DESC, UserId
LIMIT 1000;
