-- {"query": "7678.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1559} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 1, 30), ', ') as TagHistory,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium'
            ELSE 'Low'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        TotalScore,
        TagHistory,
        ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RankByReputation,
        NTILE(4) OVER (ORDER BY PostCount DESC) as PostQuartile
    FROM UserActivityStats
),
UserEngagement AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.LastPostDate,
        tu.TotalScore,
        tu.TagHistory,
        tu.ActivityLevel,
        tu.RankByScore,
        tu.RankByReputation,
        tu.PostQuartile,
        CASE 
            WHEN tu.PostCount > 0 AND tu.CommentCount > 0 THEN (tu.CommentCount * 100.0 / tu.PostCount)
            ELSE 0 
        END as CommentToPostRatio,
        CASE 
            WHEN tu.BadgeCount > 0 THEN (tu.BadgeCount * 100.0 / NULLIF(tu.PostCount, 0))
            ELSE 0 
        END as BadgeToPostRatio,
        LAG(tu.Reputation, 1) OVER (ORDER BY tu.Reputation DESC) as PrevReputation,
        LEAD(tu.Reputation, 1) OVER (ORDER BY tu.Reputation DESC) as NextReputation,
        AVG(tu.Reputation) OVER (ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAvgReputation
    FROM TopUsers tu
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAvg'
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'BelowAvg'
            ELSE 'Low'
        END as ScoreCategory,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)), 
            0
        ) as VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankPerType
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= '2020-01-01'
),
CombinedStats AS (
    SELECT 
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.PostCount,
        ue.CommentCount,
        ue.BadgeCount,
        ue.LastPostDate,
        ue.TotalScore,
        ue.TagHistory,
        ue.ActivityLevel,
        ue.RankByScore,
        ue.RankByReputation,
        ue.PostQuartile,
        ue.CommentToPostRatio,
        ue.BadgeToPostRatio,
        CASE 
            WHEN ue.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 1
            ELSE 0 
        END as AboveAvgReputation,
        CASE 
            WHEN ue.PostCount > (SELECT AVG(PostCount) FROM UserActivityStats) THEN 1
            ELSE 0 
        END as AboveAvgPosts,
        CASE 
            WHEN ue.TotalScore > (SELECT AVG(TotalScore) FROM UserActivityStats) THEN 1
            ELSE 0 
        END as AboveAvgScores,
        pa.ScoreCategory,
        pa.DaysSinceCreation,
        pa.VoteCount,
        pa.ScoreRankPerType
    FROM UserEngagement ue
    LEFT JOIN PostAnalysis pa ON ue.UserId = pa.OwnerUserId
    WHERE ue.RankByScore <= 100 OR pa.ScoreRankPerType <= 50
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Reputation,
    cs.PostCount,
    cs.CommentCount,
    cs.BadgeCount,
    cs.LastPostDate,
    cs.TotalScore,
    cs.TagHistory,
    cs.ActivityLevel,
    cs.RankByScore,
    cs.RankByReputation,
    cs.PostQuartile,
    cs.CommentToPostRatio,
    cs.BadgeToPostRatio,
    cs.AboveAvgReputation,
    cs.AboveAvgPosts,
    cs.AboveAvgScores,
    cs.ScoreCategory,
    cs.DaysSinceCreation,
    cs.VoteCount,
    cs.ScoreRankPerType,
    CASE 
        WHEN cs.Reputation > 10000 AND cs.PostCount > 100 THEN 'Elite'
        WHEN cs.Reputation > 5000 AND cs.PostCount > 50 THEN 'Veteran'
        WHEN cs.Reputation > 1000 AND cs.PostCount > 10 THEN 'Experienced'
        ELSE 'Regular'
    END as UserTier,
    CASE 
        WHEN cs.ScoreCategory = 'AboveAvg' THEN 'High Value'
        WHEN cs.ScoreCategory = 'BelowAvg' THEN 'Medium Value'
        ELSE 'Low Value'
    END as PostValue,
    CONCAT('Rank:', cs.RankByScore, '|Type:', cs.ScoreCategory) as CombinedMetric,
    ABS(cs.Reputation - cs.PrevReputation) as ReputationChange,
    ABS(cs.Reputation - cs.NextReputation) as NextReputationDiff,
    cs.MovingAvgReputation
FROM CombinedStats cs
WHERE cs.UserId IN (
    SELECT UserId FROM CombinedStats 
    WHERE PostCount > 0
    INTERSECT
    SELECT UserId FROM CombinedStats 
    WHERE Reputation > 1000
    EXCEPT
    SELECT UserId FROM CombinedStats 
    WHERE ActivityLevel = 'Low'
)
ORDER BY cs.TotalScore DESC, cs.Reputation DESC
LIMIT 1000;