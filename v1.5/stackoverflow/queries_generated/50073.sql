-- {"query": "50073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1114} 

WITH TagAnswerStats AS (
    -- Step 1: Identify users who have answered questions for a specific tag ('sql')
    -- and pre-calculate core metrics for their answers within that tag.
    -- This CTE tests joins between large tables and string matching.
    SELECT
        a.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AverageAnswerScore,
        MIN(a.CreationDate) AS FirstAnswerDate,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts AS a
    INNER JOIN Posts AS q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 -- It's an answer
      AND a.OwnerUserId IS NOT NULL
      AND q.PostTypeId = 1 -- Its parent is a question
      AND q.Tags LIKE '%<sql>%'
    GROUP BY a.OwnerUserId
    HAVING COUNT(a.Id) > 10 -- Only consider users with a significant number of answers in the tag
),
UserContributionTimeline AS (
    -- Step 2: For each user, find their first post and first gold badge to measure
    -- how quickly they achieved a high-level contribution.
    -- This CTE tests window functions over a combined dataset.
    SELECT
        UserId,
        MIN(CASE WHEN ActivityType = 'Post' THEN ActivityDate END) AS FirstPostDate,
        MIN(CASE WHEN ActivityType = 'GoldBadge' THEN ActivityDate END) AS FirstGoldBadgeDate
    FROM (
        SELECT OwnerUserId AS UserId, CreationDate AS ActivityDate, 'Post' AS ActivityType FROM Posts WHERE OwnerUserId IS NOT NULL
        UNION ALL
        SELECT UserId, Date AS ActivityDate, 'GoldBadge' AS ActivityType FROM Badges WHERE Class = 1
    ) AS UserActivities
    GROUP BY UserId
),
CommunityEngagement AS (
    -- Step 3: Measure how the community interacts with a user's content,
    -- including upvotes, comments, and favorites.
    -- This CTE tests multiple LEFT JOINs and aggregations.
    SELECT
        p.OwnerUserId,
        SUM(p.FavoriteCount) AS TotalFavorites,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        COUNT(c.Id) AS CommentsReceived
    FROM Posts AS p
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
-- Final Query: Synthesize all the metrics to rank the most impactful 'sql' experts.
-- The query combines results from all CTEs, calculates a final weighted score,
-- and uses a window function for ranking.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    tas.AnswerCount AS SqlAnswerCount,
    tas.TotalAnswerScore AS SqlTotalAnswerScore,
    ce.UpvotesReceived,
    ce.CommentsReceived,
    -- Time in days from user's first post to their first gold badge (NULL if no gold badge)
    EXTRACT(DAY FROM (uct.FirstGoldBadgeDate - uct.FirstPostDate)) AS DaysToFirstGold,
    -- A complex "Expertise Score" to rank users
    (
        (tas.AverageAnswerScore * tas.AnswerCount) + -- Weighted score from answers
        (u.Reputation * 0.1) +
        (ce.UpvotesReceived * 0.5) -
        (ce.DownvotesReceived * 2.0) -- Penalize downvotes heavily
    ) / (EXTRACT(DAY FROM (NOW() - u.CreationDate)) + 1) AS NormalizedExpertiseScore, -- Normalize by account age
    DENSE_RANK() OVER (
        ORDER BY
        (
            (tas.AverageAnswerScore * tas.AnswerCount) +
            (u.Reputation * 0.1) +
            (ce.UpvotesReceived * 0.5) -
            (ce.DownvotesReceived * 2.0)
        ) / (EXTRACT(DAY FROM (NOW() - u.CreationDate)) + 1) DESC
    ) AS ExpertiseRank
FROM Users AS u
INNER JOIN TagAnswerStats AS tas ON u.Id = tas.OwnerUserId
INNER JOIN CommunityEngagement AS ce ON u.Id = ce.OwnerUserId
LEFT JOIN UserContributionTimeline AS uct ON u.Id = uct.UserId
WHERE u.Reputation > 5000 -- Filter for high-reputation users
  AND u.Id > 0 -- Exclude community user
ORDER BY ExpertiseRank ASC, u.Reputation DESC
LIMIT 100;
