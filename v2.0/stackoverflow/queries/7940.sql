-- {"query": "7940.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1411}
WITH RankedPosts AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        COALESCE(p.Tags, '') as CleanTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(p.Score) as TotalScore,
        AVG(p.ViewCount) as AvgViews,
        MAX(p.CreationDate) as LastActivity,
        STRING_AGG(DISTINCT p.Tags, '; ') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Experienced'
            ELSE 'Beginner'
        END as UserLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostComplexity AS (
    SELECT 
        rp.PostId,
        rp.Score,
        rp.ViewCount,
        rp.ScoreCategory,
        rp.OwnerUserId,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        CASE 
            WHEN rp.AnswerCount > 10 THEN 'Highly Active'
            WHEN rp.AnswerCount > 5 THEN 'Medium Active'
            ELSE 'Low Activity'
        END as ActivityLevel,
        CASE 
            WHEN rp.Score > 100 AND rp.AnswerCount > 5 THEN 'High Engagement'
            WHEN rp.Score > 50 THEN 'Moderate Engagement'
            ELSE 'Low Engagement'
        END as EngagementLevel,
        COALESCE(rp.prev_score, 0) as PrevScore,
        (rp.Score - COALESCE(rp.prev_score, 0)) as ScoreChange,
        CHAR_LENGTH(rp.Title) as TitleLength,
        (CHAR_LENGTH(rp.CleanTags) - CHAR_LENGTH(REPLACE(rp.CleanTags, '>', ''))) as TagCount,
        rp.CleanTags,
        rp.rn
    FROM RankedPosts rp
    WHERE rp.rn = 1
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            ELSE 'Niche'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName <> ''
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.TotalScore,
    uas.AvgViews,
    uas.LastActivity,
    uas.UserLevel,
    pc.PostId,
    pc.Score,
    pc.ViewCount,
    pc.ScoreCategory,
    pc.AnswerCount,
    pc.CommentCount,
    pc.FavoriteCount,
    pc.ActivityLevel,
    pc.EngagementLevel,
    pc.ScoreChange,
    pc.TitleLength,
    pc.TagCount,
    ts.TagName,
    ts.TagCount as TagFrequency,
    ts.PopularityLevel,
    CASE 
        WHEN uas.Reputation > 10000 THEN 'Elite'
        WHEN uas.Reputation > 5000 THEN 'Advanced'
        WHEN uas.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as RepLevel,
    CASE 
        WHEN uas.TotalPosts > 50 AND uas.TotalScore > 1000 THEN 'Active Contributor'
        WHEN uas.TotalPosts > 25 THEN 'Regular Poster'
        ELSE 'Occasional Poster'
    END as ContributionLevel,
    DENSE_RANK() OVER (ORDER BY uas.TotalScore DESC) as ScoreRank,
    DENSE_RANK() OVER (ORDER BY pc.Score DESC) as PostScoreRank,
    PERCENT_RANK() OVER (ORDER BY uas.Reputation) as RepPercentile,
    NTILE(4) OVER (ORDER BY uas.AvgViews) as ViewQuartile,
    COALESCE(ts.RankByCount, 0) as TagRanking,
    CASE 
        WHEN pc.ScoreChange > 20 THEN 'High Growth'
        WHEN pc.ScoreChange > 5 THEN 'Moderate Growth'
        WHEN pc.ScoreChange < -10 THEN 'Declining'
        ELSE 'Stable'
    END as Trend
FROM UserActivityStats uas
INNER JOIN PostComplexity pc ON uas.UserId = pc.OwnerUserId
LEFT JOIN TagStats ts ON EXISTS (
    SELECT 1 
    FROM (SELECT UNNEST(STRING_TO_ARRAY(pc.CleanTags, '><')) AS tag) s
    WHERE s.tag = ts.TagName OR ts.TagName = 'c#' OR ts.TagName = 'sql'
)
WHERE 
    (pc.Score >= 10 OR pc.ViewCount >= 100 OR pc.FavoriteCount >= 5)
    AND uas.TotalPosts BETWEEN 1 AND 1000
    AND uas.Reputation >= 1
    AND (pc.ActivityLevel IN ('Highly Active', 'Medium Active') OR pc.Score >= 50)
    AND CASE 
        WHEN pc.AnswerCount = 0 THEN 1
        ELSE CASE WHEN pc.Score > 0 THEN 1 ELSE 0 END
    END = 1
    AND (ts.PopularityLevel IN ('Popular', 'Moderate') OR ts.TagName IS NULL)
GROUP BY
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.TotalScore,
    uas.AvgViews,
    uas.LastActivity,
    uas.UserLevel,
    pc.PostId,
    pc.Score,
    pc.ViewCount,
    pc.ScoreCategory,
    pc.AnswerCount,
    pc.CommentCount,
    pc.FavoriteCount,
    pc.ActivityLevel,
    pc.EngagementLevel,
    pc.ScoreChange,
    pc.TitleLength,
    pc.TagCount,
    pc.CleanTags,
    ts.TagName,
    ts.TagCount,
    ts.PopularityLevel,
    ts.RankByCount
ORDER BY 
    uas.TotalScore DESC,
    uas.Reputation DESC,
    pc.Score DESC,
    ts.TagCount DESC
LIMIT 1000;