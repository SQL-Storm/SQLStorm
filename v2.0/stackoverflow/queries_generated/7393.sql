-- {"query": "7393.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2404} 
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
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CASE 
                    WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Elite'
                    WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Veteran'
                    WHEN COUNT(DISTINCT p.Id) > 25 THEN 'Experienced'
                    ELSE 'Beginner'
                END
            ELSE 'Inactive'
        END as ExperienceLevel,
        ROUND(
            (COALESCE(SUM(p.Score), 0) * 100.0) / 
            NULLIF(COUNT(DISTINCT p.Id), 0), 2
        ) as AvgScorePerPost,
        CAST(
            ROUND(
                CASE 
                    WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                        (COUNT(DISTINCT p.Id) * 100.0) / 
                        (DATE_PART('day', NOW() - u.CreationDate) + 1)
                    ELSE 0 
                END, 2) AS INTEGER
        ) as PostsPerDay
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > '2010-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTaggers AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(t.Id) as TagCount,
        STRING_AGG(t.TagName, ', ' ORDER BY t.Count DESC) as TopTags,
        MAX(t.Count) as MaxTagCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(t.Id) DESC, u.Reputation DESC) as TagRank
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    INNER JOIN (
        SELECT 
            PostId,
            TRIM(BOTH '<>' FROM unnest(string_to_array(Tags, '><'))) as Tag
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags != ''
    ) pt ON p.Id = pt.PostId
    INNER JOIN Tags t ON pt.Tag = t.TagName
    WHERE p.PostTypeId = 1 -- Questions only
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(t.Id) >= 5
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        COALESCE(p.Body, '') as BodyText,
        LENGTH(COALESCE(p.Body, '')) as BodyLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><'), 1)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                ROUND(p.Score * 100.0 / NULLIF(p.AnswerCount, 0), 2)
            ELSE NULL 
        END as ScorePerAnswer,
        CASE 
            WHEN p.CommentCount > 0 THEN 
                ROUND(p.Score * 100.0 / NULLIF(p.CommentCount, 0), 2)
            ELSE NULL 
        END as ScorePerComment,
        CASE 
            WHEN LENGTH(COALESCE(p.Body, '')) > 1000 THEN 'Long'
            WHEN LENGTH(COALESCE(p.Body, '')) > 500 THEN 'Medium'
            ELSE 'Short'
        END as ContentLengthCategory,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.Score DESC, p.CreationDate DESC
        ) as UserPostRank
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
    AND p.CreationDate > '2020-01-01 00:00:00'
    AND p.ViewCount > 0
),
CombinedAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.ExperienceLevel,
        uas.AvgScorePerPost,
        uas.PostsPerDay,
        COALESCE(ta.TagCount, 0) as TagCount,
        ta.TopTags,
        ta.MaxTagCount,
        ROW_NUMBER() OVER (
            ORDER BY 
                uas.Reputation DESC,
                uas.PostCount DESC,
                uas.BadgeCount DESC
        ) as UserRank,
        COUNT(*) OVER () as TotalUsers,
        AVG(uas.AvgScorePerPost) OVER () as AvgUserScorePerPost,
        STRING_AGG(
            CASE 
                WHEN pca.Score > 0 THEN 
                    CONCAT(pca.Title, ' (', pca.Score, ')')
                ELSE NULL 
            END, 
            ' | ' 
            ORDER BY pca.Score DESC
        ) as TopScores
    FROM UserActivityStats uas
    FULL OUTER JOIN TopTaggers ta ON uas.UserId = ta.UserId
    WHERE uas.UserId IS NOT NULL OR ta.UserId IS NOT NULL
),
UserPostPerformance AS (
    SELECT 
        pca.PostId,
        pca.Title,
        pca.Score,
        pca.ViewCount,
        pca.AnswerCount,
        pca.CommentCount,
        pca.BodyLength,
        pca.TagCount,
        pca.ScorePerAnswer,
        pca.ScorePerComment,
        pca.ContentLengthCategory,
        pca.UserPostRank,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        u.AccountId,
        CASE 
            WHEN pca.Score > (
                SELECT AVG(Score) 
                FROM Posts 
                WHERE PostTypeId = 1 
                AND CreationDate > '2020-01-01'
            ) THEN 'Above Average'
            WHEN pca.Score > (
                SELECT AVG(Score) - 10
                FROM Posts 
                WHERE PostTypeId = 1 
                AND CreationDate > '2020-01-01'
            ) THEN 'Average'
            ELSE 'Below Average'
        END as PerformanceCategory
    FROM PostComplexityAnalysis pca
    INNER JOIN Users u ON pca.OwnerUserId = u.Id
    WHERE pca.UserPostRank <= 3
),
FinalAggregatedAnalysis AS (
    SELECT 
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.PostCount,
        ca.CommentCount,
        ca.BadgeCount,
        ca.ExperienceLevel,
        ca.AvgScorePerPost,
        ca.PostsPerDay,
        ca.TagCount,
        ca.TopTags,
        ca.MaxTagCount,
        ca.UserRank,
        ca.TotalUsers,
        ca.AvgUserScorePerPost,
        ca.TopScores,
        STRING_AGG(
            CASE 
                WHEN upp.Score > 0 THEN 
                    CONCAT(upp.Title, ' (', upp.Score, ')')
                ELSE NULL 
            END, 
            ' | ' 
            ORDER BY upp.Score DESC
        ) as OwnerTopPosts,
        STRING_AGG(
            upp.ContentLengthCategory, 
            ', ' 
            ORDER BY upp.Score DESC
        ) as ContentCategories,
        STRING_AGG(
            CAST(upp.ScorePerAnswer as VARCHAR), 
            ', ' 
            ORDER BY upp.Score DESC
        ) as AverageScoresPerAnswer,
        STRING_AGG(
            CAST(upp.ScorePerComment as VARCHAR), 
            ', ' 
            ORDER BY upp.Score DESC
        ) as AverageScoresPerComment,
        STRING_AGG(
            CAST(upp.BodyLength as VARCHAR), 
            ', ' 
            ORDER BY upp.Score DESC
        ) as BodyLengths
    FROM CombinedAnalysis ca
    LEFT JOIN UserPostPerformance upp ON ca.UserId = upp.OwnerName
    GROUP BY 
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.PostCount,
        ca.CommentCount,
        ca.BadgeCount,
        ca.ExperienceLevel,
        ca.AvgScorePerPost,
        ca.PostsPerDay,
        ca.TagCount,
        ca.TopTags,
        ca.MaxTagCount,
        ca.UserRank,
        ca.TotalUsers,
        ca.AvgUserScorePerPost,
        ca.TopScores
)
SELECT 
    FA.UserId,
    FA.DisplayName,
    FA.Reputation,
    FA.PostCount,
    FA.CommentCount,
    FA.BadgeCount,
    FA.ExperienceLevel,
    FA.AvgScorePerPost,
    FA.PostsPerDay,
    FA.TagCount,
    FA.TopTags,
    FA.MaxTagCount,
    FA.UserRank,
    FA.TotalUsers,
    FA.AvgUserScorePerPost,
    FA.TopScores,
    FA.OwnerTopPosts,
    FA.ContentCategories,
    FA.AverageScoresPerAnswer,
    FA.AverageScoresPerComment,
    FA.BodyLengths,
    CASE 
        WHEN FA.PostCount >= 50 THEN 'High Activity'
        WHEN FA.PostCount >= 25 THEN 'Medium Activity'
        ELSE 'Low Activity'
    END as PostActivityLevel,
    CASE 
        WHEN FA.Reputation > 10000 THEN 'Expert'
        WHEN FA.Reputation > 5000 THEN 'Advanced'
        WHEN FA.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationTier,
    ROW_NUMBER() OVER (ORDER BY FA.Reputation DESC, FA.PostCount DESC) as OverallRank,
    CASE 
        WHEN FA.AvgScorePerPost > (
            SELECT AVG(AvgScorePerPost) 
            FROM CombinedAnalysis
        ) THEN 'Above Average'
        WHEN FA.AvgScorePerPost > (
            SELECT AVG(AvgScorePerPost) - 5
            FROM CombinedAnalysis
        ) THEN 'Average'
        ELSE 'Below Average'
    END as ScorePerformance,
    ROUND(
        (COUNT(*) OVER () - FA.UserRank) * 100.0 / COUNT(*) OVER (), 2
    ) as PercentileRank,
    CONCAT(
        'Rank: ', FA.UserRank, '/', FA.TotalUsers, 
        ' (', ROUND(FA.UserRank * 100.0 / FA.TotalUsers, 2), '%)'
    ) as RankDisplay,
    CASE 
        WHEN FA.TagCount > 10 THEN 'Multiple Specializations'
        WHEN FA.TagCount > 5 THEN 'Specialized'
        ELSE 'Generalist'
    END as TagSpecializationLevel
FROM FinalAggregatedAnalysis FA
WHERE FA.UserRank <= 20
  AND FA.Reputation > 100
  AND (FA.PostCount > 0 OR FA.CommentCount > 0)
ORDER BY FA.UserRank ASC,
         FA.Reputation DESC,
         FA.PostCount DESC;