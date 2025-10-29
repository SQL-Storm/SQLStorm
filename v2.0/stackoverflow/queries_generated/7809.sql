-- {"query": "7809.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2608} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF(DAY, MIN(p.CreationDate), MAX(p.CreationDate)) AS DaysActive,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        ROUND(CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0), 2) AS AvgQuestionScore,
        ROUND(CAST(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END), 0), 2) AS AvgAnswerScore,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS ScoreRank,
        NTILE(10) OVER (ORDER BY SUM(p.Score) DESC) AS ScoreDecile,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 100 THEN 'Elite'
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 50 THEN 'Veteran'
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10 THEN 'Regular'
            ELSE 'Newbie'
        END AS UserTier,
        STRING_AGG(DISTINCT p.Tags, ';') AS AllTags,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PrevReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankByType,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) * 1.5 FROM Posts WHERE PostTypeId = 1) AND p.PostTypeId = 1 THEN 'HighlyUpvotedQuestion'
            WHEN p.Score > (SELECT AVG(Score) * 1.5 FROM Posts WHERE PostTypeId = 2) AND p.PostTypeId = 2 THEN 'HighlyUpvotedAnswer'
            WHEN p.Score > (SELECT AVG(Score) * 1.5 FROM Posts WHERE PostTypeId = 1) AND p.PostTypeId = 1 THEN 'HighlyUpvotedQuestion'
            WHEN p.Score > (SELECT AVG(Score) * 1.5 FROM Posts WHERE PostTypeId = 2) AND p.PostTypeId = 2 THEN 'HighlyUpvotedAnswer'
            ELSE 'Regular'
        END AS PostClassification,
        DENSE_RANK() OVER (ORDER BY LENGTH(p.Tags) DESC) AS TagLengthRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserTagAnalysis AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        STRING_AGG(DISTINCT 
            CASE 
                WHEN p.PostTypeId = 1 THEN 
                    COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), 'No Tags')
                WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 
                    COALESCE((SELECT Tags FROM Posts WHERE Id = p.ParentId), 'No Tags')
                ELSE 'Unknown'
            END, ';') AS UserTags,
        COUNT(DISTINCT CASE 
            WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN 
                REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ', '') 
            ELSE NULL 
        END) AS TagCount,
        STDEV(p.Score) AS ScoreStdDev,
        AVG(p.Score) AS AvgScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.Tags IS NOT NULL
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.Badges,
    ua.LastPostDate,
    ua.DaysActive,
    ua.TotalScore,
    ua.AvgQuestionScore,
    ua.AvgAnswerScore,
    ua.ScoreRank,
    ua.ScoreDecile,
    ua.UserTier,
    ua.AllTags,
    ua.PrevReputation,
    
    CASE 
        WHEN tp.PostId IS NOT NULL THEN 
            CONCAT('Top ', tp.ScoreRankByType, ' ', 
                CASE WHEN tp.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END, 
                ': ', tp.Title, ' (Score: ', tp.Score, ')')
        ELSE 'No Top Posts'
    END AS TopPostInfo,
    
    COALESCE(uta.UserTags, 'No Tags') AS UserTagAnalysis,
    COALESCE(uta.TagCount, 0) AS TagCount,
    COALESCE(uta.ScoreStdDev, 0) AS TagScoreStdDev,
    COALESCE(uta.AvgScore, 0) AS TagAvgScore,
    
    -- Complex Window Function Logic
    SUM(ua.TotalScore) OVER (
        ORDER BY ua.ScoreRank ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING
    ) AS ScoreRollingAvg,
    
    -- Correlated Subqueries
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId AND p2.PostTypeId = 1 AND p2.CreationDate > '2023-01-01') AS RecentQuestions,
    
    -- Set Operators Analysis
    CASE 
        WHEN EXISTS (SELECT * FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1) 
             AND EXISTS (SELECT * FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 2) 
        THEN 'Questioner and Answerer'
        WHEN EXISTS (SELECT * FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1) 
        THEN 'Questioner Only'
        WHEN EXISTS (SELECT * FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 2) 
        THEN 'Answerer Only'
        ELSE 'Neither'
    END AS PostTypeActivity,
    
    -- String Manipulation and Calculations
    CONCAT(
        'Reputation: ', ua.Reputation,
        ', Posts: ', ua.TotalPosts,
        ', Tags: ', CASE WHEN COALESCE(uta.TagCount, 0) > 0 THEN CAST(uta.TagCount AS VARCHAR) ELSE '0' END
    ) AS UserProfileSummary,
    
    -- NULL Handling with COALESCE
    COALESCE(tp.Title, 'N/A') AS TopPostTitle,
    COALESCE(tp.Score, 0) AS TopPostScore,
    
    -- Complex Expression with Aggregation
    ROUND(
        CASE 
            WHEN (ua.TotalPosts + ua.Answers + ua.Questions) > 0 THEN 
                (COALESCE(uta.ScoreStdDev, 0) * 100.0 / NULLIF((ua.TotalPosts + ua.Answers + ua.Questions), 0))
            ELSE 0 
        END, 2
    ) AS NormalizedScoreVariation,

    -- Conditional Logic with NULLIF
    NULLIF(ua.Reputation / NULLIF(ua.DaysActive, 0), 0) AS ReputationPerDay,
    
    -- CTE Data Joins
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostLinks pl 
            JOIN Posts p ON pl.RelatedPostId = p.Id 
            WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId) 
            AND pl.LinkTypeId = 3
        ) THEN 'Has Duplicate Links'
        ELSE 'No Duplicate Links'
    END AS HasDuplicateLinks

FROM UserActivityStats ua
LEFT JOIN TopPosts tp ON tp.PostId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId AND PostTypeId IN (1, 2)
    ORDER BY Score DESC
    LIMIT 1
)
LEFT JOIN UserTagAnalysis uta ON ua.UserId = uta.UserId

WHERE ua.Reputation > 1000
  AND (ua.TotalPosts > 0 OR ua.Answers > 0 OR ua.Questions > 0)

UNION ALL

-- Additional set operator for high activity users
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.Badges,
    ua.LastPostDate,
    ua.DaysActive,
    ua.TotalScore,
    ua.AvgQuestionScore,
    ua.AvgAnswerScore,
    ua.ScoreRank,
    ua.ScoreDecile,
    ua.UserTier,
    ua.AllTags,
    ua.PrevReputation,
    CONCAT('Top ', tp.ScoreRankByType, ' ', 
        CASE WHEN tp.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END, 
        ': ', tp.Title, ' (Score: ', tp.Score, ')'),
    COALESCE(uta.UserTags, 'No Tags'),
    COALESCE(uta.TagCount, 0),
    COALESCE(uta.ScoreStdDev, 0),
    COALESCE(uta.AvgScore, 0),
    SUM(ua.TotalScore) OVER (
        ORDER BY ua.ScoreRank ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING
    ),
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId AND p2.PostTypeId = 1 AND p2.CreationDate > '2023-01-01'),
    'Questioner and Answerer',
    CONCAT(
        'Reputation: ', ua.Reputation,
        ', Posts: ', ua.TotalPosts,
        ', Tags: ', CASE WHEN COALESCE(uta.TagCount, 0) > 0 THEN CAST(uta.TagCount AS VARCHAR) ELSE '0' END
    ),
    COALESCE(tp.Title, 'N/A'),
    COALESCE(tp.Score, 0),
    ROUND(
        CASE 
            WHEN (ua.TotalPosts + ua.Answers + ua.Questions) > 0 THEN 
                (COALESCE(uta.ScoreStdDev, 0) * 100.0 / NULLIF((ua.TotalPosts + ua.Answers + ua.Questions), 0))
            ELSE 0 
        END, 2
    ),
    NULLIF(ua.Reputation / NULLIF(ua.DaysActive, 0), 0),
    'Has Duplicate Links'

FROM UserActivityStats ua
LEFT JOIN TopPosts tp ON tp.PostId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId AND PostTypeId IN (1, 2)
    ORDER BY Score DESC
    LIMIT 1
)
LEFT JOIN UserTagAnalysis uta ON ua.UserId = uta.UserId

WHERE ua.Reputation > 50000
  AND (ua.TotalPosts > 10 OR ua.Answers > 10 OR ua.Questions > 10)

ORDER BY ScoreRank
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;