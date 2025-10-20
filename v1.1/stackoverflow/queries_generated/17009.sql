-- {"query": "17009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 23350, "output_tokens": 22617} 

WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score IS NOT NULL) AS MedianScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS UniqueTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopContributors AS (
    SELECT 
        uam.*,
        DENSE_RANK() OVER (ORDER BY uam.Reputation DESC, uam.PostCount DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY CASE 
            WHEN uam.Reputation >= 10000 THEN 'Expert'
            WHEN uam.Reputation >= 1000 THEN 'Advanced'
            WHEN uam.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END ORDER BY uam.AvgPostScore DESC NULLS LAST) AS TierRank
    FROM UserActivityMetrics uam
    WHERE uam.PostCount > 0
),
QuestionAnalysis AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate AS QuestionDate,
        COALESCE(q.ClosedDate IS NOT NULL, FALSE) AS IsClosed,
        MAX(a.Score) AS BestAnswerScore,
        MIN(a.CreationDate) AS FirstAnswerDate,
        COUNT(DISTINCT a.Id) AS ActualAnswerCount,
        AVG(a.Score) FILTER (WHERE a.Score > 0) AS AvgPositiveAnswerScore,
        BOOL_OR(a.Id = q.AcceptedAnswerId) AS HasAcceptedAnswer,
        STRING_AGG(DISTINCT au.DisplayName, ' | ' ORDER BY a.Score DESC) FILTER (WHERE a.Score >= 5) AS TopAnswerers
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    WHERE q.PostTypeId = 1 
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount, q.CreationDate, q.ClosedDate
),
BadgePatterns AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) FILTER (WHERE b.TagBased = B'1') AS TagBadges,
        ARRAY_AGG(b.Name ORDER BY b.Date DESC) FILTER (WHERE b.Class = 1) AS GoldBadgeNames,
        LAG(COUNT(*), 1, 0) OVER (PARTITION BY b.UserId ORDER BY DATE_TRUNC('month', b.Date)) AS PrevMonthBadges
    FROM Badges b
    GROUP BY b.UserId, DATE_TRUNC('month', b.Date)
)
SELECT 
    tc.DisplayName,
    tc.Reputation,
    tc.ReputationRank,
    CASE 
        WHEN tc.Reputation >= 10000 THEN 'Expert'
        WHEN tc.Reputation >= 1000 THEN 'Advanced'
        WHEN tc.Reputation >= 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    tc.PostCount,
    tc.QuestionCount,
    tc.AnswerCount,
    ROUND(tc.AvgPostScore::NUMERIC, 2) AS AvgPostScore,
    tc.MedianScore,
    COALESCE(bp.TotalBadges, 0) AS TotalBadges,
    COALESCE(bp.GoldBadges, 0) AS GoldBadges,
    ARRAY_TO_STRING(bp.GoldBadgeNames, ', ') AS GoldBadgeList,
    COUNT(DISTINCT qa.QuestionId) AS QuestionsWithActivity,
    SUM(CASE WHEN qa.HasAcceptedAnswer THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
    AVG(qa.ViewCount) FILTER (WHERE qa.ViewCount > 100) AS AvgViewsPopularQuestions,
    MAX(qa.BestAnswerScore) AS HighestAnswerScore,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY qa.QuestionScore) AS Q75_QuestionScore,
    SUM(CASE WHEN qa.IsClosed THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(DISTINCT qa.QuestionId), 0) * 100 AS ClosedQuestionPercentage,
    STRING_AGG(DISTINCT qa.Title, ' || ' ORDER BY qa.QuestionScore DESC) FILTER (WHERE qa.QuestionScore >= 10) AS TopQuestions,
    COALESCE(
        (SELECT COUNT(DISTINCT c.Id) 
         FROM Comments c 
         WHERE c.UserId = tc.Id 
            AND c.Score > 0
            AND EXISTS (
                SELECT 1 
                FROM Posts p 
                WHERE p.Id = c.PostId 
                    AND p.Score > 20
            )
        ), 0
    ) AS HighValueComments,
    CASE 
        WHEN tc.UniqueTags LIKE '%javascript%' OR tc.UniqueTags LIKE '%python%' THEN 'Mainstream Tech'
        WHEN tc.UniqueTags LIKE '%sql%' OR tc.UniqueTags LIKE '%database%' THEN 'Data Professional'
        WHEN tc.UniqueTags IS NULL THEN 'No Tags'
        ELSE 'Other Specialization'
    END AS TechCategory,
    SUBSTRING(tc.UniqueTags FROM 1 FOR 100) AS TagSample
FROM TopContributors tc
LEFT JOIN LATERAL (
    SELECT * FROM BadgePatterns WHERE UserId = tc.Id LIMIT 1
) bp ON TRUE
LEFT JOIN QuestionAnalysis qa ON tc.Id = qa.OwnerUserId
WHERE tc.ReputationRank <= 100
    OR (tc.TierRank <= 5 AND tc.PostCount >= 10)
GROUP BY 
    tc.Id, tc.DisplayName, tc.Reputation, tc.ReputationRank, tc.PostCount, 
    tc.QuestionCount, tc.AnswerCount, tc.AvgPostScore, tc.MedianScore,
    tc.TotalViews, tc.UniqueTags, tc.TierRank,
    bp.TotalBadges, bp.GoldBadges, bp.SilverBadges, bp.BronzeBadges,
    bp.TagBadges, bp.GoldBadgeNames
HAVING COUNT(DISTINCT qa.QuestionId) > 0 
    OR tc.AnswerCount > 5
    OR COALESCE(bp.TotalBadges, 0) > 10
ORDER BY 
    tc.ReputationRank ASC,
    COALESCE(bp.GoldBadges, 0) DESC,
    tc.AvgPostScore DESC NULLS LAST
LIMIT 50;
