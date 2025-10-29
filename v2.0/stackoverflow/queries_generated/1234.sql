-- {"query": "1234.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3675} 

WITH UserActivitySummary AS (
    -- CTE 1: Summarize user activity, categorize by reputation, and calculate badge counts.
    -- Includes a window function to find the previous access date for each user.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        -- Complex CASE statement for reputation tiering
        CASE
            WHEN U.Reputation >= 20000 THEN 'Veteran'
            WHEN U.Reputation >= 5000 THEN 'Expert'
            WHEN U.Reputation >= 500 THEN 'Established'
            WHEN U.Reputation >= 50 THEN 'Contributor'
            ELSE 'Novice'
        END AS ReputationTier,
        -- Complicated calculation with NULL logic: Up/Down Vote Ratio
        COALESCE(CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes, 0), U.UpVotes) AS UpDownVoteRatio,
        -- Non-correlated subqueries to count badges
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadges,
        LAG(U.LastAccessDate, 1, U.CreationDate) OVER (PARTITION BY U.Id ORDER BY U.LastAccessDate) AS PrevAccessDate -- Window function
    FROM
        Users U
),
PostEngagementMetrics AS (
    -- CTE 2: Calculate engagement metrics for posts, including edit history insights via correlated subqueries.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        -- Complicated expression: Custom Engagement Score calculation
        (P.Score * 0.5) + (P.ViewCount * 0.01) + (COALESCE(P.AnswerCount, 0) * 2) + (P.CommentCount * 0.75) + (COALESCE(P.FavoriteCount, 0) * 1.5) AS EngagementScore,
        -- Date calculation: Hours since creation to last activity
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600.0 AS HoursSinceCreationToLastActivity,
        -- Correlated subquery to count unique editors from PostHistory
        (
            SELECT COUNT(DISTINCT PH.UserId)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
              AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) -- Specific PostHistoryTypes for edits
        ) AS UniqueEditorsCount,
        -- Correlated subquery to find the latest edit date from PostHistory
        (
            SELECT MAX(PH.CreationDate)
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
              AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24)
        ) AS LastEditHistoryDate
    FROM
        Posts P
    WHERE
        P.OwnerUserId IS NOT NULL -- Filter out community owned posts or deleted users
),
ExplodedPostTags AS (
    -- CTE 3: Explode the 'Tags' string into individual tag rows for questions.
    -- Uses string functions and LATERAL UNNEST (PostgreSQL specific) for complex tag parsing.
    SELECT
        PEM.PostId,
        PEM.OwnerUserId,
        TRIM(tag_val) AS TagName
    FROM
        PostEngagementMetrics PEM,
        LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(PEM.Tags, 2, LENGTH(PEM.Tags) - 2), '><')) AS T(tag_val)
    WHERE
        PEM.PostTypeId = 1 -- Only analyze tags for questions
        AND PEM.Tags IS NOT NULL
        AND LENGTH(PEM.Tags) > 2
        AND TRIM(tag_val) IS NOT NULL AND TRIM(tag_val) != ''
),
UserPostInteraction AS (
    -- CTE 4: Combine user and post data, add more detailed post-level metrics, and apply ranking window functions.
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.ReputationTier,
        UAS.GoldBadges,
        UAS.SilverBadges,
        UAS.BronzeBadges,
        P.Id AS PostId,
        P.Title,
        P.PostTypeId,
        PEM.EngagementScore,
        PEM.UniqueEditorsCount,
        -- Date calculations for days to first edit and days to close
        EXTRACT(EPOCH FROM (P.LastEditDate - P.CreationDate)) / 86400.0 AS DaysToFirstEdit,
        EXTRACT(EPOCH FROM (P.ClosedDate - P.CreationDate)) / 86400.0 AS DaysToClose,
        COALESCE(LENGTH(P.Body), 0) AS BodyLength, -- String function for body length
        C.Id AS CommentId,
        C.Score AS CommentScore,
        C.CreationDate AS CommentCreationDate,
        -- Non-correlated subqueries to count total questions/answers by owner
        (SELECT COUNT(P2.Id) FROM Posts P2 WHERE P2.OwnerUserId = UAS.UserId AND P2.PostTypeId = 1) AS TotalQuestionsByOwner,
        (SELECT COUNT(P2.Id) FROM Posts P2 WHERE P2.OwnerUserId = UAS.UserId AND P2.PostTypeId = 2) AS TotalAnswersByOwner,
        -- Correlated subquery to sum bounty amount on a specific post
        (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 8) AS TotalBountyOnPost,
        DENSE_RANK() OVER (PARTITION BY UAS.UserId ORDER BY PEM.EngagementScore DESC, P.CreationDate DESC) AS UserPostEngagementRank, -- Window function
        ROW_NUMBER() OVER (PARTITION BY UAS.UserId, P.PostTypeId ORDER BY P.CreationDate DESC) AS PostTypeCreationSequence, -- Window function
        UAS.PrevAccessDate
    FROM
        UserActivitySummary UAS
    LEFT JOIN
        Posts P ON UAS.UserId = P.OwnerUserId -- Outer join
    LEFT JOIN
        PostEngagementMetrics PEM ON P.Id = PEM.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId AND C.UserId = UAS.UserId -- Outer join, comments by the post owner
    WHERE
        P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
        AND UAS.ReputationTier IS NOT NULL
),
AggregatedUserMetrics AS (
    -- CTE 5: Aggregate various metrics per user, including conditional aggregations and percentile calculation.
    SELECT
        UPI.UserId,
        UPI.DisplayName,
        UPI.ReputationTier,
        UPI.GoldBadges,
        UPI.SilverBadges,
        UPI.BronzeBadges,
        COUNT(DISTINCT UPI.PostId) AS TotalPosts,
        SUM(CASE WHEN UPI.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN UPI.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(UPI.EngagementScore) AS AvgPostEngagementScore,
        MAX(UPI.EngagementScore) AS MaxPostEngagementScore,
        SUM(UPI.UniqueEditorsCount) AS TotalUniqueEditorsAcrossPosts,
        AVG(UPI.DaysToFirstEdit) AS AvgDaysToFirstEdit,
        AVG(UPI.DaysToClose) AS AvgDaysToClose,
        SUM(UPI.BodyLength) AS TotalBodyLength,
        MAX(UPI.CommentCreationDate) AS LastCommentByOwnerDate,
        SUM(COALESCE(UPI.TotalBountyOnPost, 0)) AS TotalBountyReceived,
        -- Correlated subquery within aggregation with FILTER clause
        COUNT(DISTINCT C2.UserId) FILTER (WHERE C2.PostId IN (SELECT PostId FROM UserPostInteraction WHERE UserId = UPI.UserId)) AS UniqueCommentersOnUserPosts,
        -- Correlated subquery to sum bounty given by user
        (
            SELECT SUM(V.BountyAmount)
            FROM Votes V
            WHERE V.UserId = UPI.UserId AND V.VoteTypeId = 8
        ) AS TotalBountyGivenByOwner,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY UPI.EngagementScore) AS MedianEngagementScore -- Window function for percentile
    FROM
        UserPostInteraction UPI
    LEFT JOIN
        Comments C2 ON C2.PostId = UPI.PostId AND C2.UserId IS NOT NULL AND C2.UserId != UPI.UserId -- Outer join for comments by others
    GROUP BY
        UPI.UserId, UPI.DisplayName, UPI.ReputationTier, UPI.GoldBadges, UPI.SilverBadges, UPI.BronzeBadges
),
RecentSignificantActivity AS (
    -- CTE 6: Uses UNION ALL to combine different types of "significant" user activities.
    SELECT
        UserId,
        MAX(ActivityDate) AS LastSignificantActivityDate
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            P.CreationDate AS ActivityDate
        FROM
            Posts P
        WHERE
            P.AcceptedAnswerId IS NOT NULL OR P.Score > 100
        UNION ALL -- Set operator
        SELECT
            C.UserId AS UserId,
            C.CreationDate AS ActivityDate
        FROM
            Comments C
        WHERE
            C.Score > 5
    ) AS CombinedActivities
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserTopTags AS (
    -- CTE 7: Identifies the top 5 most frequently used tags by each user using window functions and STRING_AGG.
    SELECT
        OwnerUserId AS UserId,
        STRING_AGG(TagName, ', ' ORDER BY TagCount DESC) AS Top5Tags -- String aggregation with ordering
    FROM (
        SELECT
            OwnerUserId,
            TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC, TagName ASC) as rn -- Window function for ranking tags
        FROM
            ExplodedPostTags
        GROUP BY
            OwnerUserId, TagName
    ) AS RankedTags
    WHERE rn <= 5 -- Limit for top 5
    GROUP BY
        OwnerUserId
)
-- Main Query: Joins all CTEs and performs final aggregations, complex calculations, and rankings.
SELECT
    AUM.UserId,
    AUM.DisplayName,
    AUM.ReputationTier,
    AUM.GoldBadges,
    AUM.SilverBadges,
    AUM.BronzeBadges,
    AUM.TotalPosts,
    AUM.TotalQuestions,
    AUM.TotalAnswers,
    AUM.AvgPostEngagementScore,
    AUM.MaxPostEngagementScore,
    AUM.TotalUniqueEditorsAcrossPosts,
    AUM.AvgDaysToFirstEdit,
    AUM.AvgDaysToClose,
    AUM.TotalBodyLength,
    AUM.LastCommentByOwnerDate,
    AUM.TotalBountyReceived,
    AUM.TotalBountyGivenByOwner,
    AUM.UniqueCommentersOnUserPosts,
    RSA.LastSignificantActivityDate,
    UAS.UserCreationDate,
    UAS.UserLastAccessDate,
    UAS.UserProfileViews,
    UAS.UpdownVoteRatio,
    EXTRACT(EPOCH FROM (UAS.UserLastAccessDate - UAS.UserCreationDate)) / 86400.0 AS UserAccountAgeDays, -- Date calculation
    ROUND(CAST(AUM.TotalAnswers AS NUMERIC) / NULLIF(AUM.TotalQuestions, 0), 2) AS AnswerQuestionRatio, -- NULL logic, division
    -- Conditional aggregation using LEFT JOINs to ExplodedPostTags for specific tag counts
    SUM(CASE WHEN TA_sql.TagName = 'sql' THEN 1 ELSE 0 END) AS QuestionsWithSqlTag,
    SUM(CASE WHEN TA_perf.TagName = 'performance' THEN 1 ELSE 0 END) AS QuestionsWithPerformanceTag,
    -- Correlated subquery: get the title of the user's highest engagement score post
    (SELECT P_HighEngage.Title FROM UserPostInteraction P_HighEngage WHERE P_HighEngage.UserId = AUM.UserId ORDER BY P_HighEngage.EngagementScore DESC, P_HighEngage.PostCreationDate DESC LIMIT 1) AS TopEngagementPostTitle,
    -- Correlated subquery: get the average score of all comments made by this user
    (SELECT AVG(C_User.Score) FROM Comments C_User WHERE C_User.UserId = AUM.UserId) AS AvgCommentScoreByUser,
    RANK() OVER (ORDER BY AUM.AvgPostEngagementScore DESC, AUM.TotalPosts DESC) AS GlobalEngagementRank, -- Global ranking window function
    NTILE(10) OVER (ORDER BY AUM.TotalBountyReceived DESC) AS BountyReceiverDecile, -- NTILE window function
    UTT.Top5Tags,
    UAS.PrevAccessDate,
    (UAS.UserLastAccessDate - UAS.PrevAccessDate) AS TimeSincePrevAccess -- Date interval calculation
FROM
    AggregatedUserMetrics AUM
JOIN
    UserActivitySummary UAS ON AUM.UserId = UAS.UserId
LEFT JOIN
    RecentSignificantActivity RSA ON AUM.UserId = RSA.UserId
LEFT JOIN
    UserTopTags UTT ON AUM.UserId = UTT.UserId
LEFT JOIN
    ExplodedPostTags TA_sql ON AUM.UserId = TA_sql.OwnerUserId AND TA_sql.TagName = 'sql'
LEFT JOIN
    ExplodedPostTags TA_perf ON AUM.UserId = TA_perf.OwnerUserId AND TA_perf.TagName = 'performance'
WHERE
    AUM.TotalPosts > 5 -- Complicated predicate
    AND (AUM.ReputationTier IN ('Expert', 'Veteran') OR AUM.GoldBadges > 0 OR AUM.SilverBadges > 0) -- Complex boolean logic
    AND AUM.AvgPostEngagementScore IS NOT NULL
GROUP BY -- Extensive GROUP BY clause due to multiple joins that can create duplicate rows per user
    AUM.UserId, AUM.DisplayName, AUM.ReputationTier, AUM.GoldBadges, AUM.SilverBadges, AUM.BronzeBadges,
    AUM.TotalPosts, AUM.TotalQuestions, AUM.TotalAnswers, AUM.AvgPostEngagementScore, AUM.MaxPostEngagementScore,
    AUM.TotalUniqueEditorsAcrossPosts, AUM.AvgDaysToFirstEdit, AUM.AvgDaysToClose, AUM.TotalBodyLength,
    AUM.LastCommentByOwnerDate, AUM.TotalBountyReceived, AUM.TotalBountyGivenByOwner, AUM.UniqueCommentersOnUserPosts,
    RSA.LastSignificantActivityDate, UAS.UserCreationDate, UAS.UserLastAccessDate, UAS.UserProfileViews,
    UAS.UpdownVoteRatio, UTT.Top5Tags, UAS.PrevAccessDate
ORDER BY
    GlobalEngagementRank ASC, AUM.DisplayName
LIMIT 1000;
