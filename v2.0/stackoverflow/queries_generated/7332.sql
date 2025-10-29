-- {"query": "7332.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2660} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) as GlobalRank,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        NTILE(100) OVER (ORDER BY p.Score) as ScorePercentile,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as UserTotalPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserTotalScore,
        COALESCE(p.Title, p.Tags) as TitleOrTags,
        REPLACE(REPLACE(p.Tags, '<', ''), '>', '') as CleanTags,
        CASE 
            WHEN p.AnswerCount IS NULL OR p.AnswerCount = 0 THEN 'No Answers'
            WHEN p.AnswerCount BETWEEN 1 AND 5 THEN 'Few Answers'
            WHEN p.AnswerCount BETWEEN 6 AND 20 THEN 'Several Answers'
            ELSE 'Many Answers'
        END as AnswerLevel,
        COALESCE(p.Score, 0) + COALESCE(p.ViewCount, 0) + COALESCE(p.CommentCount, 0) as CombinedScore,
        IIF(p.Score > 0, p.Score, 0) / NULLIF(p.ViewCount, 0) as ScoreToViewRatio,
        CASE 
            WHEN p.CreationDate >= '2020-01-01' THEN '2020+'
            WHEN p.CreationDate >= '2015-01-01' THEN '2015-2019'
            WHEN p.CreationDate >= '2010-01-01' THEN '2010-2014'
            ELSE 'Pre-2010'
        END as TimePeriod
    FROM Posts p
    WHERE p.Score >= -10 AND p.ViewCount >= 0
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COALESCE(u.Views, 0) + COALESCE(u.UpVotes, 0) + COALESCE(u.DownVotes, 0) as UserActivity,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        AVG(u.Reputation) OVER (PARTITION BY u.AccountId) as AccountAvgReputation,
        CASE 
            WHEN u.Reputation BETWEEN 1 AND 100 THEN 'Novice'
            WHEN u.Reputation BETWEEN 101 AND 1000 THEN 'Expert'
            WHEN u.Reputation BETWEEN 1001 AND 10000 THEN 'Master'
            WHEN u.Reputation >= 10001 THEN 'Legend'
            ELSE 'Other'
        END as ReputationLevel,
        COUNT(DISTINCT ps.PostId) as UserPostCount,
        SUM(ps.Score) as UserTotalScore,
        AVG(ps.Score) as UserAvgScore,
        MAX(ps.CreationDate) as LastActivity,
        IIF(COUNT(DISTINCT ps.PostId) > 0, 
            (COUNT(DISTINCT ps.PostId) * 100.0) / NULLIF(COUNT(*) OVER(), 0), 0) as PostContributionPercent
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Reputation >= 0
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count BETWEEN 1 AND 10 THEN 'Low Popularity'
            WHEN t.Count BETWEEN 11 AND 100 THEN 'Medium Popularity'
            WHEN t.Count BETWEEN 101 AND 1000 THEN 'High Popularity'
            ELSE 'Very High Popularity'
        END as PopularityLevel,
        IIF(t.Count > 0, 
            (t.Count * 100.0) / NULLIF(SUM(t.Count) OVER(), 0), 0) as TagPercentage,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PrevCount,
        LEAD(t.Count, 1) OVER (ORDER BY t.Count DESC) as NextCount,
        NTILE(10) OVER (ORDER BY t.Count DESC) as PopularityDecile,
        t.IsModeratorOnly,
        t.IsRequired
    FROM Tags t
    WHERE t.Count > 0
),
CommentStats AS (
    SELECT 
        c.PostId,
        COUNT(*) as CommentCount,
        AVG(c.Score) as AvgCommentScore,
        MAX(c.CreationDate) as LatestCommentDate,
        IIF(COUNT(*) > 0, 
            (COUNT(*) * 100.0) / NULLIF(COUNT(*) OVER(), 0), 0) as CommentRatio,
        MAX(c.Score) as MaxCommentScore,
        MIN(c.Score) as MinCommentScore
    FROM Comments c
    GROUP BY c.PostId
)
SELECT 
    ps.PostId,
    ps.PostTypeId,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.CreationDate,
    ps.OwnerUserId,
    ps.Title,
    ps.Tags,
    ps.ParentId,
    ps.AcceptedAnswerId,
    ps.PostType,
    ps.UserPostRank,
    ps.GlobalRank,
    ps.PrevScore,
    ps.NextScore,
    ps.ScorePercentile,
    ps.UserTotalPosts,
    ps.UserAvgScore,
    ps.UserTotalScore,
    ps.TitleOrTags,
    ps.CleanTags,
    ps.AnswerLevel,
    ps.CombinedScore,
    ps.ScoreToViewRatio,
    ps.TimePeriod,
    us.Reputation,
    us.DisplayName as UserName,
    us.CreationDate as UserCreationDate,
    us.Views as UserViews,
    us.UpVotes as UserUpVotes,
    us.DownVotes as UserDownVotes,
    us.AccountId,
    us.UserActivity,
    us.ReputationRank,
    us.AccountAvgReputation,
    us.ReputationLevel,
    us.UserPostCount,
    us.UserTotalScore as UserTotalScore,
    us.UserAvgScore as UserAverageScore,
    us.LastActivity,
    us.PostContributionPercent,
    ta.TagName,
    ta.Count as TagCount,
    ta.ExcerptPostId,
    ta.WikiPostId,
    ta.PopularityLevel,
    ta.TagPercentage,
    ta.PopularRank,
    ta.PrevCount,
    ta.NextCount,
    ta.PopularityDecile,
    ta.IsModeratorOnly,
    ta.IsRequired,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.LatestCommentDate,
    cs.CommentRatio,
    cs.MaxCommentScore,
    cs.MinCommentScore,
    CASE 
        WHEN ps.Score > 0 AND ps.ViewCount > 0 AND ps.CommentCount > 0 THEN 'Active Post'
        WHEN ps.Score >= 0 AND ps.ViewCount > 0 THEN 'Viewed Post'
        WHEN ps.Score < 0 THEN 'Negative Score Post'
        ELSE 'Other'
    END as PostStatus,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ps.OwnerUserId AND p2.CreationDate >= '2020-01-01') as RecentPostsCount,
    CASE 
        WHEN ps.Score > (SELECT AVG(Score) FROM Posts) THEN 'Above Average'
        WHEN ps.Score < (SELECT AVG(Score) FROM Posts) THEN 'Below Average'
        ELSE 'Average'
    END as ScoringPosition,
    COALESCE(ps.Score, 0) + COALESCE(us.Reputation, 0) + COALESCE(ps.ViewCount, 0) as ComplexScore,
    IIF(ps.CreationDate IS NOT NULL AND us.CreationDate IS NOT NULL,
        EXTRACT(DAY FROM (ps.CreationDate - us.CreationDate)), 
        NULL) as TimeDiffDays,
    DATEDIFF('day', ps.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
    ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as PostOrdinal,
    RANK() OVER (ORDER BY ps.Score DESC) as RankByScore,
    DENSE_RANK() OVER (ORDER BY ps.CreationDate DESC) as RankByDate,
    CASE 
        WHEN ps.Tags IS NOT NULL AND ps.Tags LIKE '%<%' THEN 
            (SELECT COUNT(*) FROM unnest(string_to_array(substring(ps.Tags, 2, length(ps.Tags)-2), '><')) as tag)
        ELSE 0
    END as TagCountInPost,
    IIF(ps.PostTypeId = 1, ps.AnswerCount, NULL) as QuestionAnswerCount,
    IIF(ps.PostTypeId = 2, ps.ParentId, NULL) as AnswerParentId,
    CASE 
        WHEN ps.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
        WHEN ps.PostTypeId = 1 AND ps.AnswerCount > 0 THEN 'Has Answers'
        ELSE 'No Answers'
    END as AnswerStatus,
    NULLIF(us.Views + us.UpVotes + us.DownVotes, 0) as UserActivityScore,
    CASE 
        WHEN ps.CreationDate > '2023-01-01' THEN 'Recent'
        WHEN ps.CreationDate > '2020-01-01' THEN 'Modernity'
        ELSE 'Historical'
    END as TemporalCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ps.OwnerUserId AND b.Date >= '2023-01-01') as RecentBadgesCount,
    ps.UserPostRank * ps.Score as UserPostScore,
    (ps.CreationDate - ps.CreationDate) * 100 as DateAdjustmentFactor,
    IIF(ps.CombinedScore > 100 THEN 'High Activity' 
        WHEN ps.CombinedScore BETWEEN 10 AND 100 THEN 'Medium Activity' 
        ELSE 'Low Activity' END as ActivityLevel,
    (SELECT COUNT(*) FROM PostHistory ph 
     WHERE ph.PostId = ps.PostId 
     AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5) 
     AND ph.CreationDate > '2020-01-01') as RecentEditsCount,
    COALESCE(ps.Score, 0) * COALESCE(ps.ViewCount, 0) * COALESCE(ps.CommentCount, 0) as ComplexInteractionScore
FROM PostStats ps
INNER JOIN UserStats us ON ps.OwnerUserId = us.UserId
LEFT JOIN TagAnalysis ta ON ps.Tags IS NOT NULL AND ps.Tags LIKE '%' || ta.TagName || '%'
LEFT JOIN CommentStats cs ON ps.PostId = cs.PostId
WHERE ps.Score > -50 
AND (us.Reputation > 50 OR us.Reputation IS NULL)
AND ps.PostType IN ('Question', 'Answer')
AND (ps.CreationDate > '2010-01-01' OR ps.CreationDate IS NULL)
AND (ps.ViewCount > 10 OR ps.ViewCount IS NULL)
ORDER BY ps.Score DESC, ps.CreationDate DESC, ps.GlobalRank LIMIT 1000;