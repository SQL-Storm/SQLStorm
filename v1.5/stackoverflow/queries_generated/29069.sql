-- {"query": "29069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2055} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        ROW_NUMBER() OVER (ORDER BY u.CreationDate) AS NewbieRank,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
                 AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
            THEN 'Both Q&A'
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
            THEN 'Questioner'
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
            THEN 'Answerer'
            ELSE 'Neither'
        END AS UserRole,
        ROUND(AVG(NULLIF(p.Score, 0)), 2) AS AvgPostScore,
        STRING_AGG(
            CASE 
                WHEN p.PostTypeId = 1 THEN 'Q'
                WHEN p.PostTypeId = 2 THEN 'A'
                ELSE 'Other'
            END, 
            ','
        ) AS PostTypes,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) 
            THEN 'Gold'
            WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) 
            THEN 'Silver'
            WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) 
            THEN 'Bronze'
            ELSE 'None'
        END AS BadgeLevel,
        -- Calculate user's activity score based on various metrics
        (COUNT(DISTINCT p.Id) * 10 + 
         COUNT(DISTINCT c.Id) * 5 + 
         COUNT(DISTINCT b.Id) * 20 + 
         COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) * 2 +
         COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) * 1) AS ActivityScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01'::timestamp 
      AND u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopUsers AS (
    SELECT * FROM UserActivityStats 
    WHERE PostRank <= 100 AND RepRank <= 100
),
PostDetails AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        -- Use correlated subquery to calculate rank of post within user's posts
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate DESC
        ) AS UserPostRank,
        -- Use window function to calculate cummulative stats
        SUM(p.Score) OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS CumulativeScore,
        -- Use set operator to find posts that have been edited
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (5, 8, 25)
            ) THEN 'Edited' 
            ELSE 'Not Edited' 
        END AS EditStatus,
        -- Complex string expression and conditional logic
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 
            THEN 'Tagged'
            WHEN EXISTS (
                SELECT 1 FROM PostLinks pl
                WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
            ) 
            THEN 'Linked'
            WHEN p.PostTypeId = 1 
            THEN 'Question'
            WHEN p.PostTypeId = 2 
            THEN 'Answer'
            ELSE 'Other'
        END AS PostClassification,
        -- Calculated field with NULL handling
        COALESCE(p.Score, 0) + 
        COALESCE(p.ViewCount, 0) + 
        COALESCE(p.AnswerCount, 0) -
        COALESCE(p.CommentCount, 0) AS CompositeMetric
    FROM Posts p
    WHERE p.CreationDate >= '2011-01-01'::timestamp
),
FilteredPosts AS (
    -- Use set operators for finding posts with complex filtering
    SELECT PostId, PostTypeId
    FROM PostDetails 
    WHERE PostClassification IN ('Question', 'Answer')
    
    UNION
    
    SELECT PostId, PostTypeId
    FROM PostDetails 
    WHERE CompositeMetric > 100 AND Score > 5
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(pd.PostId) AS TotalPostsByUser,
        AVG(pd.Score) AS AvgScorePerPost,
        MAX(pd.ViewCount) AS MaxViews,
        STRING_AGG(pd.Title, ' | ') WITHIN GROUP (ORDER BY pd.CreationDate DESC) AS RecentTitles,
        -- Complex aggregation with CASE expression
        SUM(CASE 
            WHEN pd.PostTypeId = 1 THEN 1 
            ELSE 0 
        END) AS QuestionCount,
        SUM(CASE 
            WHEN pd.PostTypeId = 2 THEN 1 
            ELSE 0 
        END) AS AnswerCount,
        -- Window function for ranking within user activity
        RANK() OVER (ORDER BY AVG(pd.Score) DESC) AS AvgScoreRank
    FROM Users u
    JOIN PostDetails pd ON u.Id = pd.OwnerUserId
    WHERE pd.UserPostRank <= 3
    GROUP BY u.Id, u.DisplayName
)
-- Final complex query combining all previous CTEs with multiple joins and conditions
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    tu.Comments,
    tu.Badges,
    tu.ActivityScore,
    tu.PostTypes,
    tu.UserRole,
    up.TotalPostsByUser,
    up.AvgScorePerPost,
    up.MaxViews,
    pd.PostId,
    pd.Title,
    pd.Score,
    pd.ViewCount,
    pd.CompositeMetric,
    pd.EditStatus,
    pd.PostClassification,
    -- Complex calculated fields
    ROUND(
        (tu.ActivityScore * up.AvgScorePerPost) / NULLIF(pd.ViewCount, 0), 
        2
    ) AS PerformanceRatio,
    -- Date calculations
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pd.CreationDate)) / 86400 AS DaysSincePost,
    -- Conditional logic with NULL handling
    CASE 
        WHEN pd.Score >= 100 THEN 'Popular'
        WHEN pd.Score >= 50 THEN 'Moderate'
        WHEN pd.Score >= 10 THEN 'Low'
        ELSE 'Very Low'
    END AS PopularityLevel,
    -- Multiple set operators combination
    CASE 
        WHEN (
            SELECT COUNT(*) 
            FROM PostHistory ph 
            WHERE ph.PostId = pd.PostId AND ph.PostHistoryTypeId IN (5, 8, 25)
        ) > 0 THEN 'Modified'
        ELSE 'Unmodified'
    END AS ModificationStatus
FROM TopUsers tu
LEFT JOIN UserPostStats up ON tu.UserId = up.UserId
LEFT JOIN PostDetails pd ON tu.UserId = pd.OwnerUserId
LEFT JOIN FilteredPosts fp ON pd.PostId = fp.PostId
WHERE pd.PostId IS NOT NULL
  AND (tu.Reputation > 10000 OR up.AvgScorePerPost > 50)
  AND (
        pd.Score > 100 
        OR pd.ViewCount > 1000 
        OR pd.CompositeMetric > 200
    )
  AND pd.CreationDate >= '2012-01-01'::timestamp
  AND pd.CreationDate <= '2022-12-31'::timestamp
  AND pd.PostClassification IN ('Question', 'Answer')
ORDER BY tu.ActivityScore DESC, pd.CompositeMetric DESC, pd.CreationDate DESC
LIMIT 500;