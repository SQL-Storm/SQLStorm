-- {"query": "29095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2683} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PostRank,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS UNBOUNDED PRECEDING) AS CumulativeScore,
        AVG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS AvgViews,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        COALESCE(p.Title, 'No Title') AS SafeTitle,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM UNNEST(string_to_array(trim(trim(p.Tags, '<'), '>')) AS tag) 
                 WHERE tag != '' AND tag IS NOT NULL)
            ELSE 0
        END AS TagCount,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDesc,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) AS AnswerCountActual
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT rp.Id) AS TotalPosts,
        SUM(COALESCE(rp.Score, 0)) AS TotalScore,
        AVG(COALESCE(rp.Score, 0)) AS AvgScore,
        MAX(rp.Score) AS MaxScore,
        COUNT(DISTINCT CASE WHEN rp.Score > 100 THEN rp.Id END) AS HighScorePosts,
        COUNT(DISTINCT CASE WHEN rp.Score <= 100 AND rp.Score > 0 THEN rp.Id END) AS MediumScorePosts,
        COUNT(DISTINCT CASE WHEN rp.Score <= 0 THEN rp.Id END) AS LowScorePosts
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS PostCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS AvgScorePerTag,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName, t.Count
),
ComplexJoin AS (
    SELECT 
        rs.Id AS PostId,
        rs.Title AS PostTitle,
        rs.OwnerUserId,
        rs.Score,
        rs.ViewCount,
        rs.PostTypeDesc,
        rs.TagCount,
        rs.EngagementCount,
        rs.ScoreCategory,
        rs.CumulativeScore,
        rs.AvgViews,
        rs.AnswerCountActual,
        u.DisplayName AS AuthorName,
        u.Reputation AS AuthorReputation,
        u.Views AS AuthorViews,
        us.TotalPosts AS AuthorTotalPosts,
        us.TotalScore AS AuthorTotalScore,
        us.AvgScore AS AuthorAvgScore,
        us.MaxScore AS AuthorMaxScore,
        us.HighScorePosts AS AuthorHighScorePosts,
        CASE 
            WHEN rs.PrevScore IS NOT NULL AND rs.PrevScore != 0 THEN 
                ROUND((rs.Score - rs.PrevScore) * 100.0 / rs.PrevScore, 2)
            ELSE NULL
        END AS ScoreChangePercent,
        ROW_NUMBER() OVER (ORDER BY rs.Score DESC) AS ScoreRank,
        PERCENT_RANK() OVER (ORDER BY rs.Score) AS ScorePercentile,
        RANK() OVER (PARTITION BY rs.OwnerUserId ORDER BY rs.CreationDate) AS PostOrder,
        CASE 
            WHEN rs.PostRank = 1 THEN 'First Post'
            WHEN rs.PostRank = 10 THEN 'Tenth Post'
            WHEN rs.PostRank = 5 THEN 'Fifth Post'
            ELSE 'Other'
        END AS PostOrderType,
        DENSE_RANK() OVER (ORDER BY rs.AnswerCountActual DESC) AS AnswerRank,
        CASE 
            WHEN rs.Score > 100 AND rs.AnswerCountActual > 0 THEN 'High Score with Answers'
            WHEN rs.Score > 100 AND rs.AnswerCountActual = 0 THEN 'High Score No Answers'
            WHEN rs.Score <= 100 AND rs.AnswerCountActual > 0 THEN 'Low Score with Answers'
            ELSE 'Low Score No Answers'
        END AS ScoreAnswerCategory,
        COALESCE(rs.CumulativeScore, 0) + COALESCE(rs.AvgViews, 0) AS CompositeScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rs.Id AND c.Score > 5) AS HighRatedComments
    FROM RankedPosts rs
    JOIN Users u ON rs.OwnerUserId = u.Id
    JOIN UserStats us ON rs.OwnerUserId = us.Id
    WHERE rs.PostTypeId IN (1, 2)
      AND rs.Score IS NOT NULL
      AND rs.ViewCount IS NOT NULL
      AND rs.CreationDate > '2010-01-01 00:00:00'
),
FinalResult AS (
    SELECT 
        cj.PostId,
        cj.PostTitle,
        cj.OwnerUserId,
        cj.Score,
        cj.ViewCount,
        cj.PostTypeDesc,
        cj.TagCount,
        cj.EngagementCount,
        cj.ScoreCategory,
        cj.CumulativeScore,
        cj.AvgViews,
        cj.AnswerCountActual,
        cj.AuthorName,
        cj.AuthorReputation,
        cj.AuthorViews,
        cj.AuthorTotalPosts,
        cj.AuthorTotalScore,
        cj.AuthorAvgScore,
        cj.AuthorMaxScore,
        cj.AuthorHighScorePosts,
        cj.ScoreChangePercent,
        cj.ScoreRank,
        cj.ScorePercentile,
        cj.PostOrder,
        cj.PostOrderType,
        cj.AnswerRank,
        cj.ScoreAnswerCategory,
        cj.CompositeScore,
        cj.HighRatedComments,
        CASE 
            WHEN cj.ScorePercentile > 0.9 THEN 'Top 10%'
            WHEN cj.ScorePercentile > 0.75 THEN 'Top 25%'
            WHEN cj.ScorePercentile > 0.5 THEN 'Top 50%'
            ELSE 'Below Median'
        END AS PerformanceTier,
        CASE 
            WHEN cj.TagCount > 0 THEN 
                (SELECT STRING_AGG(ta.TagName, ', ') 
                 FROM Tags ta 
                 WHERE ta.TagName IN (
                     SELECT TRIM(tag) 
                     FROM UNNEST(string_to_array(trim(trim(cj.Tags, '<'), '>'), '>')) AS tag 
                     WHERE tag != '' AND tag IS NOT NULL
                 ) 
                 AND ta.Count > 50)
            ELSE NULL
        END AS PopularTags,
        (cj.Score * cj.ViewCount) / NULLIF(COALESCE(cj.AnswerCountActual, 0) + 1, 0) AS ScoreToViewRatio,
        ROW_NUMBER() OVER (ORDER BY cj.CompositeScore DESC) AS CompositeRank,
        RANK() OVER (ORDER BY cj.CompositeScore DESC) AS CompositeRankGroup,
        DENSE_RANK() OVER (ORDER BY cj.CompositeScore DESC) AS CompositeRankDense,
        COUNT(*) OVER () AS TotalPostsProcessed,
        CASE 
            WHEN cj.Score > (SELECT AVG(Score) FROM Posts) THEN 'Above Average'
            WHEN cj.Score < (SELECT AVG(Score) FROM Posts) THEN 'Below Average'
            ELSE 'Average'
        END AS ScoreComparison,
        CASE 
            WHEN cj.TagCount > 3 AND cj.AnswerCountActual > 2 THEN 'High Engagement Question'
            WHEN cj.TagCount = 0 AND cj.AnswerCountActual = 0 THEN 'Low Engagement Content'
            WHEN cj.TagCount BETWEEN 1 AND 3 AND cj.AnswerCountActual > 0 THEN 'Medium Engagement Question'
            ELSE 'Other'
        END AS EngagementLevel,
        CASE 
            WHEN cj.Score > 50 AND cj.CompositeScore > 1000 THEN 'Elite Performer'
            WHEN cj.Score > 25 AND cj.CompositeScore > 500 THEN 'Solid Performer'
            WHEN cj.Score <= 25 AND cj.CompositeScore <= 500 THEN 'Newbie'
            ELSE 'Mid Level'
        END AS PerformanceClassification,
        COALESCE(
            (SELECT COUNT(*) FROM PostHistory ph 
             WHERE ph.PostId = cj.PostId 
               AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13)
               AND ph.CreationDate > '2015-01-01 00:00:00'), 0
        ) AS EditActivity,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cj.PostId AND v.VoteTypeId IN (1, 2, 3)) AS VoteActivity,
        CASE 
            WHEN cj.Score >= 1000 THEN 'Viral Content'
            WHEN cj.Score >= 100 THEN 'Popular Content'
            WHEN cj.Score >= 50 THEN 'Medium Content'
            ELSE 'Low Content'
        END AS ContentPopularity,
        ROUND(
            (cj.CompositeScore - (SELECT AVG(CompositeScore) FROM ComplexJoin)) / 
            (SELECT STDDEV(CompositeScore) FROM ComplexJoin), 
            2
        ) AS ZScoreComposite,
        CASE 
            WHEN cj.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'Hot Topic'
            WHEN cj.ViewCount < (SELECT AVG(ViewCount) FROM Posts) THEN 'Cold Topic'
            ELSE 'Average Topic'
        END AS ViewStatus,
        (SELECT STRING_AGG(
            CONCAT(' ', ph.PostHistoryTypeId, ':', COALESCE(ph.Comment, 'No Comment')), 
            ', '
        ) FROM PostHistory ph WHERE ph.PostId = cj.PostId ORDER BY ph.CreationDate
        ) AS ActivityHistory,
        ROUND(
            cj.HighRatedComments * 1.0 / NULLIF(cj.AnswerCountActual, 0), 
            2
        ) AS CommentToAnswerRatio
    FROM ComplexJoin cj
    WHERE cj.Score >= -100
)
SELECT 
    PostId,
    PostTitle,
    OwnerUserId,
    Score,
    ViewCount,
    PostTypeDesc,
    TagCount,
    EngagementCount,
    ScoreCategory,
    CumulativeScore,
    AvgViews,
    AnswerCountActual,
    AuthorName,
    AuthorReputation,
    AuthorViews,
    AuthorTotalPosts,
    AuthorTotalScore,
    AuthorAvgScore,
    AuthorMaxScore,
    AuthorHighScorePosts,
    ScoreChangePercent,
    ScoreRank,
    ScorePercentile,
    PostOrder,
    PostOrderType,
    AnswerRank,
    ScoreAnswerCategory,
    CompositeScore,
    HighRatedComments,
    PerformanceTier,
    PopularTags,
    ScoreToViewRatio,
    CompositeRank,
    CompositeRankGroup,
    CompositeRankDense,
    TotalPostsProcessed,
    ScoreComparison,
    EngagementLevel,
    PerformanceClassification,
    EditActivity,
    VoteActivity,
    ContentPopularity,
    ZScoreComposite,
    ViewStatus,
    ActivityHistory,
    CommentToAnswerRatio
FROM FinalResult
WHERE Score > 5 
  AND (PopularTags IS NOT NULL OR Tags IS NOT NULL)
  AND CompositeScore > 100
ORDER BY CompositeScore DESC, Score DESC NULLS LAST
LIMIT 1000;