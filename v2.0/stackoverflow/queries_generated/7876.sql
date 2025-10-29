-- {"query": "7876.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3121} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as score_rank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) as view_decile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.AccountId
),
PostsWithComments AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        c.Text as CommentText,
        c.Score as CommentScore,
        CASE 
            WHEN c.Score < 0 THEN 'Negative'
            WHEN c.Score > 0 THEN 'Positive'
            ELSE 'Neutral'
        END as CommentRating,
        CASE 
            WHEN p.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'NoAnswers'
        END as AnswerStatus,
        COALESCE(p.Tags, '') as Tags,
        REGEXP_REPLACE(p.Tags, '<[^>]*>', '', 'g') as CleanTags,
        LENGTH(p.Body) as BodyLength,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AnswerCount,
        (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = p.Id) as CommentCount,
        (SELECT AVG(v.Score) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)) as AvgVoteScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= '2018-01-01'
    AND p.Score > 50
),
TopQuestions AS (
    SELECT 
        q.Id,
        q.Title,
        q.Body,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.OwnerUserId,
        q.Tags,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        CAST(q.Score AS FLOAT) / (1 + q.ViewCount) as ScoreToViewRatio,
        CASE 
            WHEN q.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END as QuestionStatus,
        CASE 
            WHEN q.Tags LIKE '%python%' THEN 'PythonRelated'
            WHEN q.Tags LIKE '%javascript%' THEN 'JavaScriptRelated'
            WHEN q.Tags LIKE '%java%' THEN 'JavaRelated'
            ELSE 'Other'
        END as LanguageTag
    FROM Posts q
    WHERE q.PostTypeId = 1
    AND q.ViewCount > 1000
    AND q.CreationDate >= '2017-01-01'
    AND q.AnswerCount > 0
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreation,
        COUNT(DISTINCT v.Id) as TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as Favorites,
        COUNT(DISTINCT p.Id) as PostsCreated,
        MAX(v.CreationDate) as LastVoteDate,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) as DaysSinceJoin,
        CASE 
            WHEN COUNT(DISTINCT v.Id) > 1000 THEN 'High'
            WHEN COUNT(DISTINCT v.Id) > 100 THEN 'Medium'
            ELSE 'Low'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
DetailedPostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        CASE 
            WHEN (p.ViewCount > 0) THEN (p.Score * 1.0 / p.ViewCount)
            ELSE 0
        END as ScorePerView,
        CASE 
            WHEN (p.AnswerCount > 0) THEN (p.ViewCount * 1.0 / p.AnswerCount)
            ELSE 0
        END as ViewsPerAnswer,
        CASE 
            WHEN (p.Score > 0 AND p.ViewCount > 0) THEN (p.Score * 1.0 / (p.ViewCount + 1))
            ELSE 0
        END as NormalizedScore,
        CASE 
            WHEN p.CreationDate >= '2020-01-01' AND p.CreationDate < '2021-01-01' THEN '2020'
            WHEN p.CreationDate >= '2021-01-01' AND p.CreationDate < '2022-01-01' THEN '2021'
            WHEN p.CreationDate >= '2022-01-01' THEN '2022'
            ELSE 'Older'
        END as YearGroup,
        IIF(p.AnswerCount > 10, 'HighAnswerCount', 'LowAnswerCount') as AnswerGroup,
        STRING_AGG(DISTINCT CASE WHEN b.Name IS NOT NULL THEN b.Name ELSE 'NoBadge' END, ', ') as UserBadges
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE p.PostTypeId = 1 
    AND p.ViewCount > 100
    AND p.CreationDate >= '2018-01-01'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.CreationDate, p.OwnerUserId, p.Tags, u.DisplayName, u.Reputation
),
CombinedAnalysis AS (
    SELECT 
        qa.Id,
        qa.Title,
        qa.Score,
        qa.ViewCount,
        qa.AnswerCount,
        qa.CommentCount,
        qa.FavoriteCount,
        qa.CreationDate,
        qa.OwnerUserId,
        qa.OwnerName,
        qa.OwnerReputation,
        qa.ScorePerView,
        qa.ViewsPerAnswer,
        qa.NormalizedScore,
        qa.YearGroup,
        qa.AnswerGroup,
        qa.UserBadges,
        us.Reputation as UserMaxReputation,
        us.TotalPosts as UserTotalPosts,
        us.QuestionCount as UserQuestionCount,
        us.AnswerCount as UserAnswerCount,
        us.AvgScore as UserAvgScore,
        us.BadgeCount as UserBadgeCount,
        us.GoldBadges as UserGoldBadges,
        us.SilverBadges as UserSilverBadges,
        us.BronzeBadges as UserBronzeBadges
    FROM DetailedPostAnalysis qa
    JOIN UserStats us ON qa.OwnerUserId = us.UserId
    WHERE qa.Score > 100
    AND qa.ViewCount > 500
)
SELECT TOP 1000
    ca.Id,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.CreationDate,
    ca.OwnerUserId,
    ca.OwnerName,
    ca.OwnerReputation,
    ca.ScorePerView,
    ca.ViewsPerAnswer,
    ca.NormalizedScore,
    ca.YearGroup,
    ca.AnswerGroup,
    ca.UserBadges,
    ca.UserMaxReputation,
    ca.UserTotalPosts,
    ca.UserQuestionCount,
    ca.UserAnswerCount,
    ca.UserAvgScore,
    ca.UserBadgeCount,
    ca.UserGoldBadges,
    ca.UserSilverBadges,
    ca.UserBronzeBadges,
    (ca.ScorePerView * ca.ViewsPerAnswer) as ProductOfRatios,
    (ca.UserAvgScore * ca.NormalizedScore) as UserScoreNormalization,
    CASE 
        WHEN (ca.UserMaxReputation > 10000) THEN 'Elite'
        WHEN (ca.UserMaxReputation > 5000) THEN 'Veteran'
        ELSE 'Regular'
    END as UserTier,
    CASE 
        WHEN ca.AnswerCount > 10 THEN 'HighEngagement'
        WHEN ca.AnswerCount > 5 THEN 'MediumEngagement'
        ELSE 'LowEngagement'
    END as EngagementLevel,
    CASE 
        WHEN ca.ViewCount > 5000 THEN 'Viral'
        WHEN ca.ViewCount > 1000 THEN 'Popular'
        WHEN ca.ViewCount > 100 THEN 'Noticeable'
        ELSE 'Unknown'
    END as PopularityLevel,
    COALESCE(
        (SELECT STRING_AGG(CONCAT(p2.Title, ':', p2.ViewCount), ' | ') 
         FROM Posts p2 
         WHERE p2.OwnerUserId = ca.OwnerUserId 
         AND p2.Id != ca.Id 
         AND p2.ViewCount > 100 
         ORDER BY p2.ViewCount DESC 
         LIMIT 5), 
        'NoOtherPosts'
    ) as SimilarPosts,
    (SELECT COUNT(*) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = ca.OwnerUserId 
     AND p3.PostTypeId = 1 
     AND p3.CreationDate > '2020-01-01') as RecentQuestions,
    (SELECT COUNT(*) 
     FROM Posts p4 
     WHERE p4.OwnerUserId = ca.OwnerUserId 
     AND p4.PostTypeId = 2 
     AND p4.CreationDate > '2020-01-01') as RecentAnswers,
    (SELECT AVG(v2.Score) 
     FROM Votes v2 
     WHERE v2.UserId = ca.OwnerUserId) as AvgUserVoteScore,
    EXISTS (
        SELECT 1 
        FROM Posts p5 
        WHERE p5.OwnerUserId = ca.OwnerUserId 
        AND p5.PostTypeId = 1 
        AND p5.Score > 500
    ) as HasHighScoreQuestion,
    (SELECT COUNT(DISTINCT c2.Id) 
     FROM Comments c2 
     WHERE c2.UserId = ca.OwnerUserId) as TotalCommentsByUser,
    (SELECT MAX(c3.CreationDate) 
     FROM Comments c3 
     WHERE c3.UserId = ca.OwnerUserId) as LastCommentDate,
    (SELECT COUNT(DISTINCT b2.Id) 
     FROM Badges b2 
     WHERE b2.UserId = ca.OwnerUserId 
     AND b2.Class = 1) as GoldBadgeCount,
    (SELECT COUNT(DISTINCT b3.Id) 
     FROM Badges b3 
     WHERE b3.UserId = ca.OwnerUserId 
     AND b3.Class = 2) as SilverBadgeCount,
    (SELECT COUNT(DISTINCT b4.Id) 
     FROM Badges b4 
     WHERE b4.UserId = ca.OwnerUserId 
     AND b4.Class = 3) as BronzeBadgeCount,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ') 
     FROM Posts p6 
     JOIN STRING_SPLIT(SUBSTRING(p6.Tags, 2, LEN(p6.Tags) - 2), '><') tag ON 1=1
     JOIN Tags t ON t.TagName = tag.value
     WHERE p6.OwnerUserId = ca.OwnerUserId
     AND p6.PostTypeId = 1) as UserTagPreferences,
    (SELECT COUNT(*) 
     FROM Votes v4 
     WHERE v4.UserId = ca.OwnerUserId 
     AND v4.VoteTypeId = 2) as UpvoteCount,
    (SELECT COUNT(*) 
     FROM Votes v5 
     WHERE v5.UserId = ca.OwnerUserId 
     AND v5.VoteTypeId = 3) as DownvoteCount
FROM CombinedAnalysis ca
WHERE ca.UserMaxReputation > 5000
AND (ca.ViewsPerAnswer > 0 OR ca.ScorePerView > 0)
ORDER BY 
    ca.Score DESC,
    ca.ViewCount DESC,
    ca.UserAvgScore DESC,
    ca.UserBadgeCount DESC,
    ca.NormalizedScore DESC,
    ca.ProductOfRatios DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;