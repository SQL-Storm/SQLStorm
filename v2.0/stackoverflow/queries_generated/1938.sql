-- {"query": "1938.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2914} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 AND V.UserId = U.Id THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 AND V.UserId = U.Id THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven,
        MAX(GREATEST(U.LastAccessDate, COALESCE(P.LastActivityDate, U.CreationDate), COALESCE(C.CreationDate, U.CreationDate))) AS LastObservedActivity,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersProvided
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId -- Votes given by the user
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS CurrentScore,
        P.ViewCount,
        P.CommentCount AS PostCommentCount,
        P.AnswerCount,
        P.FavoriteCount,
        COALESCE(P.Tags, '') AS Tags,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS TotalEditHistoryEntries,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 10 THEN 1 ELSE 0 END), 0) AS TotalDeletionVotes,
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60*60*24) AS PostAgeDays,
        (SELECT MAX(PH2.CreationDate) FROM PostHistory PH2 WHERE PH2.PostId = P.Id AND PH2.PostHistoryTypeId IN (4,5,6,8,9)) AS LastEditDateFromHistory
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3, 10) -- Only consider up/down/deletion votes for post metrics
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community-owned or deleted user posts for this analysis
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.CommentCount, P.AnswerCount, P.FavoriteCount, P.Tags
),
UserBadgeAchievements AS (
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN B.TagBased = TRUE THEN B.Name END) AS UniqueTagBadges,
        MAX(B.Date) AS LastBadgeDate,
        MIN(B.Date) AS FirstBadgeDate,
        COALESCE(EXTRACT(EPOCH FROM (NOW() - MAX(B.Date))) / (60*60*24*365.25), 9999) AS YearsSinceLastBadge
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
),
UserOverallMetrics AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.UserCreationDate,
        UAS.TotalPostsOwned,
        UAS.TotalCommentsMade,
        UAS.TotalUpvotesGiven,
        UAS.TotalDownvotesGiven,
        UBA.GoldBadges,
        UBA.SilverBadges,
        UBA.BronzeBadges,
        UBA.TotalBadges,
        UBA.YearsSinceLastBadge,
        COALESCE(SUM(PHM.TotalUpvotesReceived), 0) AS AllPostsUpvotesReceived,
        COALESCE(SUM(PHM.TotalDownvotesReceived), 0) AS AllPostsDownvotesReceived,
        COALESCE(SUM(PHM.ViewCount), 0) AS TotalViewsOnOwnedPosts,
        COALESCE(AVG(PHM.CurrentScore), 0) AS AveragePostScore,
        COALESCE(SUM(PHM.TotalEditHistoryEntries), 0) AS TotalEditsOnOwnedPosts,
        -- Complex calculation for engagement score:
        (UAS.Reputation * 0.5) + (UAS.TotalPostsOwned * 2) + (UAS.TotalCommentsMade * 0.75) + (UBA.GoldBadges * 10) + (UBA.SilverBadges * 5) + (UBA.BronzeBadges * 1) + (COALESCE(SUM(PHM.CurrentScore),0) * 0.1) AS EngagementScore,
        -- Conditional string expression
        CASE
            WHEN UAS.Reputation >= 10000 AND UBA.GoldBadges >= 3 THEN 'High-Rep Gold Tier'
            WHEN UAS.Reputation >= 5000 AND UBA.SilverBadges >= 5 THEN 'Mid-Rep Silver Tier'
            WHEN UAS.TotalPostsOwned > 500 OR UAS.TotalCommentsMade > 1000 THEN 'Prodigious Contributor'
            ELSE 'Standard User'
        END AS UserTier
    FROM UserActivitySummary UAS
    LEFT JOIN UserBadgeAchievements UBA ON UAS.UserId = UBA.UserId
    LEFT JOIN PostHistoricalMetrics PHM ON UAS.UserId = PHM.OwnerUserId
    GROUP BY
        UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserCreationDate, UAS.TotalPostsOwned,
        UAS.TotalCommentsMade, UAS.TotalUpvotesGiven, UAS.TotalDownvotesGiven, UBA.GoldBadges,
        UBA.SilverBadges, UBA.BronzeBadges, UBA.TotalBadges, UBA.YearsSinceLastBadge
),
RankedUsers AS (
    SELECT
        *,
        RANK() OVER (ORDER BY Reputation DESC, EngagementScore DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY TotalPostsOwned DESC) AS PostVolumeDecile,
        LAG(DisplayName, 1, 'N/A') OVER (ORDER BY Reputation DESC) AS PrevRankedUser,
        LEAD(DisplayName, 1, 'N/A') OVER (ORDER BY Reputation DESC) AS NextRankedUser,
        AVG(TotalUpvotesGiven) OVER (PARTITION BY UserTier) AS AvgUpvotesGivenInTier,
        SUM(TotalEditsOnOwnedPosts) OVER (ORDER BY UserCreationDate ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS RollingEditsSum
    FROM UserOverallMetrics
),
ControversialPosts AS (
    SELECT
        PHM.PostId,
        PHM.OwnerUserId,
        PHM.PostCreationDate,
        PHM.CurrentScore,
        PHM.ViewCount,
        PHM.Tags,
        PHM.TotalEditHistoryEntries,
        PHM.TotalUpvotesReceived,
        PHM.TotalDownvotesReceived,
        PHM.PostAgeDays,
        -- Correlated subquery to check if any comment on the post contains specific controversial keywords
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = PHM.PostId AND C.Text ILIKE ANY (ARRAY['%rant%', '%disagree%', '%controversial%', '%flame%', '%hate%'])) AS KeywordCommentsCount,
        -- Calculate a controversy ratio: (downvotes + deletion votes) / (upvotes + downvotes + deletion votes)
        CAST(PHM.TotalDownvotesReceived + PHM.TotalDeletionVotes AS NUMERIC) / NULLIF(PHM.TotalUpvotesReceived + PHM.TotalDownvotesReceived + PHM.TotalDeletionVotes, 0) AS ControversyRatio,
        -- Complicated string expression for tag analysis
        REPLACE(REPLACE(SUBSTRING(PHM.Tags FROM 2 FOR LENGTH(PHM.Tags) - 2), '><', ' '), ' ', ', ') AS FormattedTags
    FROM PostHistoricalMetrics PHM
    WHERE PHM.PostAgeDays > 30 -- Ensure posts had time for activity
      AND (PHM.TotalDownvotesReceived > 5 OR PHM.TotalEditHistoryEntries > 10) -- Heuristics for controversial/active posts
      AND PHM.OwnerUserId IS NOT NULL
)
-- Main Query combining user ranks and controversial posts data
SELECT
    RU.UserId,
    RU.DisplayName,
    RU.Reputation,
    RU.UserTier,
    RU.ReputationRank,
    RU.PostVolumeDecile,
    RU.EngagementScore,
    RU.GoldBadges,
    RU.SilverBadges,
    RU.BronzeBadges,
    RU.TotalPostsOwned,
    RU.TotalCommentsMade,
    RU.AllPostsUpvotesReceived,
    RU.AllPostsDownvotesReceived,
    RU.TotalEditsOnOwnedPosts,
    RU.AvgUpvotesGivenInTier,
    RU.PrevRankedUser,
    RU.NextRankedUser,
    RU.RollingEditsSum,
    CP.PostId AS ControversialPostId,
    CP.ControversyRatio,
    CP.KeywordCommentsCount,
    CP.FormattedTags AS ControversialPostTags,
    CASE
        WHEN CP.ControversyRatio > 0.4 AND CP.KeywordCommentsCount > 0 THEN 'Highly Contentious'
        WHEN CP.ControversyRatio > 0.25 THEN 'Moderately Disputed'
        WHEN CP.PostId IS NOT NULL THEN 'Minor Activity' -- If it's a controversial post, but not highly/moderately
        ELSE NULL -- Not a controversial post for this user
    END AS PostControversyLevel,
    -- NULL logic and complex predicate
    COALESCE(U.Location, 'Unknown Location') AS UserLocation,
    U.Views AS UserProfileViews,
    (SELECT COUNT(DISTINCT B2.Name) FROM Badges B2 WHERE B2.UserId = RU.UserId AND B2.Date > RU.UserCreationDate + INTERVAL '1 year') AS BadgesAfterFirstYear
FROM RankedUsers RU
LEFT JOIN ControversialPosts CP ON RU.UserId = CP.OwnerUserId
LEFT JOIN Users U ON RU.UserId = U.Id
WHERE
    (RU.Reputation > 5000 AND RU.TotalPostsOwned > 50)
    OR (RU.GoldBadges > 0 AND RU.YearsSinceLastBadge < 2)
    OR (CP.ControversyRatio IS NOT NULL AND CP.ControversyRatio > 0.3 AND CP.PostAgeDays > 60)
    -- More complex predicate using string functions and NULL handling
    AND (
        (U.Location IS NOT NULL AND U.Location LIKE '%United States%' AND U.AccountId IS NOT NULL)
        OR (U.EmailHash IS NOT NULL AND LENGTH(U.EmailHash) = 32)
        OR (RU.DisplayName IS NOT NULL AND NULLIF(UPPER(SUBSTRING(RU.DisplayName, 1, 1)), 'A') IS NOT NULL) -- DisplayName does not start with 'A' (case-insensitive)
    )
ORDER BY
    RU.ReputationRank ASC,
    CP.ControversyRatio DESC NULLS LAST,
    RU.EngagementScore DESC
LIMIT 1000;
