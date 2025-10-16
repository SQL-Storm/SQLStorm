-- {"query": "19091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3450} 

WITH ImportantPostsBase AS (
    -- CTE 1: Identifies a base set of "important" questions and answers using a UNION ALL set operator.
    -- Questions are selected based on high view count and a significant number of favorites.
    -- Answers are selected based on high score and being an accepted answer.
    SELECT
        Id,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        Title,
        Tags,
        AnswerCount, -- This column is only applicable for PostTypeId = 1 (Questions)
        FavoriteCount,
        ClosedDate
    FROM Posts
    WHERE PostTypeId = 1
      AND ViewCount > 50000
      AND FavoriteCount IS NOT NULL
      AND FavoriteCount >= 5
    UNION ALL
    SELECT
        Id,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount, -- ViewCount might be less relevant for answers, but included for consistent schema
        OwnerUserId,
        NULL AS Title, -- Answers typically don't have their own title in this column
        NULL AS Tags, -- Tags are primarily for questions
        NULL AS AnswerCount, -- Answers do not have an 'AnswerCount'
        FavoriteCount,
        ClosedDate
    FROM Posts
    WHERE PostTypeId = 2
      AND Score > 100
      AND AcceptedAnswerId IS NOT NULL
),
UserEngagement AS (
    -- CTE 2: Summarizes user activity for users who own the "important" posts.
    -- Calculates various metrics like reputation, badge counts, and overall posting performance.
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        COALESCE(U.Location, 'Unknown') AS UserLocation, -- NULL logic: replace NULL location with 'Unknown'
        COUNT(DISTINCT IPB.Id) FILTER (WHERE IPB.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT IPB.Id) FILTER (WHERE IPB.PostTypeId = 2) AS AnswerCount,
        SUM(IPB.Score) AS TotalPostScore,
        AVG(CASE WHEN IPB.PostTypeId = 1 THEN IPB.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(IPB.CreationDate) AS LastPostActivityDate, -- Max creation date of an important post by the user
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        DATE_PART('year', U.CreationDate) AS UserCreationYear,
        -- Correlated subquery: Count comments made by the user in the last 60 days
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.UserId = U.Id AND C.CreationDate > U.LastAccessDate - INTERVAL '60 days') AS RecentCommentCount,
        -- Complex calculation with NULLIF to prevent division by zero for average score
        SUM(IPB.Score) / NULLIF(COUNT(DISTINCT IPB.Id), 0) AS AvgScorePerContribution
    FROM Users U
    LEFT JOIN ImportantPostsBase IPB ON U.Id = IPB.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Location
    HAVING COUNT(DISTINCT IPB.Id) > 0 -- Filter users who own at least one "important" post
       AND U.Reputation > 500 -- Filter for reasonably reputable users
),
PostRevisionMetrics AS (
    -- CTE 3: Analyzes revision history and specific metrics for the "important" posts.
    -- Captures editing activity, last upvote date (via correlated subquery), and body changes.
    SELECT
        IPB.Id AS PostId,
        IPB.PostTypeId,
        IPB.CreationDate AS PostCreationDate,
        IPB.Score AS PostScore,
        IPB.ViewCount AS PostViewCount,
        IPB.AnswerCount, -- Will be NULL for answers, as intended
        IPB.FavoriteCount,
        IPB.OwnerUserId,
        COALESCE(IPB.Title, 'No Title (Answer)') AS PostTitle, -- NULL logic: provide a default title for answers
        IPB.Tags,
        COALESCE(IPB.ClosedDate IS NOT NULL, FALSE) AS IsClosed, -- NULL logic: convert NULL ClosedDate to FALSE boolean
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditDate, -- Edit Title, Body, Tags
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS FirstEditDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS EditRevisionCount, -- Counts actual edits/rollbacks
        -- String expression: aggregates first 100 characters of body changes, filtered for non-null text
        ARRAY_AGG(DISTINCT SUBSTRING(PH.Text FROM 1 FOR 100)) FILTER (WHERE PH.PostHistoryTypeId = 5 AND PH.Text IS NOT NULL) AS RecentBodyChanges,
        -- Correlated subquery: Finds the most recent upvote date for the post before the current timestamp
        (SELECT MAX(V.CreationDate) FROM Votes V WHERE V.PostId = IPB.Id AND V.VoteTypeId = 2 AND V.CreationDate < NOW()) AS LastUpvoteDate
    FROM ImportantPostsBase IPB
    LEFT JOIN PostHistory PH ON IPB.Id = PH.PostId
    GROUP BY IPB.Id, IPB.PostTypeId, IPB.CreationDate, IPB.Score, IPB.ViewCount, IPB.AnswerCount, IPB.FavoriteCount, IPB.OwnerUserId, IPB.Title, IPB.Tags, IPB.ClosedDate
    HAVING SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) > 0 -- Filter for posts that have at least one edit
),
TagAnalysis AS (
    -- CTE 4: Extracts and aggregates information about tags used in the selected posts.
    -- Uses string functions to parse the 'Tags' string into individual tags.
    SELECT
        PRM.PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(PRM.Tags FROM 2 FOR LENGTH(PRM.Tags) - 2), '><'))) AS TagName -- String functions: SUBSTRING, LENGTH, string_to_array, UNNEST, TRIM
    FROM PostRevisionMetrics PRM
    WHERE PRM.Tags IS NOT NULL AND LENGTH(PRM.Tags) > 2 AND PRM.PostTypeId = 1 -- Tags are primarily for questions
),
PostCommentSummary AS (
    -- CTE 5: Summarizes comment activity per post.
    -- Includes a complex predicate using string expressions to categorize comments.
    SELECT
        C.PostId,
        COUNT(C.Id) AS CommentCount,
        AVG(C.Score) AS AverageCommentScore,
        MAX(C.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT C.UserId) AS DistinctCommenters,
        -- String expression and complicated predicate: count comments containing positive sentiment keywords
        SUM(CASE WHEN C.Text ILIKE '%thank%' OR C.Text ILIKE '%useful%' OR C.Text ILIKE '%great%' THEN 1 ELSE 0 END) AS PositiveSentimentComments
    FROM Comments C
    GROUP BY C.PostId
)
-- Main query: Combines data from all CTEs and applies various analytical functions and complex filtering.
SELECT
    UE.UserId,
    UE.UserName,
    UE.Reputation,
    UE.UserLocation,
    UE.QuestionCount,
    UE.AnswerCount AS UserAnswerCount, -- Renamed to avoid confusion with post's answer count
    UE.AvgScorePerContribution,
    PRM.PostId,
    PRM.PostTypeId,
    PRM.PostTitle,
    PRM.PostScore,
    PRM.PostViewCount,
    PRM.AnswerCount AS QuestionAnswerCount, -- Renamed for clarity: specific to questions
    PRM.FavoriteCount,
    PRM.IsClosed,
    PRM.PostCreationDate,
    EXTRACT(DAY FROM (NOW() - PRM.PostCreationDate)) AS DaysSincePostCreation, -- Date calculation
    -- Date calculation & NULL logic: hours between first and last edit, defaulting to 0 if no edits
    COALESCE(EXTRACT(HOUR FROM (PRM.LastEditDate - PRM.FirstEditDate)), 0) AS HoursBetweenFirstAndLastEdit,
    PRM.EditRevisionCount,
    PCS.CommentCount,
    PCS.AverageCommentScore,
    PCS.DistinctCommenters,
    PCS.PositiveSentimentComments,
    ARRAY_TO_STRING(PRM.RecentBodyChanges, ' ||| ') AS CombinedRecentBodyChanges, -- String function: join body changes
    STRING_AGG(DISTINCT TA.TagName, ', ') AS RelatedTags, -- Aggregation of distinct tags for a post
    -- Window function (FIRST_VALUE): Finds the top post by score/views for each user's creation year
    FIRST_VALUE(PRM.PostTitle) OVER (PARTITION BY UE.UserCreationYear ORDER BY PRM.PostScore DESC, PRM.PostViewCount DESC) AS TopPostInCreationYearByScoreViews,
    -- Window function (DENSE_RANK): Ranks users by reputation within their creation year
    DENSE_RANK() OVER (PARTITION BY UE.UserCreationYear ORDER BY UE.Reputation DESC) AS UserReputationRankInYear,
    -- Window function (AVG OVER PARTITION): Calculates average score for each post type
    AVG(PRM.PostScore) OVER (PARTITION BY PRM.PostTypeId) AS AvgScoreForPostType,
    -- Correlated subquery: Calculates the average score of other *prior* posts by the same owner and post type
    (
        SELECT AVG(P_INNER.Score)
        FROM Posts P_INNER
        WHERE P_INNER.OwnerUserId = UE.UserId
          AND P_INNER.Id != PRM.PostId
          AND P_INNER.PostTypeId = PRM.PostTypeId
          AND P_INNER.CreationDate < PRM.PostCreationDate -- Only consider older posts
    ) AS AvgOtherPriorPostScoreByOwner,
    -- Complex CASE expression: Categorizes post engagement based on multiple metrics
    CASE
        WHEN PRM.PostScore >= 200 AND PRM.EditRevisionCount >= 5 AND PCS.CommentCount >= 15 THEN 'Highly Engaged & Evolved'
        WHEN PRM.PostScore >= 75 AND PRM.EditRevisionCount >= 2 AND PCS.CommentCount >= 5 THEN 'Moderately Engaged'
        ELSE 'Lower Engagement'
    END AS EngagementCategory,
    PRM.LastUpvoteDate,
    -- Correlated subquery with nested EXISTS and complex NULL logic: checks for specific badges earned by owner
    (
        SELECT
            CASE
                WHEN EXISTS (SELECT 1 FROM Badges B_INNER WHERE B_INNER.UserId = UE.UserId AND B_INNER.Name ILIKE '%Pundit%' AND B_INNER.Date < PRM.PostCreationDate) THEN 'Pundit Badge Before Post'
                WHEN EXISTS (SELECT 1 FROM Badges B_INNER WHERE B_INNER.UserId = UE.UserId AND B_INNER.Name ILIKE '%Editor%' AND B_INNER.Date < COALESCE(PRM.LastEditDate, PRM.PostCreationDate)) THEN 'Editor Badge Before Last Edit'
                ELSE 'No Relevant Badge Found'
            END
    ) AS OwnerBadgeStatusAtPostContext,
    -- Additional complex calculation: "Impact Score" considering multiple post metrics over time
    (PRM.PostScore * 0.5 + PRM.ViewCount * 0.01 + COALESCE(PRM.FavoriteCount, 0) * 2 + COALESCE(PCS.CommentCount, 0) * 0.8) / NULLIF(EXTRACT(DAY FROM (NOW() - PRM.PostCreationDate)), 0.1) AS PostImpactScoreDaily -- NULLIF to avoid division by zero (or small number) for very new posts
FROM UserEngagement UE
INNER JOIN PostRevisionMetrics PRM ON UE.UserId = PRM.OwnerUserId
LEFT JOIN PostCommentSummary PCS ON PRM.PostId = PCS.PostId
LEFT JOIN TagAnalysis TA ON PRM.PostId = TA.PostId
WHERE
    PRM.PostViewCount > 5000 -- Further filter for popular posts from the "important" set
    -- Correlated subquery in WHERE clause: compare post score to average score of posts of the same type in the last year
    AND PRM.PostScore > (SELECT AVG(P_SUB.Score) FROM Posts P_SUB WHERE P_SUB.PostTypeId = PRM.PostTypeId AND P_SUB.CreationDate > NOW() - INTERVAL '1 year')
    -- Complex predicate with multiple OR/AND conditions and NULL logic
    AND (
        (UE.GoldBadges > 0 AND UE.Reputation > 20000) -- Very high reputation users with gold badges
        OR (PRM.FavoriteCount IS NOT NULL AND PRM.FavoriteCount > 20) -- Posts with many favorites
        OR (PCS.DistinctCommenters > 5 AND PCS.AverageCommentScore > 1.5) -- Posts with significant comment engagement
        OR (PRM.PostTypeId = 2 AND PRM.AnswerCount IS NULL AND UE.AnswerCount > 0 AND PRM.PostScore > 150) -- Specific NULL logic for highly scored answers by users with answers
    )
GROUP BY
    UE.UserId, UE.UserName, UE.Reputation, UE.UserLocation, UE.QuestionCount, UE.AnswerCount, UE.AvgScorePerContribution, UE.UserCreationYear,
    PRM.PostId, PRM.PostTypeId, PRM.PostTitle, PRM.PostScore, PRM.PostViewCount, PRM.AnswerCount, PRM.FavoriteCount, PRM.IsClosed,
    PRM.PostCreationDate, PRM.LastEditDate, PRM.FirstEditDate, PRM.EditRevisionCount,
    PCS.CommentCount, PCS.AverageCommentScore, PCS.DistinctCommenters, PCS.PositiveSentimentComments,
    PRM.RecentBodyChanges, PRM.LastUpvoteDate
ORDER BY
    UE.Reputation DESC, PRM.PostScore DESC, PostImpactScoreDaily DESC
LIMIT 200;
