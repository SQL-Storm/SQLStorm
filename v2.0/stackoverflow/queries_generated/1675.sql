-- {"query": "1675.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3714} 

WITH UserBaseMetrics AS (
    -- Aggregates basic user statistics related to posts and comments, handling NULLs gracefully
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersGiven,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score ELSE NULL END) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(COALESCE(P.LastActivityDate, P.CreationDate, U.LastAccessDate)) AS LatestUserActivityOnPosts,
        MIN(COALESCE(P.CreationDate, U.CreationDate)) AS EarliestPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostEngagementMetrics AS (
    -- Focus on post-specific metrics, including edits, close/reopen, community ownership, and links
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        COALESCE(P.ViewCount, 0) AS ViewCount,
        COALESCE(P.CommentCount, 0) AS CommentCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.Title,
        P.Tags,
        P.ClosedDate,
        P.CommunityOwnedDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS EditCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.UserId END) AS DistinctEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS BecameCommunityOwned,
        COUNT(DISTINCT PL_Linked.PostId) AS NumberOfLinkedPosts,
        COUNT(DISTINCT PL_Duplicate.PostId) AS NumberOfDuplicatePosts,
        SUM(COALESCE(V.BountyAmount, 0)) AS TotalBountyOnPost
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks AS PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
    LEFT JOIN PostLinks AS PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
    LEFT JOIN Votes AS V ON P.Id = V.PostId AND V.VoteTypeId IN (8,9) -- Bounty related votes
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.LastActivityDate,
        P.Score, P.ViewCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.ClosedDate, P.CommunityOwnedDate
),
UserBadgeSummary AS (
    -- Summarizes badge counts per user, categorizing by class and type
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        COUNT(CASE WHEN B.TagBased = TRUE THEN B.Id END) AS TagBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
RankedPostsByOwner AS (
    -- Ranks posts for each user and post type, including window functions and a correlated subquery
    SELECT
        PEM.PostId,
        PEM.PostTypeId,
        PEM.OwnerUserId,
        PEM.PostCreationDate,
        PEM.PostScore,
        PEM.ViewCount,
        PEM.LastActivityDate,
        PEM.EditCount,
        PEM.WasClosed,
        PEM.BecameCommunityOwned,
        ROW_NUMBER() OVER (PARTITION BY PEM.OwnerUserId, PEM.PostTypeId ORDER BY PEM.PostScore DESC, PEM.PostCreationDate DESC) AS Rnk_PostScoreByType,
        DENSE_RANK() OVER (PARTITION BY PEM.OwnerUserId ORDER BY PEM.ViewCount DESC, PEM.PostCreationDate DESC) AS Drnk_PostViewCount,
        LAG(PEM.PostScore, 1, 0) OVER (PARTITION BY PEM.OwnerUserId ORDER BY PEM.PostCreationDate) AS PrevPostScore,
        -- Correlated subquery: checks if the owner has any other post created within 24 hours of the current post
        EXISTS (
            SELECT 1
            FROM Posts AS P_inner
            WHERE P_inner.OwnerUserId = PEM.OwnerUserId
              AND P_inner.Id != PEM.PostId
              AND P_inner.CreationDate BETWEEN (PEM.PostCreationDate - INTERVAL '24 hours') AND (PEM.PostCreationDate + INTERVAL '24 hours')
        ) AS HasOtherPostsNearCreation
    FROM PostEngagementMetrics AS PEM
    WHERE PEM.PostTypeId IN (1, 2) -- Only questions and answers for this ranking
),
UserPostTagAggregates AS (
    -- Combines user and post-level aggregates, introducing complex calculations, string expressions, and NULL logic
    SELECT
        UBM.UserId,
        UBM.DisplayName,
        UBM.Reputation,
        UBM.CreationDate AS UserCreationDate,
        UBM.LastAccessDate,
        UBM.TotalPostsOwned,
        UBM.TotalQuestionsAsked,
        UBM.TotalAnswersGiven,
        COALESCE(UBM.TotalCommentsMade, 0) AS TotalComments,
        COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
        SUM(CASE WHEN RPBO.PostTypeId = 1 AND RPBO.Rnk_PostScoreByType = 1 THEN RPBO.PostScore ELSE 0 END) AS TopQuestionScore,
        SUM(CASE WHEN RPBO.PostTypeId = 2 AND RPBO.Rnk_PostScoreByType = 1 THEN RPBO.PostScore ELSE 0 END) AS TopAnswerScore,
        CAST(UBM.TotalAnswersGiven AS DECIMAL(10,2)) / NULLIF(UBM.TotalQuestionsAsked, 0) AS AnswerToQuestionRatio,
        EXTRACT(EPOCH FROM (COALESCE(UBM.EarliestPostDate, UBM.UserCreationDate) - UBM.UserCreationDate)) / 3600.0 AS HoursToFirstPost, -- Time in hours
        -- String operations and complex CASE for PrimaryTechContribution based on any post tags owned by the user
        CASE
            WHEN EXISTS (SELECT 1 FROM Posts P_tags WHERE P_tags.OwnerUserId = UBM.UserId AND P_tags.Tags LIKE '%<sql>%') THEN 'SQL Enthusiast'
            WHEN EXISTS (SELECT 1 FROM Posts P_tags WHERE P_tags.OwnerUserId = UBM.UserId AND P_tags.Tags LIKE '%<javascript>%') THEN 'JavaScript Dev'
            WHEN EXISTS (SELECT 1 FROM Posts P_tags WHERE P_tags.OwnerUserId = UBM.UserId AND P_tags.Tags LIKE '%<python>%') THEN 'Pythonista'
            ELSE 'General Contributor'
        END AS PrimaryTechContribution,
        -- Conditional aggregations with NULL logic for post statuses
        COUNT(DISTINCT CASE WHEN PEM.WasClosed = 1 AND PEM.PostTypeId = 1 THEN PEM.PostId END) AS ClosedQuestionsOwned,
        COUNT(DISTINCT CASE WHEN PEM.BecameCommunityOwned = 1 AND PEM.PostTypeId = 2 THEN PEM.PostId END) AS CommunityOwnedAnswers,
        AVG(CASE WHEN PEM.PostTypeId = 1 THEN PEM.EditCount ELSE NULL END) AS AvgQuestionEditCount,
        -- Non-correlated subquery example for comparison: average posts for users with high reputation
        (SELECT AVG(UBM_inner.TotalPostsOwned) FROM UserBaseMetrics UBM_inner WHERE UBM_inner.Reputation > 5000) AS AvgPostsForHighRepUsers,
        MAX(CASE WHEN RPBO.HasOtherPostsNearCreation THEN 'Y' ELSE 'N' END) AS HasRapidPostCreation,
        -- NTILE window function over user reputation and badge counts
        NTILE(4) OVER (ORDER BY UBM.Reputation DESC, COALESCE(UBS.GoldBadges,0) DESC) AS ReputationBadgeQuartile,
        -- Calculate the reputation change rate per year (assuming initial reputation is 1)
        (UBM.Reputation - 1) / (GREATEST(EXTRACT(EPOCH FROM (UBM.LastAccessDate - UBM.UserCreationDate)) / (3600.0 * 24.0 * 365.25), 1e-9)) AS RepGainPerYear
    FROM UserBaseMetrics AS UBM
    LEFT JOIN UserBadgeSummary AS UBS ON UBM.UserId = UBS.UserId
    LEFT JOIN RankedPostsByOwner AS RPBO ON UBM.UserId = RPBO.OwnerUserId
    LEFT JOIN PostEngagementMetrics AS PEM ON UBM.UserId = PEM.OwnerUserId -- Direct join for PostEngagementMetrics
    GROUP BY
        UBM.UserId, UBM.DisplayName, UBM.Reputation, UBM.CreationDate, UBM.LastAccessDate,
        UBM.TotalPostsOwned, UBM.TotalQuestionsAsked, UBM.TotalAnswersGiven,
        UBM.TotalCommentsMade, UBS.GoldBadges, UBS.SilverBadges, UBS.BronzeBadges,
        UBM.EarliestPostDate, UBM.LatestUserActivityOnPosts
)
-- Main query: combines two distinct user segments using UNION ALL
SELECT
    'HighRep_Active_SQL_RapidContributor' AS UserSegment,
    UPA.UserId,
    UPA.DisplayName,
    UPA.Reputation,
    UPA.TotalPostsOwned,
    UPA.TotalQuestionsAsked,
    UPA.TotalAnswersGiven,
    UPA.TotalComments,
    UPA.GoldBadges,
    UPA.SilverBadges,
    UPA.BronzeBadges,
    UPA.TopQuestionScore,
    UPA.TopAnswerScore,
    UPA.AnswerToQuestionRatio,
    UPA.HoursToFirstPost,
    UPA.PrimaryTechContribution,
    UPA.ClosedQuestionsOwned,
    UPA.CommunityOwnedAnswers,
    UPA.AvgQuestionEditCount,
    UPA.HasRapidPostCreation,
    UPA.ReputationBadgeQuartile,
    UPA.RepGainPerYear,
    -- Correlated subquery: counts favorite posts by the user
    (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = UPA.UserId AND V.VoteTypeId = 5) AS FavoritePostsCount,
    COALESCE(U.Location, 'Unknown') AS UserLocation_Coalesced,
    -- Complicated calculation: Ratio of UpVotes to (UpVotes + DownVotes) with NULL handling
    CAST(U.UpVotes AS DECIMAL(10,2)) / NULLIF((U.UpVotes + U.DownVotes), 0) AS UpvoteDownvoteRatio
FROM UserPostTagAggregates AS UPA
INNER JOIN Users U ON UPA.UserId = U.Id -- Join back to Users for additional original columns
WHERE UPA.Reputation >= 5000
  AND UPA.TotalPostsOwned >= 10
  AND UPA.GoldBadges >= 1
  AND UPA.HasRapidPostCreation = 'Y'
  AND UPA.PrimaryTechContribution = 'SQL Enthusiast'
  AND U.Location IS NOT NULL
  AND UPA.ReputationBadgeQuartile = 1 -- Top 25% by reputation and gold badges
  AND UPA.RepGainPerYear > 1000 -- Filter by a significant reputation gain rate
  -- Another correlated subquery: checks for a specific named badge
  AND EXISTS (SELECT 1 FROM Badges B_inner WHERE B_inner.UserId = UPA.UserId AND B_inner.Name = 'Disciplined')
  AND (U.WebsiteUrl LIKE 'http://%' OR U.WebsiteUrl IS NULL) -- NULL logic in WHERE clause
  AND UPA.TotalComments > (SELECT AVG(TotalCommentsMade) FROM UserBaseMetrics WHERE TotalCommentsMade IS NOT NULL) -- Non-correlated subquery for comparison
UNION ALL
SELECT
    'Niche_HighImpact_DelayedContributor' AS UserSegment,
    UPA.UserId,
    UPA.DisplayName,
    UPA.Reputation,
    UPA.TotalPostsOwned,
    UPA.TotalQuestionsAsked,
    UPA.TotalAnswersGiven,
    UPA.TotalComments,
    UPA.GoldBadges,
    UPA.SilverBadges,
    UPA.BronzeBadges,
    UPA.TopQuestionScore,
    UPA.TopAnswerScore,
    UPA.AnswerToQuestionRatio,
    UPA.HoursToFirstPost,
    UPA.PrimaryTechContribution,
    UPA.ClosedQuestionsOwned,
    UPA.CommunityOwnedAnswers,
    UPA.AvgQuestionEditCount,
    UPA.HasRapidPostCreation,
    UPA.ReputationBadgeQuartile,
    UPA.RepGainPerYear,
    (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = UPA.UserId AND V.VoteTypeId = 5) AS FavoritePostsCount,
    COALESCE(U.Location, 'Unknown') AS UserLocation_Coalesced,
    CAST(U.UpVotes AS DECIMAL(10,2)) / NULLIF((U.UpVotes + U.DownVotes), 0) AS UpvoteDownvoteRatio
FROM UserPostTagAggregates AS UPA
INNER JOIN Users U ON UPA.UserId = U.Id
WHERE UPA.Reputation < 5000 -- Lower rep users
  AND UPA.TotalPostsOwned BETWEEN 1 AND 50 -- Not excessively active in terms of post count
  AND UPA.GoldBadges = 0 -- No Gold badges, perhaps more specialized or newer
  AND (UPA.ClosedQuestionsOwned >= 1 OR UPA.CommunityOwnedAnswers >= 1) -- But involved in complex post histories (e.g., closed questions, community-owned answers)
  AND UPA.PrimaryTechContribution NOT IN ('SQL Enthusiast', 'JavaScript Dev', 'Pythonista') -- Niche contributors (not common tech)
  AND U.Location IS NOT NULL
  AND UPA.HoursToFirstPost > (24 * 30) -- Took more than a month to make their first post (delayed engagement)
  AND U.UpVotes > COALESCE(U.DownVotes, 0) * 5 -- High upvote ratio
  -- Correlated subquery: ensures no tag-based gold badges
  AND NOT EXISTS (SELECT 1 FROM Badges B_inner WHERE B_inner.UserId = UPA.UserId AND B_inner.TagBased = TRUE AND B_inner.Class = 1)
ORDER BY Reputation DESC, TotalPostsOwned DESC
LIMIT 1000;
