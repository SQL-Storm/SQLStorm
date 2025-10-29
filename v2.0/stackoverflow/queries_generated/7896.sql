-- {"query": "7896.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2751} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) as PositiveScorePosts,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Newbie'
        END as UserTier,
        -- Complex calculation for user engagement score
        (COUNT(DISTINCT p.Id) * 0.3 + 
         COUNT(DISTINCT c.Id) * 0.2 + 
         COUNT(DISTINCT b.Id) * 0.5 + 
         (CASE WHEN u.Views > 10000 THEN 100 ELSE u.Views / 100 END) * 0.1) as EngagementScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TagUsers,
        COUNT(DISTINCT p.Id) as PostCount,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 100 AND p.PostTypeId = 1
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        CASE 
            WHEN LEN(p.Body) > 1000 THEN 'Long'
            WHEN LEN(p.Body) > 500 THEN 'Medium'
            WHEN LEN(p.Body) > 100 THEN 'Short'
            ELSE 'Very Short'
        END as ContentLengthCategory,
        -- Extract tag counts
        (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '<', '')) + 1) as TagCount,
        -- Calculate reading time estimate (assuming 200 words per minute)
        CAST(LEN(p.Body) / 5.0 AS INTEGER) as EstimatedReadingTimeMinutes,
        -- Determine answer quality based on ratio
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                CAST(
                    (COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) * 100.0) / 
                    NULLIF(p.AnswerCount, 0) 
                AS INTEGER)
            ELSE 0 
        END as AvgAnswerUpvotePercentage,
        -- Tag-based analysis
        CASE 
            WHEN p.Tags LIKE '%<java>%' THEN 'Java'
            WHEN p.Tags LIKE '%<python>%' THEN 'Python'
            WHEN p.Tags LIKE '%<javascript>%' THEN 'JavaScript'
            WHEN p.Tags LIKE '%<c#>%' THEN 'C#'
            ELSE 'Other'
        END as LanguageCategory
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2022-01-01'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
             p.CommentCount, p.CreationDate, p.OwnerUserId, u.DisplayName, p.Tags
),
CombinedAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.PostRank,
        uas.ReputationRank,
        uas.UserTier,
        uas.EngagementScore,
        ta.TagName,
        ta.Count as TagCount,
        ta.PostCount,
        ta.AvgScore,
        pca.Id as PostId,
        pca.Title,
        pca.Score as PostScore,
        pca.ViewCount,
        pca.AnswerCount,
        pca.CommentCount,
        pca.EstimatedReadingTimeMinutes,
        pca.AvgAnswerUpvotePercentage,
        'ScoreRank_' || 
        CASE 
            WHEN pca.Score > 100 THEN 'High'
            WHEN pca.Score > 50 THEN 'Medium'
            WHEN pca.Score > 10 THEN 'Low'
            ELSE 'VeryLow'
        END as ScoreCategory,
        -- Complex string manipulation
        UPPER(SUBSTRING(pca.Title, 1, 1)) || 
        LOWER(SUBSTRING(pca.Title, 2, 
            CASE WHEN CHARINDEX(' ', pca.Title) > 0 THEN CHARINDEX(' ', pca.Title) - 1 ELSE LEN(pca.Title) END
        )) || '...' as TitlePreview,
        -- Conditional formatting for display
        CASE 
            WHEN pca.ViewCount > 1000 THEN 'Viral'
            WHEN pca.ViewCount > 100 THEN 'Popular'
            WHEN pca.ViewCount > 10 THEN 'Noticeable'
            ELSE 'Obscure'
        END as PopularityLevel
    FROM UserActivityStats uas
    LEFT JOIN TopTags ta ON uas.Reputation > 5000
    LEFT JOIN PostComplexityAnalysis pca ON uas.UserId = pca.OwnerUserId
    WHERE uas.TotalPosts > 0
)

SELECT 
    CA.UserId,
    CA.DisplayName,
    CA.Reputation,
    CA.TotalPosts,
    CA.Questions,
    CA.Answers,
    CA.Comments,
    CA.Badges,
    CA.PostRank,
    CA.ReputationRank,
    CA.UserTier,
    CA.EngagementScore,
    CA.TagName,
    CA.TagCount,
    CA.PostCount,
    CA.AvgScore,
    CA.PostId,
    CA.Title,
    CA.Score as PostScore,
    CA.ViewCount,
    CA.AnswerCount,
    CA.CommentCount,
    CA.EstimatedReadingTimeMinutes,
    CA.AvgAnswerUpvotePercentage,
    CA.ScoreCategory,
    CA.TitlePreview,
    CA.PopularityLevel,
    -- Advanced NULL handling and coalescing
    COALESCE(CA.TagName, 'No Tags') as EffectiveTagName,
    ISNULL(CA.Title, 'Untitled') as EffectiveTitle,
    CASE 
        WHEN CA.EffectiveTagName = 'No Tags' THEN 'N/A'
        WHEN CA.AvgScore > 50 THEN 'High Impact'
        WHEN CA.AvgScore > 25 THEN 'Mid Impact'
        ELSE 'Low Impact'
    END as TagImpactLevel,
    -- Set operation example with complex predicates
    CAST(
        (CASE 
            WHEN CA.TotalPosts > 100 THEN 10
            WHEN CA.TotalPosts > 50 THEN 5
            WHEN CA.TotalPosts > 10 THEN 2
            ELSE 1
        END) 
        * 
        (CASE 
            WHEN CA.Reputation > 10000 THEN 2
            WHEN CA.Reputation > 5000 THEN 1.5
            WHEN CA.Reputation > 1000 THEN 1
            ELSE 0.5
        END)
        AS INTEGER
    ) as InfluenceWeight,
    -- Window function analysis
    ROW_NUMBER() OVER (PARTITION BY CA.UserTier ORDER BY CA.EngagementScore DESC) as TierEngagementRank,
    RANK() OVER (ORDER BY CA.EngagementScore DESC) as OverallEngagementRank,
    DENSE_RANK() OVER (ORDER BY CA.Reputation DESC) as ReputationDensityRank,
    -- Complex mathematical calculation
    (CA.EngagementScore * 
     SQRT(CA.TotalPosts + 1) * 
     LOG(CA.Reputation + 1)) as ComplexUserScore,
    -- Date and time manipulations
    DATEDIFF(day, CA.LastPostDate, '2023-01-01') as DaysSinceLastPost,
    DATEDIFF(day, '2022-01-01', CA.LastPostDate) as DaysActive,
    -- String manipulation with padding and concatenation
    REPLICATE('*', 
        CASE WHEN CA.Reputation > 5000 THEN 3 
             WHEN CA.Reputation > 1000 THEN 2 
             ELSE 1 END
    ) as ReputationStars,
    -- Correlated subquery example
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = CA.UserId 
     AND p2.CreationDate > '2022-06-01') as RecentPostCount,
    -- Conditional aggregation
    SUM(CASE WHEN CA.PostScore > 10 THEN 1 ELSE 0 END) OVER (PARTITION BY CA.UserId) as HighScorePosts,
    -- Multiple set operators combined
    CASE 
        WHEN (SELECT COUNT(*) FROM CombinedAnalysis ca2 WHERE ca2.UserId = CA.UserId AND ca2.PostScore > 100) > 0 THEN 'Elite Posts'
        WHEN (SELECT COUNT(*) FROM CombinedAnalysis ca3 WHERE ca3.UserId = CA.UserId AND ca3.PostScore > 50) > 0 THEN 'Good Posts'
        ELSE 'Average Posts'
    END as PostQualityLevel,
    -- Final calculated field
    CASE 
        WHEN CA.PostCount > 0 AND CA.AvgScore > 0 THEN 
            CONCAT(
                'User ', CA.DisplayName, 
                ' has ', 
                CAST(CA.PostCount AS VARCHAR(10)), 
                ' posts with average score of ', 
                CAST(CA.AvgScore AS VARCHAR(10))
            )
        ELSE 'No significant post activity'
    END as UserContributionSummary
FROM CombinedAnalysis CA
WHERE CA.PostId IS NOT NULL
  AND (CA.Reputation > 100 OR CA.TotalPosts > 5)
  AND CA.DisplayName IS NOT NULL
  AND CA.Title IS NOT NULL
  -- Complex composite predicate
  AND (
    (CA.TagName IS NULL AND CA.PostCount IS NULL) 
    OR 
    (CA.TagCount > 0 AND CA.PostCount > 10)
  )
  AND (
    CA.ViewCount > 100 
    OR 
    CA.CommentCount > 5
    OR
    CA.AvgAnswerUpvotePercentage > 50
  )
ORDER BY 
    CASE WHEN CA.EngagementScore > 1000 THEN 1 ELSE 2 END,
    CA.TotalPosts DESC,
    CA.Reputation DESC,
    CA.LastPostDate DESC
OFFSET 100 ROWS FETCH NEXT 100 ROWS ONLY
HAVING COUNT(*) > 0
GROUP BY 
    CA.UserId,
    CA.DisplayName,
    CA.Reputation,
    CA.TotalPosts,
    CA.Questions,
    CA.Answers,
    CA.Comments,
    CA.Badges,
    CA.PostRank,
    CA.ReputationRank,
    CA.UserTier,
    CA.EngagementScore,
    CA.TagName,
    CA.TagCount,
    CA.PostCount,
    CA.AvgScore,
    CA.PostId,
    CA.Title,
    CA.Score,
    CA.ViewCount,
    CA.AnswerCount,
    CA.CommentCount,
    CA.EstimatedReadingTimeMinutes,
    CA.AvgAnswerUpvotePercentage,
    CA.ScoreCategory,
    CA.TitlePreview,
    CA.PopularityLevel,
    CA.LastPostDate
HAVING 
    COUNT(*) > 1 
    OR MAX(CA.TagCount) > 5;