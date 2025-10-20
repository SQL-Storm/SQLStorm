-- {"query": "46060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 137640, "output_tokens": 110738} 

WITH RECURSIVE UserHierarchy AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        1 as Level
    FROM Users u
    WHERE u.Reputation > 10000
    
    UNION ALL
    
    SELECT 
        u2.Id,
        u2.DisplayName,
        u2.Reputation,
        u2.CreationDate,
        uh.Level + 1
    FROM Users u2
    INNER JOIN Comments c ON u2.Id = c.UserId
    INNER JOIN Posts p ON c.PostId = p.Id
    INNER JOIN UserHierarchy uh ON p.OwnerUserId = uh.Id
    WHERE uh.Level < 3 AND u2.Reputation > 5000
),
TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews,
        COUNT(DISTINCT v.Id) as TotalVotes,
        ARRAY_AGG(DISTINCT SUBSTRING(t.tag, 1, 20)) FILTER (WHERE t.tag IS NOT NULL) as TopTags
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag
    ) t ON true
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= NOW() - INTERVAL '2 years'
        AND p.Score > 5
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 5
),
AnswerMetrics AS (
    SELECT 
        a.OwnerUserId as AnswererUserId,
        q.OwnerUserId as QuestionerUserId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COUNT(DISTINCT CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Id END) as AcceptedCount,
        AVG(a.Score) as AvgAnswerScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) as MedianScore,
        MAX(a.Score) as MaxScore
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND a.CreationDate >= NOW() - INTERVAL '18 months'
        AND q.PostTypeId = 1
    GROUP BY a.OwnerUserId, q.OwnerUserId
),
BadgeProgress AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) as BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) as BadgeNames,
        MIN(b.Date) as FirstBadge,
        MAX(b.Date) as LatestBadge
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
CommentEngagement AS (
    SELECT 
        c.UserId,
        c.PostId,
        COUNT(*) as CommentCount,
        AVG(c.Score) as AvgCommentScore,
        MAX(c.CreationDate) as LastCommentDate
    FROM Comments c
    WHERE c.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY c.UserId, c.PostId
)
SELECT 
    uh.DisplayName,
    uh.Reputation,
    uh.Level as InteractionLevel,
    COALESCE(tqa.QuestionCount, 0) as TotalQuestions,
    COALESCE(tqa.AvgScore, 0) as AvgQuestionScore,
    COALESCE(tqa.TotalViews, 0) as TotalQuestionViews,
    COALESCE(am.AnswerCount, 0) as TotalAnswers,
    COALESCE(am.AcceptedCount, 0) as AcceptedAnswers,
    COALESCE(am.AvgAnswerScore, 0) as AvgAnswerScore,
    COALESCE(am.MedianScore, 0) as MedianAnswerScore,
    COALESCE(bp_gold.BadgeCount, 0) as GoldBadges,
    COALESCE(bp_silver.BadgeCount, 0) as SilverBadges,
    COALESCE(bp_bronze.BadgeCount, 0) as BronzeBadges,
    COALESCE(ce.CommentCount, 0) as RecentComments,
    COALESCE(ce.AvgCommentScore, 0) as AvgCommentScore,
    ROUND(
        (COALESCE(tqa.AvgScore, 0) * 0.3 + 
         COALESCE(am.AvgAnswerScore, 0) * 0.3 + 
         COALESCE(am.AcceptedCount::decimal / NULLIF(am.AnswerCount, 0), 0) * 100 * 0.2 +
         COALESCE(bp_gold.BadgeCount, 0) * 0.1 +
         COALESCE(ce.AvgCommentScore, 0) * 0.1), 2
    ) as EngagementScore,
    tqa.TopTags as PreferredTags,
    DENSE_RANK() OVER (ORDER BY COALESCE(tqa.QuestionCount, 0) + COALESCE(am.AnswerCount, 0) DESC) as ActivityRank,
    ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM uh.CreationDate) ORDER BY uh.Reputation DESC) as CohortRank
FROM UserHierarchy uh
LEFT JOIN TopQuestionAuthors tqa ON uh.Id = tqa.OwnerUserId
LEFT JOIN AnswerMetrics am ON uh.Id = am.AnswererUserId
LEFT JOIN BadgeProgress bp_gold ON uh.Id = bp_gold.UserId AND bp_gold.Class = 1
LEFT JOIN BadgeProgress bp_silver ON uh.Id = bp_silver.UserId AND bp_silver.Class = 2
LEFT JOIN BadgeProgress bp_bronze ON uh.Id = bp_bronze.UserId AND bp_bronze.Class = 3
LEFT JOIN (
    SELECT UserId, SUM(CommentCount) as CommentCount, AVG(AvgCommentScore) as AvgCommentScore
    FROM CommentEngagement
    GROUP BY UserId
) ce ON uh.Id = ce.UserId
WHERE uh.Level <= 2
    AND (tqa.QuestionCount IS NOT NULL OR am.AnswerCount IS NOT NULL)
ORDER BY EngagementScore DESC, uh.Reputation DESC
LIMIT 100;
