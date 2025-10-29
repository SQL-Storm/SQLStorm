-- {"query": "7375.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1894} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostRank,
        DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.CreationDate
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        DATEDIFF(day, p.CreationDate, GETDATE()) AS DaysSinceCreation,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        CASE 
            WHEN p.AnswerCount > 5 THEN 'ManyAnswers'
            WHEN p.AnswerCount > 1 THEN 'SomeAnswers'
            ELSE 'FewAnswers'
        END AS AnswerCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'LowView'
        END AS Popularity,
        COALESCE(p.Tags, '') AS TagsList,
        LEN(COALESCE(p.Tags, '')) AS TagLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                STRING_AGG(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), ',') 
                WITHIN GROUP (ORDER BY (SELECT NULL))
            ELSE NULL 
        END AS ExtractedTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
             p.CommentCount, p.FavoriteCount, p.CreationDate, 
             p.OwnerUserId, p.PostTypeId, p.Tags
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.Score) AS MaxScore,
        MIN(p.Score) AS MinScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionPosts,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerPosts,
        STRING_AGG(CAST(p.Id AS VARCHAR), ',') AS PostIds,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts,
        SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativeScorePosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= '2018-01-01'
    GROUP BY u.Id, u.DisplayName
),
ComplexQuery AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.TotalPosts,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.LastPostDate,
        uas.RecentPostRank,
        uas.AccountAgeDays,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount AS PostAnswerCount,
        pa.CommentCount AS PostCommentCount,
        pa.FavoriteCount,
        pa.CreationDate AS PostCreationDate,
        pa.PostTypeId,
        pa.DaysSinceCreation,
        pa.ScoreCategory,
        pa.AnswerCategory,
        pa.Popularity,
        pa.TagsList,
        pa.TagLength,
        pa.ExtractedTags,
        ups.TotalPosts AS UserTotalPosts,
        ups.TotalScore,
        ups.AvgScore,
        ups.MaxScore,
        ups.QuestionPosts,
        ups.AnswerPosts,
        ups.PostIds,
        ups.PositiveScorePosts,
        ups.NegativeScorePosts,
        RANK() OVER (ORDER BY (pa.Score * pa.ViewCount) DESC) AS PostPerformanceRank,
        DENSE_RANK() OVER (PARTITION BY pa.PostTypeId ORDER BY pa.Score DESC) AS TypeSpecificRank,
        NTILE(4) OVER (ORDER BY pa.ViewCount) AS ViewCountQuartile,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = pa.PostTypeId) 
            THEN 'AboveAverage'
            ELSE 'BelowAverage'
        END AS ScorePerformance,
        CASE 
            WHEN pa.Score > (SELECT MAX(Score) FROM Posts WHERE PostTypeId = pa.PostTypeId) * 0.9 
            THEN 'Top90Percent'
            ELSE 'NotTop90Percent'
        END AS HighScorerCategory,
        COALESCE (
            (SELECT TOP 1 p2.Title 
             FROM Posts p2 
             WHERE p2.PostTypeId = 1 
             AND EXISTS (SELECT 1 FROM Comments c2 WHERE c2.PostId = p2.Id AND c2.UserId = uas.UserId)
             ORDER BY p2.CreationDate DESC), 
            'NoRecentComments'
        ) AS UserRecentQuestion,
        CAST(LEN(pa.TagsList) AS FLOAT) / NULLIF(LEN(pa.TagsList) + 1, 0) AS TagDensity
    FROM UserActivityStats uas
    JOIN PostAnalysis pa ON uas.UserId = pa.OwnerUserId
    JOIN UserPostStats ups ON uas.UserId = ups.UserId
    WHERE uas.AccountAgeDays > 365
      AND pa.DaysSinceCreation < 365
      AND pa.Score >= -10
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    Views,
    TotalPosts,
    QuestionCount,
    AnswerCount,
    CommentCount,
    BadgeCount,
    LastPostDate,
    RecentPostRank,
    AccountAgeDays,
    PostId,
    Title,
    Score,
    ViewCount,
    PostAnswerCount,
    PostCommentCount,
    FavoriteCount,
    PostCreationDate,
    PostTypeId,
    DaysSinceCreation,
    ScoreCategory,
    AnswerCategory,
    Popularity,
    TagsList,
    TagLength,
    ExtractedTags,
    UserTotalPosts,
    TotalScore,
    AvgScore,
    MaxScore,
    QuestionPosts,
    AnswerPosts,
    PostIds,
    PositiveScorePosts,
    NegativeScorePosts,
    PostPerformanceRank,
    TypeSpecificRank,
    ViewCountQuartile,
    ScorePerformance,
    HighScorerCategory,
    UserRecentQuestion,
    TagDensity,
    CASE 
        WHEN ABS(AvgScore) > 5 THEN 'HighScoreVariance'
        WHEN ABS(AvgScore) > 2 THEN 'MediumScoreVariance'
        ELSE 'LowScoreVariance'
    END AS ScoreVarianceCategory,
    CASE 
        WHEN AccountAgeDays > 730 AND TotalPosts > 100 THEN 'VeteranActive'
        WHEN AccountAgeDays > 365 AND TotalPosts > 50 THEN 'ActiveRegular'
        WHEN AccountAgeDays > 180 AND TotalPosts > 10 THEN 'RegularUser'
        ELSE 'NewUser'
    END AS UserClassification,
    ROW_NUMBER() OVER (ORDER BY Views DESC, Score DESC) AS OverallRanking,
    PERCENT_RANK() OVER (ORDER BY Score) AS ScorePercentile,
    CUME_DIST() OVER (ORDER BY ViewCount) AS ViewCountCumulativeDistribution,
    LAG(DisplayName) OVER (ORDER BY Reputation DESC) AS PreviousReputableUser,
    LEAD(DisplayName) OVER (ORDER BY Reputation DESC) AS NextReputableUser
FROM ComplexQuery
WHERE Score > 0 OR CommentCount > 0
  AND (PostTypeId = 1 OR PostTypeId = 2)
  AND (PostTypeId = 1 AND AnswerCount > 0 OR PostTypeId = 2 AND AnswerCount IS NULL)
ORDER BY Score DESC, ViewCount DESC, Reputation DESC;