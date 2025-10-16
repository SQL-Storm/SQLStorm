-- {"query": "21079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1517} 

WITH ActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100 
      AND u.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 5
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QCreated,
        p.Score AS QScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(ph.Text, 'Unknown') AS CloseReason,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
            ELSE 'Open'
        END AS Status,
        LAG(p.Score) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.CreationDate) AS PrevMonthScore,
        (p.Score - LAG(p.Score) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.CreationDate)) / NULLIF(LAG(p.Score) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.CreationDate), 0) * 100 AS ScoreGrowthPct
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId 
        AND ph.PostHistoryTypeId = 10 
        AND ph.CreationDate = (SELECT MIN(CreationDate) FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId = 10)
    WHERE p.PostTypeId = 1 
      AND p.Score > 0
      AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
),
LinkedQuestions AS (
    SELECT DISTINCT 
        pl.PostId,
        pl.RelatedPostId,
        l.Name AS LinkTypeName,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS LinkRecencyRank
    FROM PostLinks pl
    INNER JOIN LinkTypes l ON pl.LinkTypeId = l.Id
    WHERE pl.LinkTypeId IN (1, 3)
      AND pl.CreationDate > CURRENT_TIMESTAMP - INTERVAL '3 months'
),
UserActivitySummary AS (
    SELECT 
        au.Id,
        au.DisplayName,
        au.Reputation,
        au.TotalPosts,
        au.Questions,
        au.Ans,
        au.AvgPostScore,
        au.RepRank,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountiesOffered,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName FROM 1 FOR 15), ', ' ORDER BY t.Count DESC) AS TopTagsAssociated
    FROM ActiveUsers au
    LEFT JOIN Votes v ON au.Id = v.UserId AND v.VoteTypeId = 8 AND v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    LEFT JOIN Badges b ON au.Id = b.UserId
    LEFT JOIN Posts p2 ON au.Id = p2.OwnerUserId AND p2.PostTypeId = 1
    LEFT JOIN (
        SELECT 
            UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS TagName,
            p.OwnerUserId,
            COUNT(*) AS Count
        FROM Posts p 
        WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
        GROUP BY TagName, p.OwnerUserId
    ) t ON au.Id = t.OwnerUserId
    GROUP BY au.Id, au.DisplayName, au.Reputation, au.TotalPosts, au.Questions, au.Ans, au.AvgPostScore, au.RepRank
)
SELECT 
    uas.DisplayName AS UserName,
    uas.Reputation,
    uas.TotalPosts,
    uas.Questions,
    uas.Ans AS NumAnswers,
    ROUND(uas.AvgPostScore::numeric, 2) AS AverageScore,
    uas.TotalBountiesOffered,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.TopTagsAssociated,
    COALESCE(qs.AnswerCount, 0) AS RecentQuestionAnswers,
    COALESCE(lq.LinkedPostCount, 0) AS RecentLinkedQuestions,
    CASE 
        WHEN uas.RepRank <= 10 THEN 'Elite'
        WHEN uas.RepRank <= 100 THEN 'Veteran'
        ELSE 'Active'
    END AS UserTier,
    GREATEST(
        COALESCE(qs.ScoreGrowthPct, 0),
        COALESCE(uas.Reputation / NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - au.CreationDate))/86400::numeric, 0), 0),
        0
    ) AS EngagementScore,
    CONCAT(
        'Score Growth: ', 
        COALESCE(qs.ScoreGrowthPct::text, 'N/A'), 
        '% | Badges: ', 
        (uas.GoldBadges + uas.SilverBadges)::text
    ) AS PerformanceSummary
FROM UserActivitySummary uas
INNER JOIN ActiveUsers au ON uas.Id = au.Id
LEFT JOIN (
    SELECT 
        qs.QuestionId,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(qs.ScoreGrowthPct) AS ScoreGrowthPct
    FROM QuestionStats qs
    LEFT JOIN Posts a ON qs.QuestionId = a.ParentId AND a.PostTypeId = 2
    WHERE qs.QCreated > CURRENT_TIMESTAMP - INTERVAL '1 month'
    GROUP BY qs.QuestionId, qs.ScoreGrowthPct
) qs ON uas.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qs.QuestionId LIMIT 1)
LEFT JOIN (
    SELECT 
        lq.PostId,
        COUNT(DISTINCT lq.RelatedPostId) AS LinkedPostCount
    FROM LinkedQuestions lq
    WHERE lq.LinkRecencyRank = 1
    GROUP BY lq.PostId
) lq ON uas.Id = (SELECT OwnerUserId FROM Posts WHERE Id = lq.PostId LIMIT 1)
WHERE uas.Questions > 2 
  OR uas.Ans > 5
  AND (uas.TopTagsAssociated IS NOT NULL OR uas.GoldBadges > 0)
ORDER BY uas.Reputation DESC, EngagementScore DESC
LIMIT 50;
