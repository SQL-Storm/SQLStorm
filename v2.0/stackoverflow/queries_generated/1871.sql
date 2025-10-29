-- {"query": "1871.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3069} 

WITH UserInteractionMetrics AS (
    -- Summarizes user-level engagement: total upvotes/downvotes received, posts owned, comments made, badges earned.
    -- Uses LEFT JOIN to include users even if they have no associated posts, comments, or votes.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceived,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(U.LastAccessDate) AS LastUserActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Votes *on their posts*
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostHistoricalEvents AS (
    -- Tracks significant events on posts, like edits, closures, and reopens, by joining PostHistory once.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.OwnerUserId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 24) THEN PH.Id END) AS EditCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseEventCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenEventCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId
),
AggregatedTagUsage AS (
    -- Aggregates tag usage for posts, converting the string 'Tags' column into individual tags
    -- using string_to_array and UNNEST for complex string processing.
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
SpecificTopicUserScores AS (
    -- Identifies users who have performed well (high score) in specific 'hot' topics.
    SELECT
        ATU.TagName,
        P.OwnerUserId AS UserId,
        SUM(P.Score) AS TotalScoreInTopic,
        COUNT(P.Id) AS PostsInTopicCount
    FROM Posts P
    JOIN AggregatedTagUsage ATU ON P.Id = ATU.PostId
    WHERE ATU.TagName IN ('sql', 'database', 'performance', 'query-optimization', 'bigdata')
      AND P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2) -- Questions or Answers
    GROUP BY ATU.TagName, P.OwnerUserId
    HAVING COUNT(P.Id) > 3 -- At least 3 posts in this specific topic
),
PostQualityMetrics AS (
    -- Calculates various quality metrics for posts, including average score of child answers and linked posts.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        COALESCE(AVG(A.Score) FILTER (WHERE A.Id IS NOT NULL), 0) AS AvgAnswerScore,
        COALESCE(SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END), 0) AS LinkedPostCount,
        COALESCE(SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END), 0) AS DuplicateLinkCount
    FROM Posts P
    LEFT JOIN Posts A ON P.Id = A.ParentId AND A.PostTypeId = 2 -- Answers to this post
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    GROUP BY P.Id, P.PostTypeId, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount
),
UserTopPost AS (
    -- Selects the highest-scoring post for each user to serve as a representative post using a window function.
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        P.Score AS PostScore,
        P.ViewCount,
        P.PostTypeId,
        P.CreationDate,
        P.Title,
        P.Body,
        P.ContentLicense,
        ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) as rn
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2) -- Only consider questions or answers
)
-- Main Query Branch: Focus on high-reputation users and their top posts, combining various metrics.
SELECT
    UIM.UserId,
    UIM.DisplayName,
    UIM.Reputation,
    UIM.TotalPostsOwned,
    UIM.TotalCommentsMade,
    UIM.TotalBadges,
    UIM.TotalUpvotesReceived,
    UIM.TotalDownvotesReceived,
    UIM.LastUserActivityDate,
    UTP.PostId AS TopPostId,
    UTP.PostTypeId AS TopPostType,
    UTP.PostScore AS TopPostScore,
    UTP.ViewCount AS TopPostViewCount,
    PHE.EditCount AS TopPostEditCount,
    PHE.CloseEventCount AS TopPostCloseCount,
    PHE.ReopenEventCount AS TopPostReopenCount,
    PQM.AvgAnswerScore AS TopPostAvgAnswerScore,
    PQM.LinkedPostCount AS TopPostLinkedCount,
    PQM.DuplicateLinkCount AS TopPostDuplicateCount,
    STUS.TagName AS TopTopicTag,
    STUS.TotalScoreInTopic AS TopTopicScore,
    STUS.PostsInTopicCount AS TopTopicPostsCount,
    (UIM.TotalUpvotesReceived - UIM.TotalDownvotesReceived) AS NetVotesReceived,
    CAST(UIM.TotalUpvotesReceived AS NUMERIC) / NULLIF((UIM.TotalUpvotesReceived + UIM.TotalDownvotesReceived), 0) AS UpvoteRatio,
    LAG(UIM.Reputation, 1, 0) OVER (ORDER BY UIM.Reputation ASC) AS PreviousReputationRank,
    RANK() OVER (ORDER BY UIM.Reputation DESC, UIM.TotalUpvotesReceived DESC) AS GlobalReputationRank,
    NTILE(10) OVER (ORDER BY UIM.TotalPostsOwned DESC) AS PostOwnerDecile,
    CASE
        WHEN UIM.Reputation > 10000 AND UIM.TotalBadges >= 50 THEN 'High Impact User'
        WHEN UIM.Reputation BETWEEN 1000 AND 10000 AND UIM.TotalPostsOwned >= 50 THEN 'Active Contributor'
        ELSE 'Casual User'
    END AS UserCategory,
    -- Correlated Subquery: Checks if the user has a "Gold" badge related to a specific topic (e.g., 'SQL')
    (
        SELECT COUNT(B.Id)
        FROM Badges B
        WHERE B.UserId = UIM.UserId
          AND B.Class = 1 -- Gold badge
          AND B.Name LIKE '%SQL%' -- Example: specific gold tag badge like 'SQL Gold'
          AND B.Date BETWEEN UIM.UserCreationDate AND UIM.LastUserActivityDate
    ) AS GoldTagBadgeCount,
    COALESCE(UTP.Title, 'N/A Post Title') AS OriginalPostTitle, -- NULL logic using COALESCE
    LOWER(SUBSTRING(UTP.Body, 1, 100)) AS BodySnippet, -- String expression for body snippet
    UTP.ContentLicense,
    AVG(PHE_AvgScore.PostScore) OVER (PARTITION BY UTP.PostTypeId) AS AvgScoreForPostType, -- Window function for average score
    MAX(UTP.CreationDate) OVER (PARTITION BY UIM.UserId) AS LastPostCreationDateByOwner
FROM UserInteractionMetrics UIM
JOIN UserTopPost UTP ON UIM.UserId = UTP.UserId AND UTP.rn = 1 -- Join with the single top post for each user
LEFT JOIN PostHistoricalEvents PHE ON UTP.PostId = PHE.PostId
LEFT JOIN PostQualityMetrics PQM ON UTP.PostId = PQM.PostId
LEFT JOIN SpecificTopicUserScores STUS ON UIM.UserId = STUS.UserId AND UTP.PostId IN (SELECT PostId FROM AggregatedTagUsage WHERE TagName = STUS.TagName) -- Ensuring relevance of topic score
LEFT JOIN PostHistoricalEvents PHE_AvgScore ON UTP.PostTypeId = PHE_AvgScore.PostTypeId -- Alias for window function calculation
WHERE UIM.Reputation > 500 -- Filter for more relevant users
  AND UTP.PostScore > 5 -- Only positive scored representative posts
  AND UTP.CreationDate BETWEEN (NOW() - INTERVAL '10 year') AND NOW() -- Posts within the last 10 years
  AND (UTP.ViewCount IS NULL OR UTP.ViewCount > 500) -- Posts with some views or no view count recorded (like answers)
ORDER BY UIM.Reputation DESC, UTP.PostScore DESC
LIMIT 500

UNION ALL

-- Secondary Query Branch: Highlight posts with significant historical events (edits, closes, reopens)
-- These might not be owned by the top users, but are interesting for performance analysis.
-- Uses UNION ALL to combine results with a different selection logic.
SELECT
    NULL AS UserId, -- Deliberately NULL to indicate this is not a primary user record
    'Community Activity' AS DisplayName,
    0 AS Reputation, -- Default value for non-user specific rows
    NULL AS TotalPostsOwned,
    NULL AS TotalCommentsMade,
    NULL AS TotalBadges,
    NULL AS TotalUpvotesReceived,
    NULL AS TotalDownvotesReceived,
    NULL AS LastUserActivityDate,
    PHE.PostId,
    PHE.PostTypeId,
    PHE.PostScore,
    PHE.ViewCount,
    PHE.EditCount,
    PHE.CloseEventCount,
    PHE.ReopenEventCount,
    PQM.AvgAnswerScore,
    PQM.LinkedPostCount,
    PQM.DuplicateLinkCount,
    NULL AS TopTopicTag,
    NULL AS TotalScoreInTopic,
    NULL AS PostsInTopicCount,
    NULL AS NetVotesReceived,
    NULL AS UpvoteRatio,
    NULL AS PreviousReputationRank,
    NULL AS GlobalReputationRank,
    NULL AS PostOwnerDecile,
    'Highly Modified/Closed Post' AS UserCategory,
    NULL AS GoldTagBadgeCount,
    COALESCE(P_union_alt.Title, 'No Title Available') AS OriginalPostTitle,
    LOWER(SUBSTRING(P_union_alt.Body, 1, 100)) AS BodySnippet,
    P_union_alt.ContentLicense,
    AVG(PHE_AvgScore.PostScore) OVER (PARTITION BY PHE.PostTypeId) AS AvgScoreForPostType, -- Window function for average score
    MAX(P_union_alt.CreationDate) OVER (PARTITION BY PHE.OwnerUserId) AS LastPostCreationDateByOwner
FROM PostHistoricalEvents PHE
JOIN PostQualityMetrics PQM ON PHE.PostId = PQM.PostId
LEFT JOIN Posts P_union_alt ON PHE.PostId = P_union_alt.Id
LEFT JOIN PostHistoricalEvents PHE_AvgScore ON PHE.PostTypeId = PHE_AvgScore.PostTypeId -- Alias for window function calculation
WHERE (PHE.CloseEventCount > 0 OR PHE.EditCount > 7 OR PHE.ReopenEventCount > 0) -- Complicated predicate
  AND PHE.PostCreationDate > (NOW() - INTERVAL '7 year') -- Recent activity filter
  AND P_union_alt.PostTypeId IN (1, 2)
ORDER BY PHE.PostScore DESC, PHE.EditCount DESC
LIMIT 250;
