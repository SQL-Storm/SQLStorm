-- {"query": "7533.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1427} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 5000 THEN 'Advanced'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.UserDisplayName,
        ph.Comment,
        CASE 
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Moderation'
            WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 'Editing'
            WHEN ph.PostHistoryTypeId IN (14, 15, 19, 20) THEN 'Moderation'
            ELSE 'Other'
        END as ActivityType,
        COALESCE(ph.Text, '') as ActivityDetails
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2022-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly,
        p.Id as PostId,
        p.Title,
        p.Score,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.Tags LIKE '%' || t.TagName || '%') as TagUsageCount
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE t.Count > 100
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.ReputationLevel,
    us.PostCount,
    us.CommentCount,
    us.BadgeCount,
    us.TotalScore,
    us.AvgScore,
    us.TotalViews,
    us.ReputationRank,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ') 
     FROM Posts p 
     JOIN unnest(string_to_array(p.Tags, '>')) AS tag ON TRUE
     JOIN Tags t ON t.TagName = tag
     WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1
     LIMIT 10) as UserTags,
    (SELECT COUNT(*) 
     FROM PostActivity pa 
     WHERE pa.UserId = us.UserId AND pa.ActivityType = 'Editing') as EditCount,
    (SELECT COUNT(*) 
     FROM PostActivity pa 
     WHERE pa.UserId = us.UserId AND pa.ActivityType = 'Moderation') as ModerationCount,
    CASE 
        WHEN us.PostCount > 0 THEN (us.TotalScore * 100.0 / us.PostCount)
        ELSE 0 
    END as ScorePerPost,
    CASE 
        WHEN us.AvgScore > 0 THEN 'High Scoring'
        WHEN us.AvgScore > 0 THEN 'Moderate Scoring'
        ELSE 'Low Scoring' 
    END as PerformanceCategory,
    'Ranking: ' || us.ReputationRank || ' of ' || (SELECT COUNT(*) FROM Users) as RankInfo,
    (SELECT JSON_AGG(JSON_BUILD_OBJECT(
        'PostId', tp.PostId,
        'Title', tp.Title,
        'Score', tp.Score,
        'Rank', tp.ScoreRank
    )) 
     FROM TopPosts tp 
     WHERE tp.OwnerUserId = us.UserId 
     AND tp.ScoreRank <= 3) as Top3Posts,
    (SELECT STRING_AGG(ta.TagName || ' (' || ta.Count || ')', ', ')
     FROM TagAnalysis ta 
     WHERE ta.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = us.UserId AND PostTypeId = 1)
     AND ta.Count > 100) as PopularTags,
    NULL as NullCheckValue
FROM UserStats us
LEFT JOIN (
    SELECT DISTINCT UserId 
    FROM PostHistory 
    WHERE CreationDate >= '2022-01-01'
) ph ON us.UserId = ph.UserId
WHERE us.PostCount > 0 
AND us.Reputation >= 100
AND (
    us.PostCount >= (SELECT AVG(PostCount) FROM UserStats) 
    OR us.BadgeCount >= (SELECT AVG(BadgeCount) FROM UserStats)
)
AND EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.OwnerUserId = us.UserId 
    AND p.CreationDate >= '2022-01-01'
)
UNION ALL
SELECT 
    -1 as UserId,
    'Summary' as DisplayName,
    SUM(us.Reputation) as Reputation,
    'Summary' as ReputationLevel,
    SUM(us.PostCount) as PostCount,
    SUM(us.CommentCount) as CommentCount,
    SUM(us.BadgeCount) as BadgeCount,
    SUM(us.TotalScore) as TotalScore,
    AVG(us.AvgScore) as AvgScore,
    SUM(us.TotalViews) as TotalViews,
    0 as ReputationRank,
    'Group Statistics' as RankInfo,
    'Statistics' as NullCheckValue
FROM UserStats us
WHERE us.Reputation > 1000;