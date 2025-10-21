-- {"query": "47036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1877}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        1 as Level
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName
    HAVING COUNT(DISTINCT p.Id) > 1000
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT p.Id) as AnswerCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) as AcceptedAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore,
        STDDEV(p.Score) as ScoreStdDev
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    INNER JOIN Posts q ON q.Id = p.ParentId AND q.PostTypeId = 1
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE u.Reputation > 1000
        AND p.Score > 0
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
badge_analysis AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = true THEN b.Name END) as UniqueTagBadges,
        MIN(b.Date) as FirstBadgeDate,
        MAX(b.Date) as LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
post_evolution AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) as EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) as RollbackCount,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) as WasClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) as WasReopened,
        STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END, ',') as CloseReasons
    FROM PostHistory ph
    GROUP BY ph.PostId
),
interaction_network AS (
    SELECT 
        c.UserId as CommenterId,
        p.OwnerUserId as PostOwnerId,
        COUNT(DISTINCT c.Id) as CommentCount,
        AVG(c.Score) as AvgCommentScore,
        COUNT(DISTINCT p.Id) as UniquePostsCommented
    FROM Comments c
    INNER JOIN Posts p ON p.Id = c.PostId
    WHERE c.UserId IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
        AND c.UserId != p.OwnerUserId
    GROUP BY c.UserId, p.OwnerUserId
    HAVING COUNT(DISTINCT c.Id) >= 5
)
SELECT 
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TagName,
    ue.AnswerCount,
    ue.TotalScore,
    ue.AvgScore,
    ue.MedianScore,
    ue.ScoreStdDev,
    ue.AcceptedAnswers,
    ROUND(100.0 * ue.AcceptedAnswers / NULLIF(ue.AnswerCount, 0), 2) as AcceptanceRate,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.UniqueTagBadges,
    EXTRACT(EPOCH FROM (ba.LastBadgeDate - ba.FirstBadgeDate)) / 86400.0 as BadgeSpanDays,
    COUNT(DISTINCT pe.PostId) as EditedPosts,
    AVG(pe.EditCount) as AvgEditsPerPost,
    SUM(pe.WasClosed) as ClosedPosts,
    SUM(pe.WasReopened) as ReopenedPosts,
    COUNT(DISTINCT inn_out.PostOwnerId) as UsersHelpedViaComments,
    COUNT(DISTINCT inn_in.CommenterId) as UsersWhoCommented,
    COALESCE(AVG(inn_out.AvgCommentScore), 0) as AvgOutgoingCommentScore,
    COALESCE(AVG(inn_in.AvgCommentScore), 0) as AvgIncomingCommentScore,
    DENSE_RANK() OVER (PARTITION BY ue.TagName ORDER BY ue.TotalScore DESC) as TagRank,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) as GlobalRank,
    PERCENT_RANK() OVER (PARTITION BY ue.TagName ORDER BY ue.AvgScore) as TagPercentile
FROM user_expertise ue
LEFT JOIN badge_analysis ba ON ba.UserId = ue.UserId
LEFT JOIN Posts p ON p.OwnerUserId = ue.UserId AND p.PostTypeId = 2
LEFT JOIN post_evolution pe ON pe.PostId = p.Id
LEFT JOIN interaction_network inn_out ON inn_out.CommenterId = ue.UserId
LEFT JOIN interaction_network inn_in ON inn_in.PostOwnerId = ue.UserId
WHERE ue.TotalScore > 100
GROUP BY 
    ue.UserId, ue.DisplayName, ue.Reputation, ue.TagName, 
    ue.AnswerCount, ue.TotalScore, ue.AvgScore, ue.MedianScore,
    ue.ScoreStdDev, ue.AcceptedAnswers, ba.GoldBadges, 
    ba.SilverBadges, ba.BronzeBadges, ba.UniqueTagBadges,
    ba.LastBadgeDate, ba.FirstBadgeDate
HAVING COUNT(DISTINCT pe.PostId) > 0
ORDER BY ue.Reputation DESC, ue.TotalScore DESC
LIMIT 500;
