-- {"query": "1524.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3094} 
WITH UserPostStats AS (
    -- Calculate aggregated statistics for each user related to their posts and comments
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(CAST(COALESCE(P.Score, 0) AS NUMERIC)) AS AvgPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        AVG(CAST(COALESCE(C.Score, 0) AS NUMERIC)) AS AvgCommentScore,
        MAX(P.CreationDate) AS LatestPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id
),
PostEditCounts AS (
    -- Pre-aggregate significant edit counts for each post
    SELECT
        PostId,
        SUM(CASE WHEN PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS SignificantEditCount
    FROM PostHistory
    GROUP BY PostId
),
PostComplexity AS (
    -- Evaluate various complexity metrics for individual posts, using window functions and correlated subqueries
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.CommentCount,
        P.ViewCount,
        P.FavoriteCount,
        COALESCE(PEC.SignificantEditCount, 0) AS SignificantEditCount, -- Number of edits (from pre-aggregated CTE)
        -- Check for duplicate links using EXISTS (correlated subquery)
        CASE WHEN EXISTS (
            SELECT 1
            FROM PostLinks AS PL
            WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3 -- Duplicate link type
        ) THEN TRUE ELSE FALSE END AS HasDuplicateLink,
        -- Check if post is closed or community owned
        (P.ClosedDate IS NOT NULL OR P.CommunityOwnedDate IS NOT NULL) AS IsClosedOrCommunityOwned,
        -- Extract first tag for questions, convert to lowercase, and trim (string manipulation)
        LOWER(TRIM(SUBSTRING(P.Tags FROM 2 FOR COALESCE(NULLIF(POSITION('>' IN P.Tags), 0), LENGTH(P.Tags) + 1) - 2))) AS PrimaryTag,
        -- Word count in body (simplistic string expression)
        LENGTH(P.Body) - LENGTH(REPLACE(P.Body, ' ', '')) + 1 AS BodyWordCount,
        -- Calculate post's rank within its owner's posts by score (window function)
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY COALESCE(P.Score, 0) DESC, P.CreationDate DESC) AS OwnerPostScoreRank,
        -- Calculate the average score for posts of this type by the same owner (correlated subquery)
        (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = P.OwnerUserId AND PostTypeId = P.PostTypeId) AS AvgOwnerPostTypeScore
    FROM Posts AS P
    LEFT JOIN PostEditCounts AS PEC ON P.Id = PEC.PostId
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2) -- Focus on questions and answers
),
UserBadgeInfluence AS (
    -- Aggregate badge information for users
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id
),
HighlyEngagedUsers AS (
    -- Identify users with high engagement or complex post history by joining various CTEs
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        COALESCE(U.Location, 'Unknown') AS UserLocation, -- NULL logic
        UPS.TotalPosts,
        UPS.TotalQuestions,
        UPS.TotalAnswers,
        UPS.AvgPostScore,
        UPS.TotalPostViews,
        UBI.GoldBadges,
        UBI.TotalBadges,
        -- Count complex posts using an aggregate FILTER clause (PostgreSQL specific, but common in benchmarking)
        COUNT(DISTINCT PC.PostId) FILTER (
            WHERE PC.SignificantEditCount > 2
            AND PC.HasDuplicateLink
            AND PC.CommentCount > 5
            AND COALESCE(PC.Score, 0) > COALESCE(PC.AvgOwnerPostTypeScore, 0) * 0.5 -- Score is above 50% of user's average for that post type
            AND PC.BodyWordCount BETWEEN 100 AND 500 -- Medium length for complexity
            AND PC.PrimaryTag IN ('sql', 'database', 'performance', 'indexing', 'c#', 'java', 'python') -- Specific tags
            AND NOT PC.IsClosedOrCommunityOwned
        ) AS ComplexPostCount,
        -- Calculate acceptance rate for answers (complicated calculation with NULLIF for division by zero)
        CAST(SUM(CASE WHEN P.PostTypeId = 2 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) /
        NULLIF(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerAcceptanceRatio,
        -- Total score from accepted answers for their own questions
        SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN (SELECT COALESCE(Score, 0) FROM Posts WHERE Id = P.AcceptedAnswerId) ELSE 0 END) AS ScoreFromAcceptedAnswers
    FROM Users AS U
    LEFT JOIN UserPostStats AS UPS ON U.Id = UPS.UserId
    LEFT JOIN UserBadgeInfluence AS UBI ON U.Id = UBI.UserId
    LEFT JOIN PostComplexity AS PC ON U.Id = PC.OwnerUserId
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId -- For AnswerAcceptanceRatio calculation and ScoreFromAcceptedAnswers
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.DisplayName, U.Location,
             UPS.TotalPosts, UPS.TotalQuestions, UPS.TotalAnswers, UPS.AvgPostScore, UPS.TotalPostViews,
             UBI.GoldBadges, UBI.TotalBadges
    HAVING U.Reputation > 5000 AND COALESCE(UBI.GoldBadges, 0) > 0 -- Complicated predicate
),
ModeratorActivity AS (
    -- Identify users who have performed moderator-like actions or whose posts were affected by moderation
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.PostId) AS PostsAffectedByHistory,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS ModeratorActionsCount, -- Closed, Deleted, Locked, Protected
        SUM(CASE WHEN PH.PostHistoryTypeId IN (11, 13, 15, 20) THEN 1 ELSE 0 END) AS ReversalActionsCount, -- Reopened, Undeleted, Unlocked, Unprotected
        AVG(EXTRACT(EPOCH FROM (PH.CreationDate - P.CreationDate))) / 3600 / 24 AS AvgDaysToModeration -- Avg days from post creation to a history event
    FROM PostHistory AS PH
    JOIN Posts AS P ON PH.PostId = P.Id
    WHERE PH.UserId IS NOT NULL
    AND PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 33, 34) -- Focus on moderation-related types and post notices
    GROUP BY PH.UserId
)
-- Final result set combining all insights, using outer joins and set operators
SELECT
    HEU.UserId,
    HEU.DisplayName,
    HEU.Reputation,
    HEU.UserLocation,
    HEU.TotalPosts,
    HEU.TotalQuestions,
    HEU.TotalAnswers,
    HEU.AvgPostScore,
    HEU.TotalPostViews,
    HEU.GoldBadges,
    HEU.TotalBadges,
    HEU.ComplexPostCount,
    HEU.AnswerAcceptanceRatio,
    HEU.ScoreFromAcceptedAnswers,
    COALESCE(MA.ModeratorActionsCount, 0) AS TotalModeratorActions,
    COALESCE(MA.AvgDaysToModeration, 0) AS AvgDaysToModeration,
    -- Calculate a composite influence score using a complex expression and NULL logic
    (HEU.Reputation * 0.1
     + COALESCE(HEU.GoldBadges, 0) * 100
     + COALESCE(HEU.ComplexPostCount, 0) * 50
     + COALESCE(HEU.AnswerAcceptanceRatio, 0) * 500
     + (CASE WHEN COALESCE(HEU.TotalQuestions, 0) > 0 THEN COALESCE(HEU.ScoreFromAcceptedAnswers, 0) * 0.5 ELSE 0 END)
     + COALESCE(MA.ModeratorActionsCount, 0) * 20
     - COALESCE(MA.ReversalActionsCount, 0) * 10
     - (EXTRACT(EPOCH FROM AGE(CURRENT_TIMESTAMP, HEU.CreationDate)) / 31536000) * 0.01 -- Deduct slightly for age to favor active recent influence
    ) AS CompositeInfluenceScore,
    -- Rank users by their composite influence score using a window function
    DENSE_RANK() OVER (ORDER BY (
        HEU.Reputation * 0.1
        + COALESCE(HEU.GoldBadges, 0) * 100
        + COALESCE(HEU.ComplexPostCount, 0) * 50
        + COALESCE(HEU.AnswerAcceptanceRatio, 0) * 500
        + (CASE WHEN COALESCE(HEU.TotalQuestions, 0) > 0 THEN COALESCE(HEU.ScoreFromAcceptedAnswers, 0) * 0.5 ELSE 0 END)
        + COALESCE(MA.ModeratorActionsCount, 0) * 20
        - COALESCE(MA.ReversalActionsCount, 0) * 10
        - (EXTRACT(EPOCH FROM AGE(CURRENT_TIMESTAMP, HEU.CreationDate)) / 31536000) * 0.01
    ) DESC) AS InfluenceRank
FROM HighlyEngagedUsers AS HEU
LEFT JOIN ModeratorActivity AS MA ON HEU.UserId = MA.UserId
WHERE HEU.DisplayName IS NOT NULL
AND HEU.Reputation > (SELECT AVG(Reputation) * 2 FROM Users) -- Only show users with significantly above-average reputation (subquery in WHERE)

UNION ALL -- Set operator: Combine with another set of users identified differently

-- Select highly reputed, active, older users who might not have "complex" posts by the above definition
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    COALESCE(U.Location, 'Unknown') AS UserLocation,
    NULL AS TotalPosts, -- NULLs to match column structure of the first SELECT
    NULL AS TotalQuestions,
    NULL AS TotalAnswers,
    NULL AS AvgPostScore,
    NULL AS TotalPostViews,
    NULL AS GoldBadges,
    NULL AS TotalBadges,
    NULL AS ComplexPostCount,
    NULL AS AnswerAcceptanceRatio,
    NULL AS ScoreFromAcceptedAnswers,
    0 AS TotalModeratorActions,
    0 AS AvgDaysToModeration,
    (U.UpVotes * 0.5 + U.Reputation * 0.05 + COALESCE(U.Views, 0) * 0.01) AS CompositeInfluenceScore, -- Different scoring for this branch
    NULL AS InfluenceRank -- Rank is specific to the first branch, so NULL here
FROM Users AS U
WHERE U.Reputation > 10000 -- High reputation
AND U.UpVotes > 5000 -- Many upvotes
AND U.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '1 year' -- Recently active
AND U.CreationDate < CURRENT_TIMESTAMP - INTERVAL '5 year' -- Older accounts
AND LENGTH(COALESCE(U.AboutMe, '')) > 50 -- Has a substantial 'AboutMe' (string expression)
AND NOT EXISTS (SELECT 1 FROM HighlyEngagedUsers WHERE UserId = U.Id) -- Exclude users already found in the first part (NOT EXISTS subquery)

ORDER BY CompositeInfluenceScore DESC;