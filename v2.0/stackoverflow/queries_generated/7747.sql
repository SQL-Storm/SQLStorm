-- {"query": "7747.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2299} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) as rn
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.Tags, '') as Tags,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Well Voted'
            WHEN p.Score > 10 THEN 'Moderately Voted'
            ELSE 'Low Voted'
        END as VoteCategory,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) as NextScore,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as RollingAvgScore
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
    AND p.Score IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as ActiveUsers,
        COUNT(DISTINCT p.Id) as RelatedQuestions,
        AVG(p.Score) as AvgQuestionScore
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.TagName IS NOT NULL
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
UserPerformance AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        CASE 
            WHEN u.Reputation > 100000 THEN 'Elite'
            WHEN u.Reputation > 10000 THEN 'Senior'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            WHEN u.Reputation > 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationLevel,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgScore,
        MAX(p.CreationDate) as LastActivity,
        DATEDIFF(day, u.CreationDate, CURRENT_TIMESTAMP) as AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Moderate'
            ELSE 'Low Activity'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT ua.UserId) as ActiveUsers,
    COUNT(DISTINCT tp.PostId) as TotalPosts,
    COUNT(DISTINCT ta.TagName) as TotalTags,
    AVG(up.TotalScore) as AvgUserScore,
    MAX(tp.Score) as MaxPostScore,
    MIN(tp.Score) as MinPostScore,
    AVG(tp.ViewCount) as AvgViewCount,
    STRING_AGG(DISTINCT tp.PostType, ', ') as PostTypes,
    STRING_AGG(DISTINCT up.ReputationLevel, ', ') as ReputationLevels,
    STRING_AGG(DISTINCT ta.PopularityLevel, ', ') as TagPopularityLevels,
    (SELECT COUNT(*) FROM Posts WHERE Score > (SELECT AVG(Score) FROM Posts)) as HighScorePosts,
    (SELECT COUNT(*) FROM Users WHERE Reputation > (SELECT AVG(Reputation) FROM Users)) as HighRepUsers,
    (SELECT COUNT(*) FROM Tags WHERE Count > (SELECT AVG(Count) FROM Tags)) as PopularTags,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.ParentId IS NOT NULL AND p.PostTypeId = 2) THEN 'Answers Present'
        ELSE 'No Answers'
    END as AnswerStatus,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != '') THEN 'Questions with Tags'
        ELSE 'No Tagged Questions'
    END as TagStatus,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Comments c JOIN Posts p ON c.PostId = p.Id WHERE p.PostTypeId = 1) THEN 'Commented Questions'
        ELSE 'No Commented Questions'
    END as CommentStatus,
    NULL as TestValue1,
    NULL as TestValue2,
    NULL as TestValue3,
    NULL as TestValue4
FROM UserActivityStats ua
FULL OUTER JOIN TopPosts tp ON ua.UserId = tp.OwnerName
FULL OUTER JOIN TagAnalysis ta ON ta.TagName = (
    SELECT t.TagName FROM Tags t 
    WHERE t.Count = (SELECT MAX(Count) FROM Tags)
    LIMIT 1
)
FULL OUTER JOIN UserPerformance up ON up.UserId = ua.UserId
WHERE ua.UserId IS NOT NULL 
   OR tp.PostId IS NOT NULL 
   OR ta.TagName IS NOT NULL 
   OR up.UserId IS NOT NULL
GROUP BY 
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts WHERE Score > (SELECT AVG(Score) FROM Posts)) THEN 'High Score Posts Present'
        ELSE 'No High Score Posts'
    END,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Users WHERE Reputation > (SELECT AVG(Reputation) FROM Users)) THEN 'High Rep Users Present'
        ELSE 'No High Rep Users'
    END
HAVING COUNT(*) > 0
UNION ALL
SELECT 
    'Detailed Analysis Report' as ReportTitle,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT u.Id) as ActiveUsers,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT t.Id) as TotalTags,
    AVG(p.Score) as AvgScore,
    MAX(p.Score) as MaxScore,
    MIN(p.Score) as MinScore,
    AVG(p.ViewCount) as AvgViews,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN 'Question' WHEN p.PostTypeId = 2 THEN 'Answer' END, ', ') as PostTypes,
    STRING_AGG(DISTINCT CASE 
        WHEN u.Reputation > 100000 THEN 'Elite'
        WHEN u.Reputation > 10000 THEN 'Senior'
        WHEN u.Reputation > 1000 THEN 'Intermediate'
        WHEN u.Reputation > 100 THEN 'Novice'
        ELSE 'Beginner'
    END, ', ') as RepLevels,
    STRING_AGG(DISTINCT CASE 
        WHEN t.Count > 1000 THEN 'Popular'
        WHEN t.Count > 100 THEN 'Moderate'
        WHEN t.Count > 10 THEN 'Niche'
        ELSE 'Rare'
    END, ', ') as TagLevels,
    (SELECT COUNT(*) FROM Posts WHERE Score > 100) as HighScoreCount,
    (SELECT COUNT(*) FROM Users WHERE Reputation > 10000) as HighRepCount,
    (SELECT COUNT(*) FROM Tags WHERE Count > 100) as PopularTagCount,
    'Analysis Complete' as StatusIndicator,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.ParentId IS NOT NULL AND p.PostTypeId = 2) THEN 'Yes'
        ELSE 'No'
    END as HasAnswers,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != '') THEN 'Yes'
        ELSE 'No'
    END as HasTags,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Comments c JOIN Posts p ON c.PostId = p.Id WHERE p.PostTypeId = 1) THEN 'Yes'
        ELSE 'No'
    END as HasComments,
    NULL as ExtraField1,
    NULL as ExtraField2,
    NULL as ExtraField3,
    NULL as ExtraField4
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE p.Score IS NOT NULL
GROUP BY 
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts WHERE Score > 100) THEN 1
        ELSE 0
    END,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Users WHERE Reputation > 10000) THEN 1
        ELSE 0
    END,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Tags WHERE Count > 100) THEN 1
        ELSE 0
    END,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.ParentId IS NOT NULL AND p.PostTypeId = 2) THEN 1
        ELSE 0
    END,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != '') THEN 1
        ELSE 0
    END
HAVING COUNT(*) > 0
ORDER BY ReportTitle;