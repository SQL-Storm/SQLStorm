-- {"query": "29026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1826} 
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
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) as ViewRank,
        RANK() OVER (ORDER BY u.UpVotes DESC) as UpvoteRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
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
        p.ParentId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        NTILE(4) OVER (ORDER BY p.ViewCount DESC) as ViewQuartile,
        CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN STRING_TO_ARRAY(p.Tags, '><') ELSE ARRAY[]::varchar[] END as TagArray
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostAnalysis AS (
    SELECT 
        tp.PostId,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.OwnerUserId,
        tp.PostTypeId,
        tp.Tags,
        tp.AnswerCount,
        tp.CommentCount,
        tp.FavoriteCount,
        tp.ScoreRank,
        tp.ViewQuartile,
        CASE WHEN tp.TagArray IS NOT NULL AND ARRAY_LENGTH(tp.TagArray, 1) > 0 THEN ARRAY_LENGTH(tp.TagArray, 1) ELSE 0 END as TagCount,
        CASE WHEN tp.Score > 10 THEN 'High' 
             WHEN tp.Score > 5 THEN 'Medium' 
             ELSE 'Low' END as ScoreTier,
        COALESCE(tp.ViewCount, 0) + COALESCE(tp.CommentCount, 0) + COALESCE(tp.FavoriteCount, 0) as EngagementScore,
        DATEDIFF('DAY', tp.CreationDate, NOW()) as AgeInDays,
        LAG(tp.Score, 1) OVER (ORDER BY tp.CreationDate) as PrevScore,
        LEAD(tp.Score, 1) OVER (ORDER BY tp.CreationDate) as NextScore,
        AVG(tp.Score) OVER (ORDER BY tp.CreationDate ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING) as MovingAvgScore
    FROM TopPosts tp
    WHERE tp.ScoreRank <= 100
),
UserActivity AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.AvgPostScore,
        us.LastPostDate,
        us.ReputationRank,
        us.ViewRank,
        us.UpvoteRank,
        CASE 
            WHEN us.PostCount > 100 THEN 'Veteran'
            WHEN us.PostCount > 50 THEN 'Experienced'
            WHEN us.PostCount > 10 THEN 'Active'
            ELSE 'Newbie'
        END as UserTier,
        CASE 
            WHEN us.Reputation > 100000 THEN 'Elite'
            WHEN us.Reputation > 50000 THEN 'Senior'
            WHEN us.Reputation > 10000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as RepTier,
        (us.Views * 0.1 + us.UpVotes * 0.5 + us.DownVotes * -0.2 + us.BadgeCount * 1.5) as ActivityWeight,
        DENSE_RANK() OVER (ORDER BY (us.Views * 0.1 + us.UpVotes * 0.5 + us.DownVotes * -0.2 + us.BadgeCount * 1.5) DESC) as ActivityRank
    FROM UserStats us
),
FinalAggregation AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.AvgPostScore,
        ua.LastPostDate,
        ua.ReputationRank,
        ua.ViewRank,
        ua.UpvoteRank,
        ua.UserTier,
        ua.RepTier,
        ua.ActivityWeight,
        ua.ActivityRank,
        COUNT(pa.PostId) as TopPostCount,
        SUM(pa.Score) as TotalScore,
        AVG(pa.EngagementScore) as AvgEngagement,
        MAX(pa.AgeInDays) as MaxAge,
        MIN(pa.Score) as MinScore,
        MAX(pa.Score) as MaxScore,
        (CASE WHEN COUNT(pa.PostId) > 0 THEN AVG(pa.MovingAvgScore) ELSE 0 END) as AvgMovingAverage
    FROM UserActivity ua
    LEFT JOIN PostAnalysis pa ON ua.UserId = pa.OwnerUserId
    WHERE ua.ReputationRank <= 500
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, ua.CommentCount, ua.BadgeCount, 
             ua.AvgPostScore, ua.LastPostDate, ua.ReputationRank, ua.ViewRank, ua.UpvoteRank,
             ua.UserTier, ua.RepTier, ua.ActivityWeight, ua.ActivityRank
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.AvgPostScore,
    fa.LastPostDate,
    fa.ReputationRank,
    fa.ViewRank,
    fa.UpvoteRank,
    fa.UserTier,
    fa.RepTier,
    fa.ActivityWeight,
    fa.ActivityRank,
    fa.TopPostCount,
    fa.TotalScore,
    fa.AvgEngagement,
    fa.MaxAge,
    fa.MinScore,
    fa.MaxScore,
    fa.AvgMovingAverage,
    CASE 
        WHEN fa.ActivityWeight > 50 AND fa.Reputation > 5000 THEN 'Highly Active'
        WHEN fa.ActivityWeight > 30 AND fa.Reputation > 2000 THEN 'Active'
        WHEN fa.ActivityWeight > 10 AND fa.Reputation > 1000 THEN 'Moderate'
        ELSE 'Low'
    END as EngagementLevel,
    (CASE 
        WHEN fa.Reputation > 100000 THEN 'Legendary'
        WHEN fa.Reputation > 50000 THEN 'Master'
        WHEN fa.Reputation > 10000 THEN 'Expert'
        WHEN fa.Reputation > 5000 THEN 'Advanced'
        WHEN fa.Reputation > 1000 THEN 'Novice'
        ELSE 'Beginner'
    END) as ReputationLevel,
    ROW_NUMBER() OVER (ORDER BY fa.ActivityWeight DESC, fa.Reputation DESC) as OverallRank,
    CONCAT('User-', fa.UserId, '-Rep-', fa.Reputation, '-Tier-', fa.UserTier) as UniqueIdentifier,
    (CASE 
        WHEN fa.TopPostCount >= 10 THEN 'Multiple Posts'
        WHEN fa.TopPostCount = 1 THEN 'Single Post'
        ELSE 'No Posts'
    END) as PostingFrequency,
    ROUND((fa.TotalScore * 1.0 / NULLIF(fa.TopPostCount, 0)), 2) as ScorePerPost,
    (CASE 
        WHEN fa.AvgMovingAverage > 10 THEN 'Growing'
        WHEN fa.AvgMovingAverage > 5 THEN 'Stable'
        WHEN fa.AvgMovingAverage > 0 THEN 'Declining'
        ELSE 'Static'
    END) as Trend
FROM FinalAggregation fa
WHERE fa.Reputation > 1000
    AND fa.PostCount > 0
    AND fa.ActivityWeight > 0
    AND fa.TopPostCount >= 0
ORDER BY fa.ActivityWeight DESC, fa.Reputation DESC, fa.AvgEngagement DESC
LIMIT 1000;