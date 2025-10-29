-- {"query": "7299.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1954} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgScore,
        STRING_AGG(DISTINCT t.TagName, ', ') as TaggedWith
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p2 ON p.Id = p2.ParentId
    LEFT JOIN Tags t ON p.Id = p2.ParentId
    WHERE u.Id > 0
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
        p.ParentId,
        p.PostTypeId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.Score DESC) as OverallRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(10) OVER (ORDER BY p.Score) as ScoreQuintile,
        LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) as NextScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(c.Id) as CommentCount,
        COUNT(ph.Id) as HistoryCount,
        COUNT(v.Id) as VoteCount,
        MAX(c.CreationDate) as LastComment,
        MAX(ph.CreationDate) as LastHistory,
        MAX(v.CreationDate) as LastVote,
        CASE 
            WHEN COUNT(c.Id) > 0 AND COUNT(ph.Id) > 0 AND COUNT(v.Id) > 0 THEN 'Active'
            WHEN COUNT(c.Id) = 0 AND COUNT(ph.Id) = 0 AND COUNT(v.Id) = 0 THEN 'Inactive'
            ELSE 'Moderate'
        END as ActivityLevel,
        (COUNT(c.Id) + COUNT(ph.Id) + COUNT(v.Id)) as TotalActivity
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.CreationDate,
        p.Tags,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as HasAcceptedAnswer,
        CASE WHEN p.CommentCount > 0 THEN 1 ELSE 0 END as HasComments,
        CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 1 ELSE 0 END as IsDuplicate,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'None'
        END as ScoreCategory,
        ABS(p.Score - (SELECT AVG(Score) FROM Posts)) as ScoreDeviation,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as DaysSinceCreation,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2020-01-01'
),
ComplexUserMetrics AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.DisplayName,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.BadgeCount,
        us.AvgScore,
        us.TaggedWith,
        ua.CommentCount,
        ua.HistoryCount,
        ua.VoteCount,
        ua.ActivityLevel,
        ua.TotalActivity,
        CASE 
            WHEN us.Reputation > 10000 AND us.PostCount > 100 THEN 'Elite'
            WHEN us.Reputation > 5000 AND us.PostCount > 50 THEN 'Veteran'
            WHEN us.Reputation > 1000 THEN 'Regular'
            ELSE 'Beginner'
        END as UserTier,
        us.LastPostDate,
        COALESCE(ua.LastComment, '1900-01-01') as LastActivity,
        RANK() OVER (ORDER BY us.Reputation DESC) as RepRank,
        RANK() OVER (ORDER BY us.PostCount DESC) as PostRank
    FROM UserStats us
    JOIN UserActivity ua ON us.UserId = ua.UserId
    WHERE us.Reputation > 0
)
SELECT 
    cm.UserId,
    cm.DisplayName,
    cm.Reputation,
    cm.PostCount,
    cm.QuestionCount,
    cm.AnswerCount,
    cm.BadgeCount,
    cm.AvgScore,
    cm.TaggedWith,
    cm.CommentCount,
    cm.HistoryCount,
    cm.VoteCount,
    cm.UserTier,
    cm.RepRank,
    cm.PostRank,
    DENSE_RANK() OVER (ORDER BY cm.Reputation DESC) as ReputationRank,
    PERCENT_RANK() OVER (ORDER BY cm.Reputation) as ReputationPercentile,
    cm.LastPostDate,
    CASE 
        WHEN cm.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
        WHEN cm.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
        ELSE 'Average'
    END as ReputationStatus,
    CASE 
        WHEN cm.PostCount > (SELECT AVG(PostCount) FROM UserStats) THEN 'Above Average Posts'
        ELSE 'Below Average Posts'
    END as PostActivityStatus,
    STRING_AGG(DISTINCT CASE WHEN pa.PostTypeCategory = 'Question with Answers' THEN pa.Title END, '; ') as QuestionsWithAnswers,
    STRING_AGG(DISTINCT CASE WHEN pa.PostTypeCategory = 'Answer' THEN pa.Title END, '; ') as AnswerTitles,
    COUNT(DISTINCT CASE WHEN pa.ScoreCategory = 'High' THEN pa.Id END) as HighScorePosts,
    COUNT(DISTINCT CASE WHEN pa.HasComments = 1 THEN pa.Id END) as CommentedPosts,
    COUNT(DISTINCT CASE WHEN pa.IsDuplicate = 1 THEN pa.Id END) as DuplicatePosts,
    ROW_NUMBER() OVER (PARTITION BY cm.UserTier ORDER BY cm.Reputation DESC) as TierRank,
    RANK() OVER (PARTITION BY cm.UserTier ORDER BY cm.PostCount DESC) as TierPostRank,
    LAG(cm.Reputation, 1) OVER (ORDER BY cm.Reputation DESC) as PrevReputation,
    LEAD(cm.Reputation, 1) OVER (ORDER BY cm.Reputation DESC) as NextReputation,
    CASE 
        WHEN cm.TotalActivity > (SELECT AVG(TotalActivity) FROM UserActivity) THEN 1
        ELSE 0
    END as AboveActivityAverage,
    ROUND((cm.PostCount * 100.0) / (SELECT COUNT(*) FROM Users), 2) as PostPercentage,
    CASE 
        WHEN cm.Reputation IS NOT NULL AND cm.PostCount > 0 THEN cm.Reputation / cm.PostCount
        ELSE NULL
    END as RepPerPost
FROM ComplexUserMetrics cm
LEFT JOIN PostAnalysis pa ON cm.UserId = pa.OwnerUserId
WHERE cm.Reputation > 100
AND cm.PostCount > 5
GROUP BY 
    cm.UserId, 
    cm.DisplayName, 
    cm.Reputation, 
    cm.PostCount, 
    cm.QuestionCount, 
    cm.AnswerCount, 
    cm.BadgeCount, 
    cm.AvgScore, 
    cm.TaggedWith, 
    cm.CommentCount, 
    cm.HistoryCount, 
    cm.VoteCount, 
    cm.UserTier, 
    cm.RepRank, 
    cm.PostRank, 
    cm.LastPostDate, 
    cm.TotalActivity
HAVING 
    COUNT(DISTINCT pa.Id) > 0
    AND cm.Reputation > (SELECT AVG(Reputation) FROM Users)
ORDER BY 
    cm.Reputation DESC,
    cm.PostCount DESC,
    cm.RepRank ASC
LIMIT 1000;