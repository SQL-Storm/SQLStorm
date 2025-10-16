-- {"query": "20003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1517} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS AccountCreationDate,
        (EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))) / 3600.0 AS HoursToLastActivity,
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Score AS PostScore,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE u.Reputation > 1000 AND p.CreationDate > (NOW() - INTERVAL '5 year') AND p.CommunityOwnedDate IS NULL
),
RankedActivity AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        PostType,
        PostScore,
        ViewCount,
        CommentCountOnPost,
        PostCreationDate,
        HoursToLastActivity,
        -- Window function to rank posts by score within each user's activity
        ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY PostScore DESC, PostCreationDate DESC) as rn_score,
        -- Window function to calculate the average score of the last 5 posts by a user
        AVG(PostScore) OVER(PARTITION BY UserId ORDER BY PostCreationDate ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) as moving_avg_score,
        -- Use LAG to find the time difference between consecutive posts
        EXTRACT(EPOCH FROM (PostCreationDate - LAG(PostCreationDate, 1, PostCreationDate) OVER (PARTITION BY UserId ORDER BY PostCreationDate))) / 86400.0 as days_since_last_post
    FROM UserActivity
    WHERE PostType IN ('Question', 'Answer')
),
UserStatsAggregation AS (
    SELECT
        ra.UserId,
        MAX(ra.DisplayName) AS DisplayName,
        MAX(ra.Reputation) AS Reputation,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN ra.PostType = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN ra.PostType = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(ra.PostScore) AS AveragePostScore,
        SUM(ra.ViewCount) AS TotalViews,
        MAX(ra.moving_avg_score) AS PeakMovingAvgScore,
        -- Correlated subquery to get count of gold badges
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ra.UserId AND b.Class = 1 AND b.TagBased = 'f') AS GoldBadges,
        -- Another subquery to check if user has ever edited a post they don't own
        EXISTS(SELECT 1 FROM PostHistory ph WHERE ph.UserId = ra.UserId AND ph.PostHistoryTypeId IN (4,5,6) AND ph.PostId NOT IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = ra.UserId)) AS HasEditedOthersPosts
    FROM RankedActivity ra
    WHERE ra.rn_score <= 20 -- Consider only top 20 posts for this aggregation
    GROUP BY ra.UserId
    HAVING SUM(CASE WHEN ra.PostType = 'Answer' THEN 1 ELSE 0 END) > 5
),
TagAnalysis AS (
    -- A separate CTE using UNION to analyze popular tags among two user groups
    (SELECT
        'HighRepUsers' AS UserGroup,
        T.tag,
        COUNT(*) as TagCount
    FROM UserActivity ua
    CROSS JOIN LATERAL unnest(string_to_array(substring(ua.Tags, 2, length(ua.Tags)-2), '><')) AS T(tag)
    WHERE ua.Reputation > 50000 AND ua.PostType = 'Question' AND ua.Tags IS NOT NULL
    GROUP BY T.tag
    ORDER BY TagCount DESC
    LIMIT 10)
    UNION ALL
    (SELECT
        'MidRepUsers' AS UserGroup,
        T.tag,
        COUNT(*) as TagCount
    FROM UserActivity ua
    CROSS JOIN LATERAL unnest(string_to_array(substring(ua.Tags, 2, length(ua.Tags)-2), '><')) AS T(tag)
    WHERE ua.Reputation BETWEEN 10000 AND 50000 AND ua.PostType = 'Question' AND ua.Tags IS NOT NULL
    GROUP BY T.tag
    ORDER BY TagCount DESC
    LIMIT 10)
)
-- Final SELECT statement combining all the data
SELECT
    usa.DisplayName,
    usa.Reputation,
    usa.TotalPosts,
    usa.QuestionCount,
    usa.AnswerCount,
    CAST(usa.AveragePostScore AS DECIMAL(10, 2)) AS AvgScore,
    usa.PeakMovingAvgScore,
    usa.GoldBadges,
    -- Complex CASE expression and string manipulation
    CASE
        WHEN usa.HasEditedOthersPosts THEN 'Collaborator'
        WHEN usa.QuestionCount > usa.AnswerCount * 2 THEN 'Inquisitor'
        WHEN usa.AnswerCount > usa.QuestionCount * 2 THEN 'Problem Solver'
        ELSE 'Generalist'
    END || ' (' || SUBSTRING(MD5(usa.DisplayName), 1, 8) || ')' AS UserProfile,
    ta.UserGroup AS TopTagGroup,
    ta.tag AS PopularTag,
    -- Final ranking using a window function over the calculated score
    DENSE_RANK() OVER (ORDER BY (usa.Reputation * 0.4 + usa.PeakMovingAvgScore * 0.6) DESC) AS FinalRank
FROM UserStatsAggregation usa
-- Outer join to the tag analysis, which may not have a match for every user
LEFT JOIN TagAnalysis ta ON (usa.Reputation > 50000 AND ta.UserGroup = 'HighRepUsers') OR (usa.Reputation BETWEEN 10000 AND 50000 AND ta.UserGroup = 'MidRepUsers')
-- Final filtering based on a calculation
WHERE (usa.AveragePostScore * usa.AnswerCount) > 100 AND usa.GoldBadges > 0
ORDER BY FinalRank, usa.Reputation DESC, PopularTag NULLS LAST
LIMIT 200;
