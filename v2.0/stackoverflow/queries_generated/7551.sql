-- {"query": "7551.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2525} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) as ReputationRank,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                ROUND(CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS FLOAT) * 100 / COUNT(DISTINCT p.Id), 2)
            ELSE 0 
        END as QuestionPercentage,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                DENSE_RANK() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) DESC)
            ELSE 0 
        END as AnswerRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionPercentage,
        ReputationRank,
        AnswerRank,
        CASE 
            WHEN Reputation > 100000 THEN 'Elite'
            WHEN Reputation > 50000 THEN 'Veteran'
            WHEN Reputation > 10000 THEN 'Contributor'
            ELSE 'Member'
        END as UserTier,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Score > 100), 
            0
        ) as HighScoreQuestions,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Score > 100), 
            0
        ) as HighScoreAnswers
    FROM UserActivityStats u
    WHERE ReputationRank <= 5000
),
UserPostPatterns AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.UserTier,
        tu.PostCount,
        tu.QuestionPercentage,
        tu.ReputationRank,
        AVG(p.Score) as AveragePostScore,
        MIN(p.CreationDate) as FirstPostDate,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as AnswerCount,
        STRING_AGG(
            CASE 
                WHEN p.PostTypeId = 1 THEN CONCAT('Q:', p.Title, ':', p.Score) 
                WHEN p.PostTypeId = 2 THEN CONCAT('A:', p.Id, ':', p.Score) 
                ELSE NULL 
            END, 
            '; '
        ) as PostSummary,
        ROUND(
            CAST(COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS FLOAT) * 100 / NULLIF(COUNT(p.Id), 0), 
            2
        ) as QuestionRatio,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id) as TotalCommentsOnPosts
    FROM TopUsers tu
    LEFT JOIN Posts p ON tu.UserId = p.OwnerUserId
    WHERE p.CreationDate >= '2015-01-01'
    GROUP BY tu.UserId, tu.DisplayName, tu.UserTier, tu.PostCount, tu.QuestionPercentage, tu.ReputationRank
),
TagAnalytics AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 
            0
        ) as UsedInPosts,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.Count > 50
),
ComplexPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        COALESCE(u.DisplayName, 'Anonymous') as OwnerDisplayName,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as UserPostCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserScoreRank,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 50 THEN 'HighValueQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > 50 THEN 'HighValueAnswer'
            WHEN p.PostTypeId = 1 AND p.Score > 10 THEN 'GoodQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > 10 THEN 'GoodAnswer'
            ELSE 'Other'
        END as PostQuality,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                STRING_AGG(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') 
            ELSE 'No Tags'
        END as TagList,
        CASE 
            WHEN p.CreationDate >= '2020-01-01' THEN 1
            WHEN p.CreationDate >= '2015-01-01' THEN 2
            WHEN p.CreationDate >= '2010-01-01' THEN 3
            ELSE 4
        END as TimeCategory
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate BETWEEN '2010-01-01' AND '2022-12-31'
),
CombinedData AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.UserTier,
        up.PostCount,
        up.QuestionPercentage,
        up.ReputationRank,
        up.HighScoreQuestions,
        up.HighScoreAnswers,
        upp.AveragePostScore,
        upp.FirstPostDate,
        upp.QuestionCount,
        upp.AnswerCount,
        upp.TagList,
        ta.TagName,
        ta.TagPopularity,
        ta.UsedInPosts,
        cp.PostId,
        cp.Title,
        cp.Score,
        cp.PostQuality,
        cp.TimeCategory,
        ROW_NUMBER() OVER (PARTITION BY up.UserId ORDER BY cp.Score DESC) as PostRankByUser,
        DENSE_RANK() OVER (ORDER BY cp.Score DESC) as OverallPostRank
    FROM TopUsers up
    INNER JOIN UserPostPatterns upp ON up.UserId = upp.UserId
    LEFT JOIN ComplexPosts cp ON up.UserId = cp.OwnerUserId
    LEFT JOIN Tags ta ON cp.Tags IS NOT NULL AND ta.TagName IN (
        SELECT TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(cp.Tags, 2, LENGTH(cp.Tags)-2), '><')))
    )
    WHERE cp.Score IS NOT NULL
)
SELECT 
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT UserId) as DistinctUsers,
    COUNT(DISTINCT PostId) as DistinctPosts,
    COUNT(DISTINCT TagName) as DistinctTags,
    AVG(ReputationRank) as AverageReputationRank,
    MAX(PostRankByUser) as MaxPostRank,
    MIN(OverallPostRank) as MinOverallPostRank,
    STRING_AGG(CONCAT(DisplayName, ':', PostCount, ':', Score), '; ') as UserPostSummary,
    STRING_AGG(CONCAT(TagName, ':', TagPopularity, ':', UsedInPosts), '| ') as TagSummary,
    STRING_AGG(CONCAT(PostId, ':', PostQuality, ':', TimeCategory), ', ') as PostSummary
FROM CombinedData
WHERE UserId IS NOT NULL 
  AND PostId IS NOT NULL
  AND Score IS NOT NULL
  AND PostQuality IN ('HighValueQuestion', 'HighValueAnswer')
  AND TimeCategory IN (1, 2)
  AND UserTier IN ('Elite', 'Veteran', 'Contributor')
  AND PostCount >= 5
  AND Score > 25
  AND (ReputationRank BETWEEN 11 AND 1000 OR ReputationRank IS NULL)
GROUP BY 
    UserId, DisplayName, UserTier, PostCount, QuestionPercentage, ReputationRank, HighScoreQuestions, HighScoreAnswers,
    AveragePostScore, FirstPostDate, QuestionCount, AnswerCount, TagList, TagName, TagPopularity, UsedInPosts, PostId, Title, Score, PostQuality, TimeCategory
HAVING 
    COUNT(*) > 1
    AND COUNT(DISTINCT PostId) >= 3
    AND AVG(Score) > 15
    AND MAX(PostRankByUser) > 1
    AND MIN(OverallPostRank) < 2000
UNION ALL
SELECT 
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT UserId) as DistinctUsers,
    COUNT(DISTINCT PostId) as DistinctPosts,
    COUNT(DISTINCT TagName) as DistinctTags,
    AVG(ReputationRank) as AverageReputationRank,
    MAX(PostRankByUser) as MaxPostRank,
    MIN(OverallPostRank) as MinOverallPostRank,
    STRING_AGG(CONCAT(DisplayName, ':', PostCount, ':', Score), '; ') as UserPostSummary,
    STRING_AGG(CONCAT(TagName, ':', TagPopularity, ':', UsedInPosts), '| ') as TagSummary,
    STRING_AGG(CONCAT(PostId, ':', PostQuality, ':', TimeCategory), ', ') as PostSummary
FROM CombinedData
WHERE UserId IS NOT NULL 
  AND PostId IS NOT NULL
  AND Score IS NOT NULL
  AND PostQuality IN ('GoodQuestion', 'GoodAnswer')
  AND TimeCategory IN (3)
  AND UserTier IN ('Member', 'Contributor')
  AND PostCount BETWEEN 1 AND 10
  AND Score > 5
  AND (ReputationRank BETWEEN 100 AND 5000 OR ReputationRank IS NULL)
GROUP BY 
    UserId, DisplayName, UserTier, PostCount, QuestionPercentage, ReputationRank, HighScoreQuestions, HighScoreAnswers,
    AveragePostScore, FirstPostDate, QuestionCount, AnswerCount, TagList, TagName, TagPopularity, UsedInPosts, PostId, Title, Score, PostQuality, TimeCategory
HAVING 
    COUNT(*) > 2
    AND COUNT(DISTINCT PostId) >= 2
    AND AVG(Score) BETWEEN 5 AND 15
    AND MAX(PostRankByUser) > 2
    AND MIN(OverallPostRank) > 2000
ORDER BY TotalRecords DESC
LIMIT 100;