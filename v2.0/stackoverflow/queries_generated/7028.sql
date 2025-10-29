-- {"query": "7028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1625} 
WITH UserActivity AS (
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
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) as ViewQuartile,
        COALESCE(p.Tags, '') as Tags,
        STRING_AGG(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') WITHIN GROUP (ORDER BY p.Id) as AllTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ViewQuartile,
        ps.Tags,
        ps.AllTags,
        CASE 
            WHEN ps.Score > 100 THEN 'HighlyVoted'
            WHEN ps.Score > 50 THEN 'WellVoted'
            WHEN ps.Score > 10 THEN 'ModeratelyVoted'
            ELSE 'LowVoted'
        END as VotingCategory,
        CASE 
            WHEN ps.ViewCount > 10000 THEN 'Viral'
            WHEN ps.ViewCount > 1000 THEN 'Popular'
            WHEN ps.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityCategory,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId = 2) as UpvotesCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId = 3) as DownvotesCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.PostId) as CommentCountActual
    FROM PostStats ps
),
UserPostAnalysis AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.ReputationLevel,
        COALESCE(tp.Score, 0) as LatestScore,
        COALESCE(tp.ViewCount, 0) as LatestViews,
        COALESCE(tp.AnswerCount, 0) as LatestAnswers,
        COALESCE(tp.CommentCountActual, 0) as LatestComments,
        tp.PostId,
        tp.Title,
        tp.Tags,
        tp.ScoreRank,
        tp.ViewQuartile,
        tp.VotingCategory,
        tp.PopularityCategory,
        CASE 
            WHEN ua.PostCount > 0 AND tp.Score > 0 THEN (ua.PostCount * tp.Score) / (ua.Reputation + 1)
            ELSE 0
        END as EfficiencyScore,
        CASE 
            WHEN ua.Reputation >= 1000 AND tp.Score < 10 THEN 'Underperforming'
            WHEN ua.Reputation >= 1000 AND tp.Score >= 10 AND tp.Score < 50 THEN 'Moderate'
            WHEN ua.Reputation >= 1000 AND tp.Score >= 50 THEN 'HighlyActive'
            ELSE 'Inactive'
        END as ActivityLevel
    FROM UserActivity ua
    LEFT JOIN TopPosts tp ON ua.UserId = tp.OwnerUserId AND tp.UserPostRank = 1
    WHERE ua.PostCount > 0 OR ua.CommentCount > 0 OR ua.BadgeCount > 0
)
SELECT 
    uaa.UserId,
    uaa.DisplayName,
    uaa.Reputation,
    uaa.PostCount,
    uaa.CommentCount,
    uaa.BadgeCount,
    uaa.ReputationLevel,
    uaa.EfficiencyScore,
    uaa.ActivityLevel,
    uaa.LatestScore,
    uaa.LatestViews,
    uaa.LatestAnswers,
    uaa.LatestComments,
    uaa.PostId,
    uaa.Title,
    uaa.Tags,
    uaa.ScoreRank,
    uaa.ViewQuartile,
    uaa.VotingCategory,
    uaa.PopularityCategory,
    CASE 
        WHEN uaa.EfficiencyScore > 100 THEN 'Exceptional'
        WHEN uaa.EfficiencyScore > 50 THEN 'Good'
        WHEN uaa.EfficiencyScore > 10 THEN 'Fair'
        ELSE 'Poor'
    END as PerformanceCategory,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = uaa.UserId 
     AND p.PostTypeId = 1 
     AND p.CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as QuestionsLastYear,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = uaa.UserId 
     AND p.PostTypeId = 2 
     AND p.CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as AnswersLastYear,
    (SELECT STRING_AGG(b.Name, ', ') 
     FROM Badges b 
     WHERE b.UserId = uaa.UserId 
     AND b.Date >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as RecentBadges,
    COALESCE(uaa.PostCount, 0) + COALESCE(uaa.CommentCount, 0) + COALESCE(uaa.BadgeCount, 0) as TotalActivity,
    (SELECT STRING_AGG(ps.Title, ', ') 
     FROM Posts ps 
     WHERE ps.OwnerUserId = uaa.UserId 
     AND ps.PostTypeId = 1 
     AND ps.AnswerCount > 0 
     AND ps.CreationDate >= DATEADD(MONTH, -6, CURRENT_TIMESTAMP)) as RecentAnsweredQuestions
FROM UserPostAnalysis uaa
WHERE uaa.PostCount > 0
ORDER BY uaa.EfficiencyScore DESC, uaa.Reputation DESC, uaa.LatestScore DESC
LIMIT 1000;