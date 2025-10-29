-- {"query": "7297.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1969}
WITH UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400.0 as DaysSinceRegistration,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) > 500 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Experienced'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
            ELSE 'Beginner'
        END as UserLevel,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        AVG(p.Score) as AvgPostScore,
        AVG(p.ViewCount) as AvgPostViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
TopTags AS (
    SELECT 
        tags.TagName,
        tags.Count,
        tags.ExcerptPostId,
        ROW_NUMBER() OVER (ORDER BY tags.Count DESC) as Rank,
        NTILE(10) OVER (ORDER BY tags.Count DESC) as Decile
    FROM Tags tags
    WHERE tags.Count > 100
),
PostMetrics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
                    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
                    ELSE 'Unanswered'
                END
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostStatus,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High Traffic'
            WHEN p.ViewCount > 100 THEN 'Medium Traffic'
            WHEN p.ViewCount > 10 THEN 'Low Traffic'
            ELSE 'Minimal Traffic'
        END as TrafficLevel,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 10 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Slightly Voted'
            ELSE 'Controversial/No Votes'
        END as VoteStatus,
        (LENGTH(p.Body) - LENGTH(REPLACE(UPPER(p.Body), 'SELECT', ''))) as SelectKeywordCount,
        (LENGTH(p.Body) - LENGTH(REPLACE(UPPER(p.Body), 'FROM', ''))) as FromKeywordCount,
        COALESCE(LENGTH(p.Tags), 0) as TagLength,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400.0 as AgeInDays
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(p.Score) as AvgPostScore,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.ViewCount), 0) as AvgViewCount,
        MAX(p.CreationDate) as LastActivity,
        EXTRACT(EPOCH FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) / 86400.0 as ActivityDurationDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 50 AND AVG(p.Score) > 5 THEN 'High Engagement'
            WHEN COUNT(DISTINCT p.Id) > 20 AND AVG(p.Score) > 2 THEN 'Medium Engagement'
            ELSE 'Low Engagement'
        END as EngagementLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexFilter AS (
    SELECT 
        pm.PostId,
        pm.Title,
        pm.Body,
        pm.Score,
        pm.ViewCount,
        pm.CreationDate,
        pm.OwnerUserId,
        pm.PostStatus,
        pm.TrafficLevel,
        pm.VoteStatus,
        pm.SelectKeywordCount,
        pm.FromKeywordCount,
        pm.TagLength,
        pm.AgeInDays,
        ROW_NUMBER() OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY pm.Score DESC, pm.ViewCount DESC) as GlobalRank,
        DENSE_RANK() OVER (ORDER BY pm.OwnerUserId, pm.CreationDate) as UserIdPostRank,
        LAG(pm.Score, 1) OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.CreationDate) as PrevScore,
        LAG(pm.ViewCount, 1) OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.CreationDate) as PrevViewCount,
        CASE 
            WHEN pm.Score > (SELECT AVG(pm2.Score) FROM PostMetrics pm2 WHERE pm2.OwnerUserId = pm.OwnerUserId) 
            THEN 'Above Average'
            ELSE 'Below Average'
        END as ScorePerformance,
        CASE 
            WHEN pm.ViewCount > (SELECT AVG(pm2.ViewCount) FROM PostMetrics pm2 WHERE pm2.OwnerUserId = pm.OwnerUserId) 
            THEN 'Above Average Views'
            ELSE 'Below Average Views'
        END as ViewPerformance
    FROM PostMetrics pm
    WHERE pm.Score > 0 AND pm.ViewCount > 0
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.Badges,
    ua.LastPostDate,
    ua.DaysSinceRegistration,
    ua.UserLevel,
    ua.TotalScore,
    ua.TotalViews,
    ua.AvgPostScore,
    ua.AvgPostViews,
    tt.TagName,
    tt.Count as TagCount,
    tt.Rank,
    tt.Decile,
    cf.PostId,
    cf.Title,
    cf.Body,
    cf.Score,
    cf.ViewCount,
    cf.CreationDate,
    cf.PostStatus,
    cf.TrafficLevel,
    cf.VoteStatus,
    cf.SelectKeywordCount,
    cf.FromKeywordCount,
    cf.TagLength,
    cf.AgeInDays,
    cf.UserPostRank,
    cf.GlobalRank,
    cf.UserIdPostRank,
    cf.PrevScore,
    cf.PrevViewCount,
    cf.ScorePerformance,
    cf.ViewPerformance,
    CASE 
        WHEN cf.ScorePerformance = 'Above Average' AND cf.ViewPerformance = 'Above Average Views' THEN 'Top Performer'
        WHEN cf.ScorePerformance = 'Above Average' OR cf.ViewPerformance = 'Above Average Views' THEN 'Good Performer'
        ELSE 'Average Performer'
    END as PerformanceTier,
    CASE 
        WHEN ua.Reputation > 1000000 THEN 'Legendary'
        WHEN ua.Reputation > 100000 THEN 'Master'
        WHEN ua.Reputation > 10000 THEN 'Expert'
        WHEN ua.Reputation > 1000 THEN 'Advanced'
        WHEN ua.Reputation > 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationTier
FROM UserActivity ua
INNER JOIN ComplexFilter cf ON ua.UserId = cf.OwnerUserId
LEFT JOIN TopTags tt ON tt.Rank <= 5
WHERE 
    ua.TotalPosts > 10
    AND ua.Reputation > 100
    AND cf.Score > 50
    AND cf.ViewCount > 100
    AND cf.AgeInDays <= 365
    AND (
        cf.Title LIKE '%query%' 
        OR cf.Title LIKE '%sql%'
        OR cf.Body LIKE '%SELECT%'
        OR cf.Body LIKE '%FROM%'
        OR cf.Body LIKE '%JOIN%'
    )
ORDER BY 
    ua.Reputation DESC,
    cf.Score DESC,
    cf.ViewCount DESC
LIMIT 1000;