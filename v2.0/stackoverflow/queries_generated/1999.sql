-- {"query": "1999.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3380} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user activity metrics, including correlated subqueries for badge counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS TotalUpvotesGiven,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS TotalDownvotesGiven,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(P.CreationDate) AS LatestPostDate,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 1) AS AvgQuestionScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId = 2) AS AvgAnswerScore,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges, -- Correlated Subquery for Gold Badges
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges, -- Correlated Subquery for Silver Badges
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadges, -- Correlated Subquery for Bronze Badges
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostPerformance AS (
    -- CTE 2: Analyzes individual post performance, utilizing window functions and more correlated subqueries
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.Body, -- Included for later string analysis
        P.CreationDate AS PostCreationDate,
        P.OwnerUserId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><') AS ParsedTags, -- String manipulation for tags
        (
            SELECT MIN(PH.CreationDate)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
            AND PH.PostHistoryTypeId IN (4, 5, 6, 24) -- Edit Title, Edit Body, Edit Tags, Suggested Edit Applied
        ) AS FirstEditAppliedDate, -- Correlated Subquery for first edit
        (
            SELECT MAX(PH.CreationDate)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
            AND PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) -- Post Closed types (legacy and current)
        ) AS ClosedDateFromHistory, -- Correlated Subquery for closed date
        (
            SELECT COUNT(DISTINCT C_inner.Id)
            FROM Comments C_inner
            WHERE C_inner.PostId = P.Id
            AND C_inner.CreationDate > P.CreationDate + INTERVAL '1 hour'
            AND C_inner.Score >= 5
        ) AS HighScoreCommentsAfterFirstHour, -- Another correlated subquery for comment activity
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostScoreByOwner, -- Window function: previous post's score by same owner
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostTypeScoreRank, -- Window function: rank posts by score within their type
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.ViewCount DESC) AS OwnerViewRank, -- Window function: rank posts by view count for each owner
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) OVER (PARTITION BY P.Id) AS PostUpvoteCount, -- Window function: total upvotes per post
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) OVER (PARTITION BY P.Id) AS PostDownvoteCount -- Window function: total downvotes per post
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND P.CreationDate >= '2022-01-01' -- Filter for recent posts to manage data volume
),
ProblematicContentAnalysis AS (
    -- CTE 3: Identifies posts that are "problematic" or notable based on various criteria
    SELECT
        PP.PostId,
        PP.PostTypeId,
        PP.Title,
        PP.Body,
        PP.PostCreationDate,
        PP.OwnerUserId,
        PP.PostScore,
        PP.ViewCount,
        PP.FavoriteCount,
        PP.ClosedDateFromHistory,
        PP.HighScoreCommentsAfterFirstHour,
        COALESCE(PP.FirstEditAppliedDate, PP.PostCreationDate) AS EffectiveLastEditConsidered, -- NULL logic with COALESCE
        EXISTS (
            SELECT 1
            FROM PostLinks PL
            WHERE PL.PostId = PP.PostId
            AND PL.LinkTypeId = 3 -- Check if the post is a duplicate source
        ) AS IsDuplicateSource, -- Subquery with EXISTS
        EXISTS (
            SELECT 1
            FROM PostHistory PH
            WHERE PH.PostId = PP.PostId
            AND PH.PostHistoryTypeId = 11 -- Check if the post was reopened
        ) AS WasReopened, -- Subquery with EXISTS
        CASE
            WHEN PP.PostTypeId = 1 AND COALESCE(PP.AnswerCount, 0) = 0 AND PP.LastActivityDate < NOW() - INTERVAL '6 months' THEN 'Unanswered Stale Question'
            WHEN PP.PostTypeId = 1 AND PP.ClosedDateFromHistory IS NOT NULL THEN 'Closed Question'
            WHEN PP.PostTypeId = 2 AND PP.PostScore < -5 THEN 'Highly Downvoted Answer'
            ELSE 'Normal Post'
        END AS PostStatusCategory, -- Complicated conditional logic
        CASE
            WHEN PP.Title ILIKE '%performance%' OR PP.Body ILIKE '%benchmark%' THEN 'Performance/Benchmark Related' -- String expression with ILIKE
            WHEN EXISTS (SELECT 1 FROM UNNEST(PP.ParsedTags) AS tag WHERE tag ILIKE 'sql%' OR tag ILIKE 'database%') THEN 'SQL/Database Tag Related' -- String expression and subquery on array
            ELSE 'General'
        END AS ContentKeywordCategory
    FROM PostPerformance PP
    WHERE PP.PostScore < 0 OR PP.ViewCount > 10000 OR PP.FavoriteCount > 100 -- Filter for high-interest/problematic posts
    OR PP.ClosedDateFromHistory IS NOT NULL
)
-- Main query: Combines insights from CTEs and applies further filtering, calculations, and set operations
SELECT
    PCA.PostId,
    PCA.PostTypeId,
    PCA.Title,
    PCA.PostCreationDate,
    PCA.OwnerUserId,
    UE.DisplayName AS OwnerDisplayName,
    COALESCE(UE.Reputation, 0) AS OwnerReputation, -- NULL logic for reputation
    PCA.PostScore,
    PCA.ViewCount,
    COALESCE(PCA.FavoriteCount, 0) AS FavoriteCount, -- NULL logic for favorite count
    PCA.ClosedDateFromHistory,
    PCA.HighScoreCommentsAfterFirstHour,
    PCA.IsDuplicateSource,
    PCA.WasReopened,
    PCA.PostStatusCategory,
    PCA.ContentKeywordCategory,
    UE.AccountAgeDays,
    COALESCE(UE.GoldBadges, 0) AS GoldBadges, -- NULL logic for badge counts
    COALESCE(UE.SilverBadges, 0) AS SilverBadges,
    COALESCE(UE.BronzeBadges, 0) AS BronzeBadges,
    PP.PostTypeScoreRank,
    PP.OwnerViewRank,
    PP.PostUpvoteCount,
    PP.PostDownvoteCount,
    -- Complicated calculation: Ratio of upvotes to total votes, handling division by zero
    CASE
        WHEN (PP.PostUpvoteCount + PP.PostDownvoteCount) > 0
        THEN (CAST(PP.PostUpvoteCount AS NUMERIC) / (PP.PostUpvoteCount + PP.PostDownvoteCount))
        ELSE 0
    END AS UpvoteRatio,
    -- Elaborate calculation: Normalized influence score, considering post score, favorites, age, views, and recent edits
    (PCA.PostScore * (1 + (COALESCE(PCA.FavoriteCount, 0) / 10.0)) - (EXTRACT(EPOCH FROM (NOW() - PCA.PostCreationDate)) / (3600.0 * 24 * 365.25 * 0.1)))
    / (LOG(GREATEST(PCA.ViewCount, 1)) + 1 + (CASE WHEN PCA.EffectiveLastEditConsidered > PCA.PostCreationDate + INTERVAL '1 day' THEN 0.5 ELSE 0 END)) AS WeightedInfluenceScore,
    -- String expression and NULL handling for post body excerpt
    COALESCE(LEFT(PCA.Body, 150), 'No body text available') AS PostBodyExcerpt,
    -- Non-correlated subquery in SELECT clause: counts matching tags
    (SELECT COUNT(DISTINCT T.Id) FROM Tags T WHERE T.TagName = ANY(PP.ParsedTags)) AS MatchedTagsCount,
    -- Non-correlated subquery in SELECT clause: average comment score by registered users
    (SELECT AVG(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = PCA.PostId AND C_sub.UserId IS NOT NULL) AS AvgCommentScoreByRegisteredUser
FROM ProblematicContentAnalysis PCA
LEFT JOIN UserEngagement UE ON PCA.OwnerUserId = UE.UserId -- Left join to include users who might not have posts (if CTE 1 allowed this)
INNER JOIN PostPerformance PP ON PCA.PostId = PP.PostId -- Re-join to access window function results not passed from PCA
WHERE PCA.PostStatusCategory != 'Normal Post' -- Filter for posts categorized as non-normal
OR (UE.Reputation IS NOT NULL AND UE.Reputation < 500 AND PCA.PostScore < 0) -- Or posts by low-rep users with negative scores
OR (PCA.ContentKeywordCategory LIKE '%SQL%') -- Or posts related to SQL/Database keywords
ORDER BY WeightedInfluenceScore DESC, PCA.PostCreationDate DESC
LIMIT 500

UNION ALL -- Set operator: Combines results with a different analysis branch

-- Second branch of the UNION ALL: Identifies users with high post counts but low engagement/reputation
SELECT
    NULL AS PostId, -- Explicit NULLs to match column structure of the first branch
    NULL AS PostTypeId,
    NULL AS Title,
    NULL AS PostCreationDate,
    UE.UserId AS OwnerUserId,
    UE.DisplayName AS OwnerDisplayName,
    COALESCE(UE.Reputation, 0) AS OwnerReputation,
    P_low_engage.Score AS PostScore, -- Includes score from the "worst" post
    P_low_engage.ViewCount AS ViewCount,
    COALESCE(P_low_engage.FavoriteCount, 0) AS FavoriteCount,
    P_low_engage.ClosedDate AS ClosedDateFromHistory,
    NULL AS HighScoreCommentsAfterFirstHour,
    FALSE AS IsDuplicateSource,
    FALSE AS WasReopened,
    'UserAnomaly: LowEngagementHighPoster' AS PostStatusCategory, -- Distinct status category
    'UserCentric' AS ContentKeywordCategory,
    UE.AccountAgeDays,
    COALESCE(UE.GoldBadges, 0) AS GoldBadges,
    COALESCE(UE.SilverBadges, 0) AS SilverBadges,
    COALESCE(UE.BronzeBadges, 0) AS BronzeBadges,
    NULL AS PostTypeScoreRank,
    NULL AS OwnerViewRank,
    NULL AS PostUpvoteCount,
    NULL AS PostDownvoteCount,
    NULL AS UpvoteRatio,
    -- Different weighting for user-centric influence: posts per day penalized by upvotes given
    (UE.TotalPosts * 1.0 / GREATEST(UE.AccountAgeDays, 1, 0.001)) - (UE.TotalUpvotesGiven * 0.5) AS WeightedInfluenceScore,
    COALESCE(LEFT(P_low_engage.Body, 150), 'No associated post body') AS PostBodyExcerpt,
    NULL AS MatchedTagsCount,
    NULL AS AvgCommentScoreByRegisteredUser
FROM UserEngagement UE
LEFT JOIN LATERAL ( -- Lateral join to find the single "worst" (lowest score, highest views) post for each low-engagement user
    SELECT P_inner.*
    FROM Posts P_inner
    WHERE P_inner.OwnerUserId = UE.UserId
    AND P_inner.PostTypeId IN (1, 2)
    ORDER BY P_inner.Score ASC, P_inner.ViewCount DESC
    LIMIT 1
) AS P_low_engage ON TRUE
WHERE UE.TotalPosts > 50 -- Users who posted many times
AND COALESCE(UE.AvgQuestionScore, 0) < 3 -- But have very low average question score (handling NULL for avg)
AND UE.TotalUpvotesGiven < UE.TotalPosts * 1.5 -- And don't give many upvotes relative to posts
AND COALESCE(UE.Reputation, 0) < 750 -- And relatively low reputation
AND UE.AccountAgeDays > 30 -- Must be an established user
ORDER BY WeightedInfluenceScore DESC, UE.Reputation ASC
LIMIT 100;
