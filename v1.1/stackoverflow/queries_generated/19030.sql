-- {"query": "19030.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2268} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        -- Complex calculation: Average score of posts owned by the user, only considering questions and answers
        COALESCE(AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score END), 0) AS AvgScorePerOwnedPost,
        -- Window function: Rank users by their reputation
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS ReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastActivityDate,
        P.ClosedDate,
        -- String expression & NULL logic: Extract up to 200 chars of body, replace newlines/tabs, default to empty string
        SUBSTRING(REPLACE(REPLACE(COALESCE(P.Body, ''), E'\n', ' '), E'\t', ' '), 1, 200) AS BodyExcerpt,
        -- Complicated Predicate: Check for specific tag categories and content keywords
        (P.Tags ILIKE '%<sql>%' OR P.Tags ILIKE '%<database>%' OR P.Body ILIKE '%database management%') AS IsDbRelated,
        -- Calculation: Age of post in days
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - P.CreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        -- Window function: Average score for posts of the same type created within the same calendar month
        AVG(P.Score) OVER (PARTITION BY P.PostTypeId, EXTRACT(YEAR FROM P.CreationDate), EXTRACT(MONTH FROM P.CreationDate)) AS AvgMonthlyPostTypeScore,
        -- Window function: Rank posts by ViewCount within their PostType, for questions only
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.CreationDate DESC) AS ViewCountRankByPostType
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2) -- Only questions and answers
),
TagUsageStats AS (
    SELECT
        PCA.PostId,
        PCA.OwnerUserId,
        -- Correlated Subquery: Count unique tags associated with this post from the Tags table
        (
            SELECT COUNT(DISTINCT T.Id)
            FROM Tags T
            WHERE PCA.Tags LIKE '%<' || T.TagName || '>%<'
        ) AS MatchedUniqueTagCount,
        -- Correlated Subquery: Check if post has any gold-badged related tags (i.e., tags that also exist as gold badges)
        EXISTS (
            SELECT 1
            FROM Badges B
            JOIN Tags T ON B.Name = T.TagName
            WHERE PCA.Tags LIKE '%<' || T.TagName || '>%<' AND B.Class = 1
        ) AS HasGoldTagBadge
    FROM PostContentAnalysis PCA
    WHERE PCA.Tags IS NOT NULL
),
PostHistoryAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS HasBodyEditHistory, -- Has a body edit
        -- Correlated Subquery: Find the user with highest reputation among those who edited this post
        (
            SELECT MAX(U_INNER.Reputation)
            FROM Users U_INNER
            WHERE U_INNER.Id = PH.UserId
        ) AS EditorMaxReputation,
        -- String expression & NULL logic: Extract CloseReasonType name if post was closed
        COALESCE(MAX(CRT.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL), 'Not Closed Or No Reason') AS LatestCloseReason
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.Comment = CRT.Id::varchar AND PH.PostHistoryTypeId = 10
    GROUP BY PH.PostId
),
UserBadgeMetrics AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Window function: Calculate average badges per user based on creation year
        AVG(COUNT(B.Id)) OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate)) AS AvgBadgesPerCreationYear
    FROM Badges B
    JOIN Users U ON B.UserId = U.Id
    GROUP BY B.UserId, U.CreationDate
)
-- Final Query: Combine all CTEs and perform final aggregations, joins, and filtering
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ReputationRank,
    UAS.UserCreationDate,
    UAS.TotalPostsCreated,
    UAS.TotalCommentsMade,
    UAS.AvgScorePerOwnedPost,
    UBM.GoldBadges,
    UBM.SilverBadges,
    UBM.BronzeBadges,
    UBM.AvgBadgesPerCreationYear,
    PCA.PostId,
    PCA.PostTypeName,
    PCA.Title AS PostTitle,
    PCA.Score AS PostScore,
    PCA.ViewCount AS PostViewCount,
    PCA.PostAgeDays,
    PCA.IsDbRelated,
    PCA.AvgMonthlyPostTypeScore,
    PCA.ViewCountRankByPostType,
    TUS.MatchedUniqueTagCount,
    TUS.HasGoldTagBadge,
    PHA.TotalHistoryEntries AS PostEditHistoryCount,
    PHA.HasBodyEditHistory,
    PHA.EditorMaxReputation,
    PHA.LatestCloseReason,
    -- Complex calculation: Engagement score based on post view count, score, comments, and activity
    (PCA.ViewCount * 0.1 + PCA.Score * 0.5 + COALESCE(P.CommentCount, 0) * 0.8 + COALESCE(P.FavoriteCount, 0) * 1.2) AS EngagementScore,
    -- NULL logic: Check if a post has an accepted answer (for questions)
    (CASE WHEN PCA.PostTypeId = 1 AND PCA.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END) AS HasAcceptedAnswer,
    -- String expression: Concatenate User DisplayName and a truncated Location
    UAS.DisplayName || ' from ' || COALESCE(SUBSTRING(U.Location, 1, 20), 'Unknown') AS UserLocationSummary,
    -- Correlated subquery: Count how many upvotes a post received from users with reputation > 1000
    (
        SELECT COUNT(V.Id)
        FROM Votes V
        JOIN Users VU ON V.UserId = VU.Id
        WHERE V.PostId = PCA.PostId AND V.VoteTypeId = 2 AND VU.Reputation > 1000
    ) AS HighReputationUpvotes,
    -- Set operator for combining high-scoring questions and answers
    (
        SELECT
            P_HIGH.Id
        FROM Posts P_HIGH
        WHERE P_HIGH.PostTypeId = 1 AND P_HIGH.Score > 500
        UNION ALL
        SELECT
            P_HIGH.Id
        FROM Posts P_HIGH
        WHERE P_HIGH.PostTypeId = 2 AND P_HIGH.Score > 300
    ) AS HighlyRatedPostIds -- This will be an array/list of IDs if supported, or a subquery result for EXISTS/IN
FROM UserActivitySummary UAS
JOIN Users U ON UAS.UserId = U.Id -- Re-join for U.Location
LEFT JOIN UserBadgeMetrics UBM ON UAS.UserId = UBM.UserId
INNER JOIN PostContentAnalysis PCA ON UAS.UserId = PCA.OwnerUserId
LEFT JOIN TagUsageStats TUS ON PCA.PostId = TUS.PostId
LEFT JOIN PostHistoryAnalysis PHA ON PCA.PostId = PHA.PostId
LEFT JOIN Posts P ON PCA.PostId = P.Id -- Join back to original Posts for CommentCount and FavoriteCount
WHERE
    UAS.Reputation > 10000 -- Filter for high reputation users
    AND PCA.PostAgeDays < 365 -- Only posts from the last year
    AND (
        PCA.Score > 50 -- Posts with good score
        OR PCA.ViewCount > 5000 -- Or highly viewed posts
    )
ORDER BY
    UAS.Reputation DESC,
    EngagementScore DESC,
    PCA.PostCreationDate DESC
LIMIT 1000; -- Limit results for practical benchmarking
