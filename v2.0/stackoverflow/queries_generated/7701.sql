-- {"query": "7701.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1462} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationLevel,
        ROUND(AVG(p.Score), 2) as AvgPostScore,
        ROUND(AVG(p.ViewCount), 2) as AvgViewCount,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > '2010-01-01' 
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        PERCENT_RANK() OVER (ORDER BY p.Score DESC) as ScorePercentile,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore
    FROM Posts p
    WHERE p.PostTypeId = 1 
    AND p.CreationDate > '2015-01-01'
),
PostAnalysis AS (
    SELECT 
        tp.PostId,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.OwnerUserId,
        tp.Tags,
        tp.ScoreRank,
        tp.GlobalScoreRank,
        tp.ViewRank,
        tp.ScorePercentile,
        tp.PrevScore,
        CASE 
            WHEN tp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN tp.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Average'
            ELSE 'Average'
        END as ScoreCategory,
        DATEDIFF('days', tp.CreationDate, CURRENT_TIMESTAMP) as DaysSincePost,
        CASE 
            WHEN tp.ViewCount > 5000 THEN 'Viral'
            WHEN tp.ViewCount > 1000 THEN 'Popular'
            WHEN tp.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Ordinary'
        END as PopularityCategory,
        COALESCE(tp.PrevScore, 0) as PreviousScore,
        (tp.Score - COALESCE(tp.PrevScore, 0)) as ScoreChange,
        CASE 
            WHEN tp.PrevScore IS NULL THEN 'New Post'
            WHEN tp.Score > tp.PrevScore THEN 'Gained'
            WHEN tp.Score < tp.PrevScore THEN 'Lost'
            ELSE 'Stable'
        END as ScoreStatus,
        COALESCE(SUBSTRING(tp.Tags, 2, LENGTH(tp.Tags)-2), 'No Tags') as CleanTags
    FROM TopPosts tp
    WHERE tp.ScoreRank <= 5
),
TagAnalysis AS (
    SELECT 
        ta.CleanTags,
        COUNT(*) as TagFrequency,
        COUNT(DISTINCT ta.OwnerUserId) as UserCount,
        AVG(ta.Score) as AvgScore,
        AVG(ta.ViewCount) as AvgViews,
        MAX(ta.Score) as MaxScore,
        MIN(ta.Score) as MinScore
    FROM PostAnalysis ta
    WHERE ta.CleanTags IS NOT NULL AND ta.CleanTags != ''
    GROUP BY ta.CleanTags
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.PostCount,
    us.CommentCount,
    us.BadgeCount,
    us.ReputationLevel,
    us.AvgPostScore,
    us.AvgViewCount,
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.GlobalScoreRank,
    pa.ScorePercentile,
    pa.ScoreCategory,
    pa.PopularityCategory,
    pa.ScoreStatus,
    ta.TagFrequency,
    ta.UserCount,
    ta.AvgScore as TagAvgScore,
    ta.AvgViews as TagAvgViews,
    CASE 
        WHEN us.PostCount > 0 THEN (CAST(us.BadgeCount AS FLOAT) / us.PostCount)
        ELSE 0
    END as BadgePerPostRatio,
    CASE 
        WHEN us.Reputation > 0 THEN (CAST(us.UpVotes AS FLOAT) / us.Reputation)
        ELSE 0
    END as UpVoteRatio,
    CASE
        WHEN pa.DaysSincePost > 0 THEN (CAST(pa.Score AS FLOAT) / pa.DaysSincePost)
        ELSE 0
    END as ScorePerDay,
    CASE
        WHEN us.Views > 0 THEN (CAST(us.UpVotes AS FLOAT) / us.Views)
        ELSE 0
    END as UpVotesPerView,
    STRING_AGG(pa.CleanTags, '; ') as AllPostTags,
    COUNT(*) OVER () as TotalRecords,
    MAX(pa.Score) OVER (PARTITION BY us.UserId) as MaxScoreForUser,
    MIN(pa.Score) OVER (PARTITION BY us.UserId) as MinScoreForUser,
    AVG(pa.ViewCount) OVER (PARTITION BY us.UserId) as AvgViewCountForUser,
    LAG(pa.Score, 1) OVER (PARTITION BY us.UserId ORDER BY pa.CreationDate) as PrevScoreForUser,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, pa.Score DESC) as OverallRank,
    NTILE(10) OVER (ORDER BY pa.Score DESC) as ScoreDecile,
    RANK() OVER (ORDER BY pa.ViewCount DESC) as ViewRankOverall
FROM UserStats us
INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
LEFT JOIN TagAnalysis ta ON pa.CleanTags = ta.CleanTags
WHERE us.PostCount > 0 
AND pa.Score > 0
AND pa.ScoreCategory IN ('Above Average', 'Viral')
AND us.Reputation > 1000
ORDER BY us.Reputation DESC, pa.Score DESC
LIMIT 1000;