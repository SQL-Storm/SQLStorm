-- {"query": "7998.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1792} 
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
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Newbie'
        END as UserLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'ZeroOrNegative'
        END as VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as PostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(4) OVER (ORDER BY p.CreationDate) as PostingQuarter
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2020-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        DATEDIFF(day, u.CreationDate, NOW()) as DaysSinceRegistration,
        CASE 
            WHEN DATEDIFF(day, u.CreationDate, NOW()) > 365 THEN 'LongTerm'
            WHEN DATEDIFF(day, u.CreationDate, NOW()) > 180 THEN 'MediumTerm'
            ELSE 'ShortTerm'
        END as TenureCategory,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT b.Id) as TotalBadges,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2008-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT 
    us.UserId,
    us.DisplayName,
    CONCAT('Reputation: ', us.Reputation, ' | Views: ', us.Views) as ProfileSummary,
    us.PostCount,
    us.CommentCount,
    us.BadgeCount,
    CASE 
        WHEN us.PostCount > 0 THEN CONCAT('Avg Score: ', ROUND(us.AvgPostScore, 2))
        ELSE 'No Posts'
    END as AvgPostPerformance,
    CASE 
        WHEN us.PostCount > 0 THEN CONCAT('Last Post: ', DATE_FORMAT(us.LastPostDate, '%Y-%m-%d'))
        ELSE 'No Posts'
    END as LastActivity,
    us.TotalViews,
    CASE 
        WHEN us.AllTags IS NOT NULL THEN CONCAT('Tags: ', SUBSTRING(us.AllTags, 1, 50), '...')
        ELSE 'No Tags'
    END as TagSummary,
    us.UserLevel,
    (
        SELECT COUNT(*) 
        FROM PostPerformance pp 
        WHERE pp.OwnerUserId = us.UserId 
        AND pp.PostType = 'Question'
    ) as QuestionCount,
    (
        SELECT COUNT(*) 
        FROM PostPerformance pp 
        WHERE pp.OwnerUserId = us.UserId 
        AND pp.PostType = 'Answer'
    ) as AnswerCount,
    (
        SELECT AVG(p.Score) 
        FROM Posts p 
        WHERE p.OwnerUserId = us.UserId 
        AND p.PostTypeId = 1
    ) as AvgQuestionScore,
    (
        SELECT AVG(p.Score) 
        FROM Posts p 
        WHERE p.OwnerUserId = us.UserId 
        AND p.PostTypeId = 2
    ) as AvgAnswerScore,
    (
        SELECT COUNT(DISTINCT p.Id) 
        FROM Posts p 
        WHERE p.OwnerUserId = us.UserId 
        AND p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 MONTH)
    ) as RecentPosts,
    (
        SELECT COUNT(DISTINCT c.Id) 
        FROM Comments c 
        WHERE c.UserId = us.UserId
    ) as RecentComments,
    (
        SELECT COUNT(DISTINCT b.Id) 
        FROM Badges b 
        WHERE b.UserId = us.UserId
    ) as RecentBadges,
    CONCAT(
        'Score Rank: ', COALESCE((SELECT ScoreRank FROM PostPerformance WHERE OwnerUserId = us.UserId ORDER BY ScoreRank LIMIT 1), 'N/A'),
        ' | View Rank: ', COALESCE((SELECT ViewRank FROM PostPerformance WHERE OwnerUserId = us.UserId ORDER BY ViewRank LIMIT 1), 'N/A')
    ) as PerformanceMetrics,
    (
        SELECT GROUP_CONCAT(DISTINCT ta.TagName ORDER BY ta.PopularityRank)
        FROM Posts p
        JOIN (
            SELECT TagName FROM Tags WHERE Count > 50
        ) ta ON POSITION(CONCAT('<', ta.TagName, '>') IN CONCAT('<', p.Tags, '>'))
        WHERE p.OwnerUserId = us.UserId
    ) as PopularTags,
    (SELECT COUNT(*) FROM Tags WHERE Count > 500) as PopularTagCount,
    (
        SELECT COUNT(*) FROM Votes v 
        JOIN Posts p ON v.PostId = p.Id 
        WHERE p.OwnerUserId = us.UserId 
        AND v.VoteTypeId IN (2, 3)
    ) as UpDownVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.Score > 100) as HighScorePosts,
    CASE 
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.Score > 100) > 5 THEN 'High Performer'
        WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.Score > 100) > 2 THEN 'Mid Performer'
        ELSE 'Low Performer'
    END as PerformanceTier
FROM UserStats us
WHERE us.PostCount > 0
AND (
    SELECT COUNT(DISTINCT p.Id) 
    FROM Posts p 
    WHERE p.OwnerUserId = us.UserId 
    AND p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
) > 0
HAVING PostCount > 5
ORDER BY us.Reputation DESC, us.PostCount DESC
LIMIT 1000;