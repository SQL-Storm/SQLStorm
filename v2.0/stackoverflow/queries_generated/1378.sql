-- {"query": "1378.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2472} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersPosted,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreSum,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswerCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(p.CreationDate) AS LatestPostDate,
        -- Window function: Rank users by reputation within their creation year
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC, u.Id) AS ReputationRankInYear
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        LOWER(p.Title) AS LowercasedTitle,
        -- String expression for cleaned tags, handling the '><' delimiter
        REPLACE(REPLACE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '>', ','), '<', '') AS CleanedTagsString,
        -- Window function: Average score for posts of the same type
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
        -- Window function: Cumulative count of posts by this owner up to this point
        COUNT(p.Id) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS OwnerPostSequenceNum,
        -- Calculate post age in hours using epoch difference
        EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 3600 AS PostAgeHours
    FROM Posts AS p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
PostHistoryChanges AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEditEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEvents,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS FirstEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS LastEditDate,
        -- Correlated subquery to check if post has related duplicates
        (SELECT COUNT(pl.Id) FROM PostLinks AS pl WHERE pl.PostId = ph.PostId AND pl.LinkTypeId = 3) AS DuplicateLinkCount
    FROM PostHistory AS ph
    GROUP BY ph.PostId
),
PostCommentSentiment AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments,
        AVG(c.Score) AS AverageCommentScore,
        -- Correlated subquery for user with most comments on this post
        (
            SELECT u.DisplayName
            FROM Comments AS c_inner
            JOIN Users AS u ON c_inner.UserId = u.Id
            WHERE c_inner.PostId = c.PostId
            GROUP BY u.DisplayName
            ORDER BY COUNT(c_inner.Id) DESC
            LIMIT 1
        ) AS TopCommenterDisplayName
    FROM Comments AS c
    GROUP BY c.PostId
),
HighImpactPosts AS (
    -- Set operator: UNION ALL to combine different criteria for "high impact"
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        'HighViewQuestion' AS ImpactType
    FROM Posts AS p
    WHERE p.PostTypeId = 1
      AND p.ViewCount > 5000
      AND p.Score > 50
    UNION ALL
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        'HighlyScoredAnswer' AS ImpactType
    FROM Posts AS p
    WHERE p.PostTypeId = 2
      AND p.Score > 100
      AND p.ParentId IS NOT NULL
)
SELECT
    ue.UserId,
    u.DisplayName,
    ue.Reputation,
    ue.TotalPostsCreated,
    ue.TotalAnswersPosted,
    ue.GoldBadgesCount,
    ue.ReputationRankInYear,
    pa.PostId,
    pa.LowercasedTitle AS PostTitle,
    pa.PostCreationDate,
    pa.Score AS PostScore,
    pa.ViewCount AS PostViewCount,
    pa.CommentCount AS PostCommentCount,
    pa.CleanedTagsString,
    phc.TotalEditEvents,
    phc.CloseEvents,
    phc.ReopenEvents,
    phc.DuplicateLinkCount,
    pcs.AverageCommentScore,
    pcs.TopCommenterDisplayName,
    hip.ImpactType,
    -- Complicated predicate/expression/calculation
    ROUND(
        (CAST(pa.Score AS NUMERIC) / NULLIF(pa.ViewCount, 0)) * 100
        + (pa.CommentCount * 0.5)
        + (ue.TotalAnswersPosted * 0.1)
        - (phc.CloseEvents * 5)
    , 2) AS EngagementMetric,
    -- NULL logic: Use FirstEditDate if available, otherwise PostCreationDate
    COALESCE(phc.FirstEditDate, pa.PostCreationDate) AS EffectiveFirstActivityDate,
    -- Conditional expression based on post age and user reputation
    CASE
        WHEN pa.PostAgeHours < 24 THEN 'New'
        WHEN pa.PostAgeHours BETWEEN 24 AND 168 THEN 'Recent'
        WHEN pa.PostAgeHours > 168 AND ue.Reputation > 10000 THEN 'Established_Influencer'
        ELSE 'Established_General'
    END AS PostAgeCategory,
    -- Window function: Moving average of post scores for a user, looking at the last 3 posts and current
    AVG(pa.Score) OVER (PARTITION BY ue.UserId ORDER BY pa.PostCreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS UserMovingAvgScore,
    -- Null logic in string expression: Handle potentially NULL Location
    UPPER(LEFT(COALESCE(u.Location, 'UNKNOWN LOCATION'), 10)) AS UserLocationPrefix,
    -- Correlated subquery in SELECT: Average score of previous posts by the same user and post type
    (
        SELECT AVG(p_sub.Score)
        FROM Posts AS p_sub
        WHERE p_sub.OwnerUserId = ue.UserId
          AND p_sub.PostTypeId = pa.PostTypeId
          AND p_sub.CreationDate < pa.PostCreationDate
    ) AS AvgPreviousPostScoreForType
FROM UserEngagement AS ue
JOIN Users AS u ON ue.UserId = u.Id
LEFT JOIN PostTagAnalysis AS pa ON ue.UserId = pa.OwnerUserId
LEFT JOIN PostHistoryChanges AS phc ON pa.PostId = phc.PostId
LEFT JOIN PostCommentSentiment AS pcs ON pa.PostId = pcs.PostId
LEFT JOIN HighImpactPosts AS hip ON pa.PostId = hip.PostId
WHERE
    ue.Reputation >= 5000 -- Filter for highly influential users
    AND ue.TotalPostsCreated >= 5 -- Users with at least 5 posts
    AND pa.PostTypeId IS NOT NULL -- Ensure we only consider posts that exist in PostTagAnalysis
    AND pa.Score > pa.AvgScoreForPostType -- Post score must be above the average for its type
    -- String pattern matching for tags, includes NULL logic if tags are missing
    AND (pa.CleanedTagsString LIKE '%sql%' OR pa.CleanedTagsString LIKE '%database%' OR pa.CleanedTagsString IS NULL)
    AND pa.PostCreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Specific date range for posts
    AND (phc.CloseEvents = 0 OR phc.ReopenEvents > 0) -- Posts either never closed, or were closed and then reopened
    AND u.AboutMe IS NOT NULL -- User must have an 'About Me' section (NULL logic)
    -- Correlated subquery in WHERE clause for users whose average post score is above the overall average for their reputation band
    AND (SELECT AVG(p_inner.Score) FROM Posts AS p_inner WHERE p_inner.OwnerUserId = ue.UserId) > (
        SELECT COALESCE(AVG(p_band.Score), 0) -- Handle case where no posts in band
        FROM Posts AS p_band
        JOIN Users AS u_band ON p_band.OwnerUserId = u_band.Id
        WHERE u_band.Reputation BETWEEN FLOOR(ue.Reputation / 10000) * 10000 AND FLOOR(ue.Reputation / 10000) * 10000 + 9999
    )
ORDER BY
    ue.Reputation DESC,
    EngagementMetric DESC,
    pa.PostCreationDate DESC
LIMIT 1000;
