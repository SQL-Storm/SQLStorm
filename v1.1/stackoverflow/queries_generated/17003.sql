-- {"query": "17003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 9340, "output_tokens": 9541} 

WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score > 0) AS MedianPositiveScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopContributors AS (
    SELECT 
        uam.*,
        DENSE_RANK() OVER (ORDER BY uam.Reputation DESC, uam.PostCount DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY CASE 
            WHEN uam.Reputation >= 10000 THEN 'Expert'
            WHEN uam.Reputation >= 1000 THEN 'Advanced'
            WHEN uam.Reputation >= 100 THEN 'Regular'
            ELSE 'Beginner'
        END ORDER BY uam.AvgPostScore DESC NULLS LAST) AS TierRank
    FROM UserActivityMetrics uam
    WHERE uam.PostCount > 0
),
BadgeAnalysis AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        LISTAGG(DISTINCT b.Name, ' | ') WITHIN GROUP (ORDER BY b.Class, b.Name) AS BadgeList
    FROM Badges b
    WHERE b.TagBased = '0'
    GROUP BY b.UserId
),
QuestionEngagement AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        COALESCE(q.ClosedDate IS NOT NULL, FALSE) AS IsClosed,
        COUNT(DISTINCT a.Id) AS ActualAnswerCount,
        MAX(a.Score) AS BestAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = q.Id OR c.PostId IN (
                SELECT Id FROM Posts WHERE ParentId = q.Id
            )
        ) AS TotalComments,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END AS Status
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount, 
             q.AnswerCount, q.FavoriteCount, q.ClosedDate, q.AcceptedAnswerId
)
SELECT 
    tc.Id AS UserId,
    COALESCE(tc.DisplayName, 'Anonymous') AS DisplayName,
    tc.Reputation,
    tc.ReputationRank,
    CASE 
        WHEN tc.Reputation >= 10000 THEN 'Expert'
        WHEN tc.Reputation >= 1000 THEN 'Advanced'
        WHEN tc.Reputation >= 100 THEN 'Regular'
        ELSE 'Beginner'
    END AS UserTier,
    tc.TierRank,
    tc.QuestionCount,
    tc.AnswerCount,
    ROUND(tc.AnswerCount::NUMERIC / NULLIF(tc.QuestionCount, 0), 2) AS AnswerToQuestionRatio,
    tc.AvgPostScore,
    tc.MedianPositiveScore,
    COALESCE(ba.TotalBadges, 0) AS TotalBadges,
    COALESCE(ba.GoldBadges, 0) AS GoldBadges,
    COALESCE(ba.SilverBadges, 0) AS SilverBadges,
    COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
    EXTRACT(DAYS FROM (CURRENT_DATE - ba.LastBadgeDate)) AS DaysSinceLastBadge,
    SUBSTRING(COALESCE(ba.BadgeList, 'No badges'), 1, 100) AS BadgeSample,
    (
        SELECT COUNT(DISTINCT v.Id)
        FROM Votes v
        WHERE v.UserId = tc.Id 
            AND v.VoteTypeId IN (2, 3)
            AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ) AS RecentVotesCast,
    qe_stats.TotalQuestions,
    qe_stats.AcceptedQuestions,
    qe_stats.AvgQuestionScore,
    qe_stats.TotalViews,
    qe_stats.EngagementScore,
    CASE 
        WHEN tc.AllTags IS NULL THEN NULL
        WHEN LENGTH(tc.AllTags) > 50 THEN SUBSTRING(tc.AllTags, 1, 47) || '...'
        ELSE tc.AllTags
    END AS TopTags,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.UserId = tc.Id 
                AND ph.PostHistoryTypeId IN (10, 12, 14)
                AND ph.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
        ) THEN 'Moderator Activity'
        WHEN tc.Reputation > 5000 AND qe_stats.AcceptedQuestions > 10 THEN 'Top Contributor'
        WHEN tc.AnswerCount > tc.QuestionCount * 2 THEN 'Helper'
        WHEN tc.QuestionCount > tc.AnswerCount * 2 THEN 'Asker'
        ELSE 'Balanced'
    END AS UserProfile
FROM TopContributors tc
LEFT JOIN BadgeAnalysis ba ON tc.Id = ba.UserId
LEFT JOIN LATERAL (
    SELECT 
        COUNT(*) AS TotalQuestions,
        COUNT(*) FILTER (WHERE qe.Status = 'Accepted') AS AcceptedQuestions,
        AVG(qe.QuestionScore) AS AvgQuestionScore,
        SUM(qe.ViewCount) AS TotalViews,
        SUM(
            COALESCE(qe.QuestionScore, 0) * 10 + 
            COALESCE(qe.ViewCount, 0) * 0.001 + 
            COALESCE(qe.ActualAnswerCount, 0) * 5 +
            COALESCE(qe.FavoriteCount, 0) * 20
        ) AS EngagementScore
    FROM QuestionEngagement qe
    WHERE qe.OwnerUserId = tc.Id
) qe_stats ON TRUE
WHERE tc.ReputationRank <= 100
    OR (tc.TierRank <= 5 AND tc.Reputation >= 500)
    OR ba.GoldBadges > 0
ORDER BY 
    tc.ReputationRank ASC,
    qe_stats.EngagementScore DESC NULLS LAST,
    ba.TotalBadges DESC NULLS LAST
LIMIT 100;
