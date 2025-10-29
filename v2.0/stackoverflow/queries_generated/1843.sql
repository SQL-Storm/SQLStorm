-- {"query": "1843.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3115} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT P_Owned.Id) AS TotalOwnedPosts,
        SUM(CASE WHEN P_Owned.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P_Owned.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COALESCE(SUM(P_Owned.Score), 0) AS TotalScoreReceivedOnOwnedPosts,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotesCast,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotesCast,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS TotalFavoriteBookmarks, -- Legacy favorite votes
        AVG(CASE WHEN P_Owned.PostTypeId IN (1,2) THEN P_Owned.Score ELSE NULL END) AS AvgOwnedPostScore,
        COUNT(DISTINCT P_Edited.Id) AS TotalPostsEdited,
        COUNT(DISTINCT P_LastAccessed.Id) AS TotalLastAccessedPosts
    FROM Users U
    LEFT JOIN Posts P_Owned ON U.Id = P_Owned.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Posts P_Edited ON U.Id = P_Edited.LastEditorUserId
    LEFT JOIN Posts P_LastAccessed ON U.LastAccessDate >= P_LastAccessed.CreationDate AND U.LastAccessDate < P_LastAccessed.LastActivityDate AND P_LastAccessed.OwnerUserId = U.Id -- Posts the user was active on recently
    GROUP BY U.Id
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.AcceptedAnswerId,
        P.ParentId,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Title, Body, Tags edits
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10) AS CloseVoteCount,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 11) AS ReopenVoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS ReceivedDownVotes,
        -- String expression for tags, handling NULL and empty tags
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2)
            ELSE ''
        END AS CleanTags
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Only Questions and Answers
    AND P.CreationDate >= (NOW() - INTERVAL '5 year') -- Only relatively recent posts for performance
),
UserBadgePerformance AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
HighlyInteractedPosts AS (
    SELECT
        PEM.PostId,
        PEM.OwnerUserId,
        PEM.PostTypeId,
        PEM.PostScore,
        PEM.ViewCount,
        PEM.AnswerCount,
        PEM.CommentCount,
        PEM.FavoriteCount,
        PEM.EditCount,
        PEM.CloseVoteCount,
        PEM.ReopenVoteCount,
        PEM.ReceivedDownVotes,
        PEM.CleanTags,
        -- Complicated calculation for 'ControversyScore'
        (PEM.EditCount * 0.5) + (ABS(PEM.PostScore) * 0.1) + (PEM.ReceivedDownVotes * 0.8) + (PEM.CloseVoteCount * 2) - (PEM.ReopenVoteCount * 1.5) AS ControversyScore,
        -- Check for specific controversial conditions using subquery for average
        CASE
            WHEN PEM.CloseVoteCount > 0 AND PEM.ReopenVoteCount > 0 THEN 'ClosedAndReopened'
            WHEN PEM.ReceivedDownVotes > (SELECT AVG(ReceivedDownVotes) * 2 FROM PostEngagementMetrics WHERE PostTypeId = PEM.PostTypeId) AND PEM.EditCount > 5 THEN 'HighlyNegativeAndEdited'
            WHEN PEM.ViewCount > 100000 AND (PEM.FavoriteCount IS NULL OR PEM.FavoriteCount < 10) THEN 'HighViewsLowFavs'
            ELSE 'Normal'
        END AS ControversyType
    FROM PostEngagementMetrics PEM
    WHERE (PEM.PostScore < -5 AND PEM.ReceivedDownVotes > 10) -- Very negative posts
       OR (PEM.EditCount > 10 AND PEM.CloseVoteCount > 0) -- Highly edited and closed posts
       OR (EXISTS (SELECT 1 FROM Comments C WHERE C.PostId = PEM.PostId AND LENGTH(C.Text) > 200 AND C.Score > 5)) -- Posts with long, highly upvoted comments
       OR (PEM.ViewCount > 50000 AND PEM.CommentCount > 50) -- Very popular and commented posts
),
RankedUsers AS (
    -- Category 1: Influential users involved in highly interacted or controversial posts
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Unknown User ' || U.Id) AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        UAS.TotalOwnedPosts,
        UAS.TotalScoreReceivedOnOwnedPosts,
        UAS.TotalCommentsMade,
        COALESCE(UBP.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBP.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBP.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UBP.TotalBadges, 0) AS TotalBadges,
        'ActiveOnControversial' AS UserCategory,
        HIP.PostId,
        HIP.ControversyScore,
        HIP.ControversyType,
        HIP.CleanTags,
        RANK() OVER (PARTITION BY HIP.ControversyType ORDER BY U.Reputation DESC, HIP.ControversyScore DESC, UAS.TotalScoreReceivedOnOwnedPosts DESC) AS RankWithinControversyType,
        NTILE(5) OVER (ORDER BY U.Reputation DESC, HIP.ControversyScore DESC) AS ReputationControversyQuintile
    FROM Users U
    INNER JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
    LEFT JOIN UserBadgePerformance UBP ON U.Id = UBP.UserId -- LEFT JOIN because some users might have no badges
    INNER JOIN HighlyInteractedPosts HIP ON U.Id = HIP.OwnerUserId -- Only users who own such posts
    WHERE U.Reputation > 10000
      AND (U.Location LIKE '%developer%' OR U.Location LIKE '%engineer%' OR U.Location IS NULL) -- NULL logic for location, and string search
      AND U.AboutMe IS NOT NULL AND LENGTH(TRIM(U.AboutMe)) > 100 -- Users with substantial 'AboutMe'
      AND UAS.TotalOwnedPosts > 50
      AND UAS.TotalCommentsMade > 20
      AND COALESCE(UBP.GoldBadges, 0) >= 1
      AND HIP.ControversyScore > (SELECT AVG(ControversyScore) FROM HighlyInteractedPosts) * 1.5 -- Only truly controversial
      AND U.LastAccessDate >= (NOW() - INTERVAL '1 year')
),
HistoricalImpactUsers AS (
    -- Category 2: Users with significant historical impact and good community standing
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous Contributor ' || U.Id) AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        UAS.TotalOwnedPosts,
        UAS.TotalScoreReceivedOnOwnedPosts,
        UAS.TotalCommentsMade,
        COALESCE(UBP.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBP.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBP.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UBP.TotalBadges, 0) AS TotalBadges,
        'HistoricalImpact' AS UserCategory,
        NULL AS PostId, -- Not tied to a specific post in this category
        NULL AS ControversyScore,
        NULL AS ControversyType,
        NULL AS CleanTags,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, UAS.TotalScoreReceivedOnOwnedPosts DESC, COALESCE(UBP.TotalBadges, 0) DESC) AS OverallRank,
        -- Correlated subquery for counting accepted answers posted by this user
        (SELECT COUNT(DISTINCT P_Acc.Id)
         FROM Posts P_Q
         INNER JOIN Posts P_Acc ON P_Q.AcceptedAnswerId = P_Acc.Id
         WHERE P_Q.OwnerUserId = U.Id AND P_Acc.OwnerUserId = U.Id AND P_Acc.PostTypeId = 2
        ) AS AcceptedAnswersToOwnQuestionsCount
    FROM Users U
    INNER JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
    LEFT JOIN UserBadgePerformance UBP ON U.Id = UBP.UserId
    WHERE U.CreationDate < (NOW() - INTERVAL '7 year') -- Old users
      AND UAS.TotalQuestionsOwned > 10
      AND UAS.TotalAnswersOwned > 20
      AND U.UpVotes > U.DownVotes * 5 -- More upvotes than downvotes ratio
      AND U.Views > 1000
      AND EXISTS (SELECT 1 FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 1) -- Has accepted an answer for a question they own
      AND NOT EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = U.Id AND B.Name = 'Disciplined') -- Exclude users who might be too strict (example of NOT EXISTS logic)
)
SELECT
    RU.UserId,
    RU.UserDisplayName,
    RU.Reputation,
    RU.UserCreationDate,
    RU.TotalOwnedPosts,
    RU.TotalScoreReceivedOnOwnedPosts,
    RU.TotalCommentsMade,
    RU.GoldBadges,
    RU.SilverBadges,
    RU.BronzeBadges,
    RU.TotalBadges,
    RU.UserCategory,
    RU.PostId,
    RU.ControversyScore,
    RU.ControversyType,
    RU.CleanTags,
    RU.RankWithinControversyType AS SpecificRank,
    RU.ReputationControversyQuintile AS OverallRankComponent
FROM RankedUsers RU
WHERE RU.RankWithinControversyType <= 10 -- Top 10 within each controversy type
AND RU.ReputationControversyQuintile = 1 -- Only the top quintile for overall reputation/controversy
AND (RU.CleanTags LIKE '%<sql>%' OR RU.CleanTags LIKE '%<database>%' OR RU.CleanTags LIKE '%<performance>%') -- String matching within tags
UNION ALL
SELECT
    HIU.UserId,
    HIU.UserDisplayName,
    HIU.Reputation,
    HIU.UserCreationDate,
    HIU.TotalOwnedPosts,
    HIU.TotalScoreReceivedOnOwnedPosts,
    HIU.TotalCommentsMade,
    HIU.GoldBadges,
    HIU.SilverBadges,
    HIU.BronzeBadges,
    HIU.TotalBadges,
    HIU.UserCategory,
    HIU.PostId,
    HIU.ControversyScore,
    HIU.ControversyType,
    HIU.CleanTags,
    HIU.OverallRank AS SpecificRank,
    HIU.AcceptedAnswersToOwnQuestionsCount AS OverallRankComponent -- Using this as a secondary rank component for historical users
FROM HistoricalImpactUsers HIU
WHERE HIU.OverallRank <= 50 -- Top 50 historical impact users
AND HIU.AcceptedAnswersToOwnQuestionsCount >= 5 -- Historical users with at least 5 accepted answers on their own questions
ORDER BY Reputation DESC, SpecificRank ASC;
