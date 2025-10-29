-- {"query": "7689.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1647}
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.ViewCount, 0) + COALESCE(p.Score, 0) AS ViewScoreSum,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountPerPost
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= DATE '2020-01-01' AND p.CreationDate < DATE '2023-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT p.PostTypeId) AS PostTypesUsed,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT CAST(p.PostTypeId AS VARCHAR), ',') AS PostTypeList,
        CASE 
            WHEN COUNT(p.Id) > 100 THEN 'High'
            WHEN COUNT(p.Id) > 50 THEN 'Medium'
            ELSE 'Low'
        END AS ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
PostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.Title,
        ps.Tags,
        ps.Body,
        ps.PostType,
        ps.ViewScoreSum,
        ps.UserPostRank,
        ps.CommentCountPerPost,
        DENSE_RANK() OVER (ORDER BY ps.ViewScoreSum DESC) AS RankByViewScore,
        PERCENT_RANK() OVER (ORDER BY ps.ViewScoreSum) AS PercentileRank,
        LAG(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) AS PrevScore,
        LEAD(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) AS NextScore,
        AVG(ps.Score) OVER (PARTITION BY ps.OwnerUserId) AS AvgScoreByUser,
        COUNT(*) OVER (PARTITION BY ps.OwnerUserId) AS TotalPostsByUser,
        CASE 
            WHEN ps.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = ps.PostTypeId) 
            THEN 'AboveAvg'
            ELSE 'BelowAvg'
        END AS ScoreCategory
    FROM PostStats ps
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END AS TagPopularity,
        RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) AS PrevCount,
        (t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC)) AS CountChange
    FROM Tags t
),
CombinedData AS (
    SELECT 
        pa.PostId,
        pa.PostTypeId,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.Title,
        pa.Tags,
        pa.Body,
        pa.PostType,
        pa.ViewScoreSum,
        pa.UserPostRank,
        pa.CommentCountPerPost,
        pa.RankByViewScore,
        pa.PercentileRank,
        pa.PrevScore,
        pa.NextScore,
        pa.AvgScoreByUser,
        pa.TotalPostsByUser,
        pa.ScoreCategory,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts AS UserTotalPosts,
        ua.PostTypesUsed,
        ua.AvgScore AS UserAvgScore,
        ua.LastPostDate,
        ua.PostTypeList,
        ua.ActivityLevel,
        ta.TagName,
        ta.Count AS TagCount,
        ta.TagPopularity,
        ta.PopularityRank,
        ta.CountChange
    FROM PostAnalysis pa
    LEFT JOIN UserActivity ua ON pa.OwnerUserId = ua.UserId
    LEFT JOIN (
        SELECT 
            p.Id AS PostId,
            t.TagName,
            t.Count,
            CASE 
                WHEN t.Count > 1000 THEN 'Popular'
                WHEN t.Count > 100 THEN 'Moderate'
                ELSE 'Niche'
            END AS TagPopularity,
            RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank,
            (t.Count - LAG(t.Count) OVER (ORDER BY t.Count DESC)) AS CountChange
        FROM Posts p
        JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
        WHERE p.PostTypeId = 1
    ) ta ON pa.PostId = ta.PostId
)
SELECT 
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT cd.PostId) AS UniquePosts,
    COUNT(DISTINCT cd.OwnerUserId) AS UniqueUsers,
    AVG(cd.Score) AS AvgPostScore,
    AVG(cd.ViewCount) AS AvgViewCount,
    AVG(cd.AnswerCount) AS AvgAnswerCount,
    AVG(cd.CommentCount) AS AvgCommentCount,
    AVG(cd.FavoriteCount) AS AvgFavoriteCount,
    MAX(cd.Reputation) AS MaxReputation,
    MIN(cd.Reputation) AS MinReputation,
    STRING_AGG(DISTINCT cd.PostType, ',') AS PostTypesInData,
    STRING_AGG(DISTINCT cd.TagPopularity, ',') AS TagPopularities,
    STRING_AGG(DISTINCT cd.ActivityLevel, ',') AS UserActivityLevels,
    COUNT(CASE WHEN cd.ScoreCategory = 'AboveAvg' THEN 1 END) AS PostsAboveAverageScore,
    COUNT(CASE WHEN cd.ScoreCategory = 'BelowAvg' THEN 1 END) AS PostsBelowAverageScore,
    AVG(COALESCE(cd.TagCount, 0)) AS AvgTagCount,
    COUNT(CASE WHEN cd.TagPopularity = 'Popular' THEN 1 END) AS PopularTagsCount,
    COUNT(CASE WHEN cd.TagPopularity = 'Moderate' THEN 1 END) AS ModerateTagsCount,
    COUNT(CASE WHEN cd.TagPopularity = 'Niche' THEN 1 END) AS NicheTagsCount,
    AVG(cd.UserAvgScore) AS OverallUserAvgScore,
    COUNT(CASE WHEN cd.UserTotalPosts > 100 THEN 1 END) AS HighActivityUsers,
    COUNT(CASE WHEN cd.UserTotalPosts BETWEEN 50 AND 100 THEN 1 END) AS MediumActivityUsers,
    COUNT(CASE WHEN cd.UserTotalPosts < 50 THEN 1 END) AS LowActivityUsers
FROM CombinedData cd
WHERE cd.CreationDate >= DATE '2020-01-01' AND cd.CreationDate < DATE '2023-01-01'
    AND cd.OwnerUserId IS NOT NULL
    AND cd.Score IS NOT NULL
    AND cd.ViewCount IS NOT NULL
    AND COALESCE(cd.AnswerCount, 0) >= 0
    AND COALESCE(cd.FavoriteCount, 0) >= 0;