-- {"query": "7459.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1958} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as avg_score_5day,
        NTILE(10) OVER (ORDER BY p.Score DESC) as score_decile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2018-01-01' 
      AND p.CreationDate < '2023-01-01'
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.ViewCount as UserViews,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) FILTER (WHERE p.Tags IS NOT NULL), '|') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2018-01-01'
    GROUP BY u.Id, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.AccountId
),
ComplexTagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Emerging'
            ELSE 'Niche'
        END as TagCategory,
        LEAD(t.Count) OVER (ORDER BY t.Count DESC) as NextPopularCount,
        LAG(t.Count) OVER (ORDER BY t.Count ASC) as PrevPopularCount,
        PERCENT_RANK() OVER (ORDER BY t.Count) as TagPercentile,
        ROUND((t.Count * 1.0 / MAX(t.Count) OVER ()) * 100, 2) as TagPercentage
    FROM Tags t
    WHERE t.Count > 10
),
AnswerQuality AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        a.LastEditDate,
        q.Title as QuestionTitle,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount as QuestionAnswerCount,
        CASE 
            WHEN a.Score > 10 THEN 'High'
            WHEN a.Score > 5 THEN 'Medium' 
            WHEN a.Score > 0 THEN 'Low'
            ELSE 'None'
        END as AnswerQualityLevel,
        CASE 
            WHEN a.OwnerUserId IS NOT NULL THEN 1
            ELSE 0
        END as IsOwnerProvided,
        NULLIF(a.Score - LAG(a.Score) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate), 0) as ScoreDifference,
        EXTRACT(EPOCH FROM (a.CreationDate - LAG(a.CreationDate) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate))) / 3600 as HoursSinceLastAnswer
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
      AND q.PostTypeId = 1
      AND a.CreationDate >= '2018-01-01'
      AND a.CreationDate < '2023-01-01'
),
FinalAnalysis AS (
    SELECT 
        rp.Id as PostId,
        rp.PostTypeId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.CreationDate,
        rp.OwnerUserId,
        us.UserViews,
        us.Reputation,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        rp.prev_score,
        rp.next_score,
        rp.avg_score_5day,
        rp.score_decile,
        ct.TagCategory,
        ct.NextPopularCount,
        ct.TagPercentage,
        COALESCE(aq.AnswerQualityLevel, 'No Answers') as AnswerQuality,
        COALESCE(aq.ScoreDifference, 0) as ScoreDifferenceFromPrev,
        COALESCE(aq.HoursSinceLastAnswer, 0) as HoursSinceLastAnswer,
        CASE 
            WHEN rp.Score > 0 AND rp.ViewCount > 0 THEN ROUND((rp.Score * 100.0 / rp.ViewCount), 2)
            ELSE 0 
        END as ScorePerView,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'Below Average'
            ELSE 'Very Low'
        END as PerformanceLevel
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN ComplexTagAnalysis ct ON rp.Tags IS NOT NULL AND POSITION('>' || ct.TagName || '<' IN rp.Tags) > 0
    LEFT JOIN AnswerQuality aq ON rp.Id = aq.ParentId
    WHERE rp.rn = 1
)
SELECT 
    PostId,
    PostTypeId,
    Title,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    CreationDate,
    OwnerUserId,
    UserViews,
    Reputation,
    TotalPosts,
    Questions,
    Answers,
    prev_score,
    next_score,
    avg_score_5day,
    score_decile,
    TagCategory,
    NextPopularCount,
    TagPercentage,
    AnswerQuality,
    ScoreDifferenceFromPrev,
    HoursSinceLastAnswer,
    ScorePerView,
    PerformanceLevel,
    CASE 
        WHEN SUM(ScorePerView) > 10 THEN 'High Engagement'
        WHEN SUM(ScorePerView) > 5 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END as EngagementCategory,
    ROW_NUMBER() OVER (ORDER BY ScorePerView DESC) as EngagementRank,
    PERCENT_RANK() OVER (ORDER BY ScorePerView) as EngagementPercentile,
    NTILE(5) OVER (ORDER BY ScorePerView) as EngagementQuintile,
    CAST(COUNT(*) OVER() AS FLOAT) as TotalResults,
    CAST(SUM(ScorePerView) OVER() AS FLOAT) as TotalScorePerView,
    LAG(ScorePerView, 1) OVER (ORDER BY ScorePerView DESC) as PrevScorePerView,
    LEAD(ScorePerView, 1) OVER (ORDER BY ScorePerView DESC) as NextScorePerView,
    COALESCE(COUNT(*) FILTER (WHERE PerformanceLevel = 'Above Average'), 0) as AboveAverageCount,
    COALESCE(COUNT(*) FILTER (WHERE PerformanceLevel = 'Below Average'), 0) as BelowAverageCount,
    COALESCE(COUNT(*) FILTER (WHERE PerformanceLevel = 'Very Low'), 0) as VeryLowCount,
    STRING_AGG(Title, '; ') WITHIN GROUP (ORDER BY ScorePerView DESC) as TopTitles,
    NULLIF(COUNT(*) FILTER (WHERE AnswerQuality = 'High'), 0) as HighQualityAnswers,
    NULLIF(COUNT(*) FILTER (WHERE AnswerQuality = 'Medium'), 0) as MediumQualityAnswers,
    NULLIF(COUNT(*) FILTER (WHERE AnswerQuality = 'Low'), 0) as LowQualityAnswers
FROM FinalAnalysis
WHERE Score > 0 AND ViewCount > 0
GROUP BY 
    PostId, PostTypeId, Title, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount,
    CreationDate, OwnerUserId, UserViews, Reputation, TotalPosts, Questions, Answers,
    prev_score, next_score, avg_score_5day, score_decile, TagCategory, NextPopularCount,
    TagPercentage, AnswerQuality, ScoreDifferenceFromPrev, HoursSinceLastAnswer, ScorePerView, PerformanceLevel
HAVING COUNT(*) >= 1
ORDER BY ScorePerView DESC, Reputation DESC
LIMIT 10000;