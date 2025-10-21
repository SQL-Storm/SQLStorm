-- {"query": "29014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1584} 
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
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) as RankByReputation,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC) as RankByPostCount,
        ROW_NUMBER() OVER (ORDER BY BadgeCount DESC) as RankByBadgeCount
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        COALESCE(p.Tags, '') as TagsOrEmpty,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score >= 10 THEN 'HighQualityQuestion'
            WHEN p.PostTypeId = 1 AND p.Score < 10 THEN 'LowQualityQuestion'
            WHEN p.PostTypeId = 2 AND p.Score >= 5 THEN 'HighQualityAnswer'
            WHEN p.PostTypeId = 2 AND p.Score < 5 THEN 'LowQualityAnswer'
            ELSE 'Other'
        END as PostQualityCategory,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as DaysSinceCreation,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'NoAnswers'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'NotQuestion'
        END as AnswerStatus,
        (
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
        ) as TotalVotes,
        (
            SELECT TOP 1 v.UserId 
            FROM Votes v 
            WHERE v.PostId = p.Id AND v.VoteTypeId = 1
        ) as AcceptedUserId
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
UserPostStats AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.PostCount,
        ru.CommentCount,
        ru.BadgeCount,
        ru.AvgPostScore,
        ru.ReputationTier,
        STRING_AGG(pa.Title, '; ') WITHIN GROUP (ORDER BY pa.CreationDate DESC) as RecentPostTitles,
        STRING_AGG(
            CASE 
                WHEN pa.PostTypeId = 1 THEN 'Q:' + pa.Title 
                WHEN pa.PostTypeId = 2 THEN 'A:' + pa.Title
                ELSE pa.Title 
            END, 
            ' | '
        ) WITHIN GROUP (ORDER BY pa.CreationDate DESC) as PostTypeTitles,
        AVG(pa.Score) as AvgScoreOfRecentPosts,
        MAX(pa.DaysSinceCreation) as MaxDaysSincePost,
        COUNT(CASE WHEN pa.PostQualityCategory LIKE '%Question%' THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN pa.PostQualityCategory LIKE '%Answer%' THEN 1 END) as AnswerCount,
        SUM(CASE WHEN pa.Score > 0 THEN 1 ELSE 0 END) as PositiveScoreCount,
        SUM(CASE WHEN pa.Score < 0 THEN 1 ELSE 0 END) as NegativeScoreCount
    FROM RankedUsers ru
    LEFT JOIN PostAnalysis pa ON ru.UserId = pa.OwnerUserId
    WHERE ru.PostCount > 0
    GROUP BY ru.UserId, ru.DisplayName, ru.Reputation, ru.PostCount, ru.CommentCount, ru.BadgeCount, ru.AvgPostScore, ru.ReputationTier
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.PostCount,
    ups.CommentCount,
    ups.BadgeCount,
    ups.AvgPostScore,
    ups.ReputationTier,
    ups.RecentPostTitles,
    ups.PostTypeTitles,
    ups.AvgScoreOfRecentPosts,
    ups.MaxDaysSincePost,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.PositiveScoreCount,
    ups.NegativeScoreCount,
    RANK() OVER (ORDER BY ups.Reputation DESC) as OverallReputationRank,
    RANK() OVER (ORDER BY ups.PostCount DESC) as OverallPostCountRank,
    RANK() OVER (ORDER BY ups.BadgeCount DESC) as OverallBadgeRank,
    DENSE_RANK() OVER (ORDER BY ups.ReputationTier, ups.Reputation DESC) as TierReputationRank,
    (ups.PostCount * 5 + ups.BadgeCount * 3 + ups.AvgScoreOfRecentPosts * 2) as EngagementScore,
    CASE 
        WHEN ups.QuestionCount > 0 AND ups.AnswerCount > 0 THEN 'ActiveContributor'
        WHEN ups.QuestionCount > 0 THEN 'Questioner'
        WHEN ups.AnswerCount > 0 THEN 'Answerer'
        ELSE 'Inactive'
    END as UserType,
    CASE 
        WHEN ups.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'AboveAverage'
        WHEN ups.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'BelowAverage'
        ELSE 'Average'
    END as RepComparison,
    CASE 
        WHEN ups.QuestionCount > 10 OR ups.AnswerCount > 20 THEN 'HighlyActive'
        WHEN ups.QuestionCount > 5 OR ups.AnswerCount > 10 THEN 'ModeratelyActive'
        ELSE 'LowActivity'
    END as ActivityLevel,
    CONCAT(
        'User:', ups.UserId, 
        ' | Posts:', ups.PostCount,
        ' | Badges:', ups.BadgeCount,
        ' | AvgScore:', ROUND(ups.AvgScoreOfRecentPosts, 2)
    ) as UserSummary,
    COALESCE(
        (SELECT STRING_AGG(b.Name, ', ') 
         FROM Badges b 
         WHERE b.UserId = ups.UserId 
         AND b.Date >= '2020-01-01'
        ), 
        'NoRecentBadges'
    ) as RecentBadges
FROM UserPostStats ups
WHERE ups.UserId IN (
    SELECT UserId FROM (
        SELECT UserId, COUNT(*) as PostCount 
        FROM Posts 
        WHERE CreationDate >= '2018-01-01' 
        GROUP BY UserId 
        HAVING COUNT(*) >= 5
    ) sub
)
ORDER BY ups.Reputation DESC, ups.PostCount DESC
LIMIT 500;