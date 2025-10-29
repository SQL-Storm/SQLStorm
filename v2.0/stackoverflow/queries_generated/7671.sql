-- {"query": "7671.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2569} 
WITH RECURSIVE UserHierarchy AS (
    SELECT Id, AccountId, 0 as Level
    FROM Users
    WHERE AccountId IS NOT NULL
    UNION ALL
    SELECT u.Id, u.AccountId, uh.Level + 1
    FROM Users u
    INNER JOIN UserHierarchy uh ON u.AccountId = uh.AccountId
    WHERE uh.Level < 3
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        AVG(p.Score) as AvgScore,
        COUNT(DISTINCT p.OwnerUserId) as UniqueOwners,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as OwnerNames
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.TagName IS NOT NULL
    GROUP BY t.TagName, t.Count
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PrevScore,
        COALESCE(p.OwnerUserId, -1) as EffectiveOwner,
        COALESCE(p.OwnerDisplayName, 'Anonymous') as EffectiveOwnerName,
        (CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as HasAcceptedAnswer,
        TRIM(BOTH '<>' FROM p.Tags) as CleanedTags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountActual,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) as UpDownVotes
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' 
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT ps.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) as Answers,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) * 100.0 / NULLIF(COUNT(DISTINCT ps.Id), 0) as QuestionPercent,
        AVG(ps.Score) as AvgPostScore,
        MAX(ps.CreationDate) as LastPostDate,
        MIN(ps.CreationDate) as FirstPostDate,
        COUNT(DISTINCT b.Id) as BadgesReceived,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts ps ON ps.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PerformanceMetrics AS (
    SELECT 
        pa.Id,
        pa.Title,
        pa.PostTypeDesc,
        pa.Score,
        pa.ViewCount,
        pa.ScoreCategory,
        pa.ScoreRank,
        pa.ViewRank,
        pa.AvgScoreByType,
        pa.PrevScore,
        pa.EffectiveOwner,
        pa.EffectiveOwnerName,
        pa.HasAcceptedAnswer,
        pa.CleanedTags,
        pa.CommentCountActual,
        pa.UpDownVotes,
        CASE 
            WHEN pa.ViewCount > 0 THEN pa.Score * 100.0 / pa.ViewCount
            ELSE 0 
        END as ScorePerView,
        CASE 
            WHEN pa.Score > 0 AND pa.ViewCount > 0 THEN (pa.AnswerCount * 100.0) / pa.Score
            ELSE 0 
        END as AnswerRatio,
        CASE 
            WHEN pa.FavoriteCount > 0 THEN pa.CommentCountActual * 1.0 / pa.FavoriteCount
            ELSE 0 
        END as CommentToFavoriteRatio,
        LTRIM(RTRIM(pa.CleanedTags, '<'), '>') as FirstTag,
        CASE 
            WHEN pa.CleanedTags LIKE '%<%' THEN 
                SUBSTRING(pa.CleanedTags, POSITION('<' IN pa.CleanedTags) + 1, POSITION('>' IN pa.CleanedTags, POSITION('<' IN pa.CleanedTags)) - POSITION('<' IN pa.CleanedTags) - 1)
            ELSE pa.CleanedTags 
        END as PrimaryTag,
        COALESCE(ut.Id, -1) as TagOwnerId,
        COALESCE(ut.Name, 'No Tag Owner') as OwnerTagStatus
    FROM PostAnalysis pa
    LEFT JOIN Tags ut ON ut.TagName = 
        CASE 
            WHEN pa.CleanedTags LIKE '%<%' THEN 
                SUBSTRING(pa.CleanedTags, POSITION('<' IN pa.CleanedTags) + 1, POSITION('>' IN pa.CleanedTags, POSITION('<' IN pa.CleanedTags)) - POSITION('<' IN pa.CleanedTags) - 1)
            ELSE pa.CleanedTags 
        END
    WHERE pa.Score IS NOT NULL
    AND (pa.PostTypeDesc = 'Question' OR pa.PostTypeDesc = 'Answer')
)
SELECT 
    pm.Id,
    pm.Title,
    pm.PostTypeDesc,
    pm.Score,
    pm.ViewCount,
    pm.ScoreCategory,
    pm.ScoreRank,
    pm.ViewRank,
    pm.AvgScoreByType,
    pm.PrevScore,
    pm.EffectiveOwner,
    pm.EffectiveOwnerName,
    pm.HasAcceptedAnswer,
    pm.CleanedTags,
    pm.CommentCountActual,
    pm.UpDownVotes,
    pm.ScorePerView,
    pm.AnswerRatio,
    pm.CommentToFavoriteRatio,
    pm.FirstTag,
    pm.PrimaryTag,
    pm.TagOwnerId,
    pm.OwnerTagStatus,
    COALESCE(ua.DisplayName, 'No User') as UserName,
    COALESCE(ua.Reputation, 0) as UserReputation,
    COALESCE(ua.TotalPosts, 0) as UserTotalPosts,
    COALESCE(ua.Questions, 0) as UserQuestions,
    COALESCE(ua.Answers, 0) as UserAnswers,
    COALESCE(ua.BadgesReceived, 0) as UserBadges,
    CASE 
        WHEN pm.ScorePerView > 5 THEN 'High Engagement'
        WHEN pm.ScorePerView > 2 THEN 'Medium Engagement' 
        ELSE 'Low Engagement'
    END as EngagementCategory,
    CASE 
        WHEN pm.TagOwnerId = -1 THEN 'Unowned Tag'
        WHEN pm.TagOwnerId = 0 THEN 'Orphaned Tag'
        ELSE 'Owned Tag'
    END as TagOwnershipStatus,
    CASE 
        WHEN pm.HasAcceptedAnswer = 1 THEN 'Answer Accepted'
        WHEN pm.Score > 10 THEN 'High Score'
        ELSE 'Normal'
    END as PostStatus,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = pm.Id) as ChildCount,
    STRING_AGG(DISTINCT pm.PrimaryTag, ', ') OVER (ORDER BY pm.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as AllTags,
    (SELECT MIN(pa2.ViewCount) FROM PostAnalysis pa2 WHERE pa2.PostTypeId = 1 AND pa2.ViewCount IS NOT NULL) as MinQuestionViews,
    (SELECT MAX(pa2.ViewCount) FROM PostAnalysis pa2 WHERE pa2.PostTypeId = 1 AND pa2.ViewCount IS NOT NULL) as MaxQuestionViews,
    (SELECT AVG(pa2.ViewCount) FROM PostAnalysis pa2 WHERE pa2.PostTypeId = 1 AND pa2.ViewCount IS NOT NULL) as AvgQuestionViews
FROM PerformanceMetrics pm
LEFT JOIN UserActivity ua ON ua.UserId = pm.EffectiveOwner
WHERE pm.Score > 0
AND pm.ViewCount > 0
AND pm.ScorePerView IS NOT NULL
AND (CASE WHEN pm.PrimaryTag IS NOT NULL THEN pm.PrimaryTag ELSE '' END) != ''
ORDER BY pm.Score DESC, pm.ViewCount DESC
LIMIT 1000
EXCEPT
SELECT 
    pm.Id,
    pm.Title,
    pm.PostTypeDesc,
    pm.Score,
    pm.ViewCount,
    pm.ScoreCategory,
    pm.ScoreRank,
    pm.ViewRank,
    pm.AvgScoreByType,
    pm.PrevScore,
    pm.EffectiveOwner,
    pm.EffectiveOwnerName,
    pm.HasAcceptedAnswer,
    pm.CleanedTags,
    pm.CommentCountActual,
    pm.UpDownVotes,
    pm.ScorePerView,
    pm.AnswerRatio,
    pm.CommentToFavoriteRatio,
    pm.FirstTag,
    pm.PrimaryTag,
    pm.TagOwnerId,
    pm.OwnerTagStatus,
    COALESCE(ua.DisplayName, 'No User') as UserName,
    COALESCE(ua.Reputation, 0) as UserReputation,
    COALESCE(ua.TotalPosts, 0) as UserTotalPosts,
    COALESCE(ua.Questions, 0) as UserQuestions,
    COALESCE(ua.Answers, 0) as UserAnswers,
    COALESCE(ua.BadgesReceived, 0) as UserBadges,
    CASE 
        WHEN pm.ScorePerView > 5 THEN 'High Engagement'
        WHEN pm.ScorePerView > 2 THEN 'Medium Engagement' 
        ELSE 'Low Engagement'
    END as EngagementCategory,
    CASE 
        WHEN pm.TagOwnerId = -1 THEN 'Unowned Tag'
        WHEN pm.TagOwnerId = 0 THEN 'Orphaned Tag'
        ELSE 'Owned Tag'
    END as TagOwnershipStatus,
    CASE 
        WHEN pm.HasAcceptedAnswer = 1 THEN 'Answer Accepted'
        WHEN pm.Score > 10 THEN 'High Score'
        ELSE 'Normal'
    END as PostStatus,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = pm.Id) as ChildCount,
    STRING_AGG(DISTINCT pm.PrimaryTag, ', ') OVER (ORDER BY pm.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as AllTags,
    (SELECT MIN(pa2.ViewCount) FROM PostAnalysis pa2 WHERE pa2.PostTypeId = 1 AND pa2.ViewCount IS NOT NULL) as MinQuestionViews,
    (SELECT MAX(pa2.ViewCount) FROM PostAnalysis pa2 WHERE pa2.PostTypeId = 1 AND pa2.ViewCount IS NOT NULL) as MaxQuestionViews,
    (SELECT AVG(pa2.ViewCount) FROM PostAnalysis pa2 WHERE pa2.PostTypeId = 1 AND pa2.ViewCount IS NOT NULL) as AvgQuestionViews
FROM PerformanceMetrics pm
LEFT JOIN UserActivity ua ON ua.UserId = pm.EffectiveOwner
WHERE pm.HasAcceptedAnswer = 0
AND pm.Score < 50
AND pm.ViewCount < 100
ORDER BY pm.Score ASC, pm.ViewCount ASC
LIMIT 500;