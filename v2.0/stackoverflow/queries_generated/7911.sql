-- {"query": "7911.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2065} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LatestPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 5000 THEN 'Veteran'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            ELSE 'Novice'
        END as UserTier,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) as RecentRank,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PrevScore,
        NTILE(10) OVER (ORDER BY p.Score) as ScoreDecile,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 10 THEN 'Low Voted'
            ELSE 'Unvoted'
        END as VoteCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 500 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Notable'
            ELSE 'Obscure'
        END as PopularityLevel
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
PostAnalyses AS (
    SELECT 
        tp.Id,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.OwnerUserId,
        tp.OwnerName,
        tp.Tags,
        tp.ScoreRank,
        tp.RecentRank,
        tp.PrevScore,
        tp.ScoreDecile,
        tp.VoteCategory,
        tp.PopularityLevel,
        CASE 
            WHEN tp.Score < 0 THEN 'Negative'
            WHEN tp.Score = 0 THEN 'Neutral'
            WHEN tp.Score BETWEEN 1 AND 10 THEN 'Low'
            WHEN tp.Score BETWEEN 11 AND 50 THEN 'Medium'
            WHEN tp.Score BETWEEN 51 AND 100 THEN 'High'
            ELSE 'Extreme'
        END as ScoreLevel,
        RANK() OVER (ORDER BY tp.CreationDate) as ChronologicalRank,
        DATEDIFF('day', tp.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        COALESCE(tp.PrevScore, 0) - tp.Score as ScoreChangeFromPrevious,
        ROUND(tp.Score * 1.0 / COALESCE(NULLIF(tp.ViewCount, 0), 1), 4) as ScorePerViewRatio,
        CASE 
            WHEN tp.ViewCount = 0 THEN 'No Views'
            WHEN tp.ViewCount BETWEEN 1 AND 10 THEN 'Few Views'
            WHEN tp.ViewCount BETWEEN 11 AND 100 THEN 'Some Views'
            WHEN tp.ViewCount BETWEEN 101 AND 1000 THEN 'Many Views'
            ELSE 'Extremely Popular'
        END as ViewCategory,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tp.Id) as CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.Id AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.Id AND v.VoteTypeId = 3) as Downvotes
    FROM TopPosts tp
),
ComplexUserAnalysis AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.DisplayName,
        us.Views,
        us.UpVotes,
        us.DownVotes,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.LatestPostDate,
        us.ReputationRank,
        us.UserTier,
        us.TotalScore,
        us.AvgPostScore,
        us.AllTags,
        ROW_NUMBER() OVER (ORDER BY us.TotalScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY us.Reputation DESC) as ReputationRank2,
        CASE 
            WHEN us.PostCount > 100 THEN 'Heavy Poster'
            WHEN us.PostCount > 50 THEN 'Moderate Poster'
            WHEN us.PostCount > 10 THEN 'Light Poster'
            ELSE 'Casual Poster'
        END as PostingFrequency,
        CASE 
            WHEN us.BadgeCount > 10 THEN 'Badge Collector'
            WHEN us.BadgeCount > 5 THEN 'Moderate Collector'
            WHEN us.BadgeCount > 1 THEN 'Occasional Collector'
            ELSE 'No Badges'
        END as BadgeStatus,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.Score > 100) as HighScorePosts,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.ViewCount > 1000) as ViralPosts,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.CreationDate >= DATEADD('month', -6, CURRENT_TIMESTAMP)) as RecentPosts
    FROM UserStats us
)
SELECT 
    pca.UserId,
    pca.Reputation,
    pca.DisplayName,
    pca.Views,
    pca.UpVotes,
    pca.DownVotes,
    pca.PostCount,
    pca.CommentCount,
    pca.BadgeCount,
    pca.LatestPostDate,
    pca.ReputationRank,
    pca.UserTier,
    pca.TotalScore,
    pca.AvgPostScore,
    pca.AllTags,
    pca.ScoreRank,
    pca.ReputationRank2,
    pca.PostingFrequency,
    pca.BadgeStatus,
    pca.HighScorePosts,
    pca.ViralPosts,
    pca.RecentPosts,
    CASE 
        WHEN pca.TotalScore > 5000 THEN 'Legendary'
        WHEN pca.TotalScore > 1000 THEN 'Master'
        WHEN pca.TotalScore > 500 THEN 'Expert'
        WHEN pca.TotalScore > 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as AchievementLevel,
    ROUND(pca.AvgPostScore, 2) as AvgPostScore,
    COALESCE(NULLIF(pca.TotalScore, 0) * 1.0 / NULLIF(pca.PostCount, 0), 0) as ScorePerPost,
    ROUND(pca.Reputation * 1.0 / NULLIF(pca.TotalScore, 0), 4) as ReputationEfficiency,
    (SELECT AVG(UpVotes) FROM ComplexUserAnalysis) as AvgUserUpVotes,
    (SELECT AVG(BadgeCount) FROM ComplexUserAnalysis) as AvgUserBadges,
    CASE 
        WHEN pca.HighScorePosts * 1.0 / NULLIF(pca.PostCount, 0) > 0.2 THEN 'High Quality Focus'
        WHEN pca.HighScorePosts * 1.0 / NULLIF(pca.PostCount, 0) > 0.1 THEN 'Quality Aware'
        ELSE 'Standard Poster'
    END as QualityFocus,
    (SELECT STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') 
     FROM Posts p 
     WHERE p.OwnerUserId = pca.UserId 
     AND p.PostTypeId = 1 
     AND p.Tags IS NOT NULL 
     AND p.Tags <> '') as UserTagFocus,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = pca.UserId AND p.Tags LIKE '%<java>%') as JavaPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = pca.UserId AND p.Tags LIKE '%<python>%') as PythonPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = pca.UserId AND p.Tags LIKE '%<javascript>%') as JavaScriptPosts
FROM ComplexUserAnalysis pca
WHERE pca.PostCount > 1
  AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = pca.UserId AND p.Score > 100)
  AND pca.Reputation > 100
  AND (
    pca.BadgeCount > 5 
    OR pca.HighScorePosts > 10 
    OR pca.ViralPosts > 5
  )
  AND pca.UserId IN (
    SELECT u.Id 
    FROM Users u 
    WHERE u.Id IN (
      SELECT DISTINCT p.OwnerUserId 
      FROM Posts p 
      WHERE p.Score > 100 AND p.CreationDate >= DATEADD('month', -12, CURRENT_TIMESTAMP)
    )
  )
ORDER BY pca.TotalScore DESC, pca.Reputation DESC
LIMIT 100;