-- {"query": "17092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2527}

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.CreationDate)) * 12 + 
        EXTRACT(MONTH FROM AGE(CURRENT_DATE, u.CreationDate)) AS AccountAgeMonths,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedQuestions,
        AVG(p.Score) FILTER (WHERE p.Score > 0) AS AvgPositiveScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2), ', ') 
            FILTER (WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2) AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
BadgeAnalysis AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate,
        ARRAY_AGG(Name ORDER BY Date DESC) FILTER (WHERE Class = 1) AS GoldBadgeNames
    FROM Badges
    GROUP BY UserId
),
EditPatterns AS (
    SELECT 
        ph.UserId,
        COUNT(*) AS TotalEdits,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS ContentEdits,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (7, 8, 9)) AS Rollbacks,
        AVG(LENGTH(ph.Text)) FILTER (WHERE ph.Text IS NOT NULL) AS AvgEditSize,
        STDDEV(EXTRACT(EPOCH FROM ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate)) / 3600) AS EditTimeVariance
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
        AND ph.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY ph.UserId
),
VoteActivity AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
        SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) AS TotalBountiesStarted,
        CASE 
            WHEN COUNT(*) FILTER (WHERE v.VoteTypeId = 3) > 0 
            THEN CAST(COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS DECIMAL) / COUNT(*) FILTER (WHERE v.VoteTypeId = 3)
            ELSE NULL 
        END AS UpDownRatio
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
CommentEngagement AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(*) FILTER (WHERE c.Text LIKE '%?%') AS QuestionComments,
        COUNT(*) FILTER (WHERE c.Text ILIKE '%thank%' OR c.Text ILIKE '%thanks%') AS ThankYouComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
LinkedPosts AS (
    SELECT 
        p1.OwnerUserId AS UserId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks
    FROM Posts p1
    INNER JOIN PostLinks pl ON p1.Id = pl.PostId
    WHERE p1.OwnerUserId IS NOT NULL
    GROUP BY p1.OwnerUserId
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY um.Reputation DESC, COALESCE(ba.GoldBadges, 0) DESC) AS Rank,
    um.DisplayName,
    um.Reputation,
    UPPER(SUBSTRING(um.Location FROM 1 FOR 3)) || REPEAT('*', LEAST(LENGTH(um.Location) - 3, 5)) AS MaskedLocation,
    um.AccountAgeMonths,
    um.QuestionCount + um.AnswerCount AS TotalPosts,
    ROUND(CAST(um.AcceptedQuestions AS DECIMAL) / NULLIF(um.QuestionCount, 0) * 100, 2) AS AcceptanceRate,
    COALESCE(um.AvgPositiveScore, 0) AS AvgPositiveScore,
    COALESCE(um.MedianScore, 0) AS MedianScore,
    LEFT(COALESCE(um.TopTags, 'No tags'), 50) AS TopTagsShort,
    COALESCE(ba.GoldBadges, 0) + COALESCE(ba.SilverBadges, 0) * 0.3 + COALESCE(ba.BronzeBadges, 0) * 0.1 AS WeightedBadgeScore,
    EXTRACT(DAY FROM CURRENT_DATE - COALESCE(ba.LastBadgeDate, um.CreationDate)) AS DaysSinceLastBadge,
    COALESCE(ep.TotalEdits, 0) AS TotalEdits,
    ROUND(COALESCE(ep.ContentEdits, 0)::DECIMAL / NULLIF(ep.TotalEdits, 1) * 100, 1) AS ContentEditPercent,
    COALESCE(ep.EditTimeVariance, 0) AS EditTimeVariance,
    COALESCE(va.UpvotesGiven, 0) - COALESCE(va.DownvotesGiven, 0) AS NetVotesGiven,
    ROUND(COALESCE(va.UpDownRatio, 0), 2) AS UpDownRatio,
    COALESCE(va.TotalBountiesStarted, 0) AS TotalBountiesStarted,
    COALESCE(ce.CommentCount, 0) AS CommentCount,
    ROUND(COALESCE(ce.AvgCommentScore, 0), 2) AS AvgCommentScore,
    ROUND(COALESCE(ce.AvgCommentLength, 0), 0) AS AvgCommentLength,
    CASE 
        WHEN COALESCE(ce.CommentCount, 0) > 0 
        THEN ROUND(COALESCE(ce.ThankYouComments, 0)::DECIMAL / ce.CommentCount * 100, 1)
        ELSE 0 
    END AS ThankYouPercent,
    COALESCE(lp.LinkedPostCount, 0) AS LinkedPostCount,
    CASE 
        WHEN um.Reputation > 10000 AND COALESCE(ba.GoldBadges, 0) > 5 THEN 'Elite'
        WHEN um.Reputation > 5000 OR COALESCE(ba.GoldBadges, 0) > 2 THEN 'Expert'
        WHEN um.Reputation > 1000 THEN 'Active'
        ELSE 'Regular'
    END AS UserTier,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Posts p2 
            WHERE p2.OwnerUserId = um.Id 
                AND p2.Score > 100 
                AND p2.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
        ) THEN '🌟'
        ELSE ''
    END AS RecentHighScorer
FROM UserMetrics um
LEFT JOIN BadgeAnalysis ba ON um.Id = ba.UserId
LEFT JOIN EditPatterns ep ON um.Id = ep.UserId
LEFT JOIN VoteActivity va ON um.Id = va.UserId
LEFT JOIN CommentEngagement ce ON um.Id = ce.UserId
LEFT JOIN LinkedPosts lp ON um.Id = lp.UserId
WHERE um.QuestionCount + um.AnswerCount > 0
    AND (
        um.Reputation > 500 
        OR COALESCE(ba.GoldBadges, 0) > 0 
        OR COALESCE(ep.TotalEdits, 0) > 50
        OR EXISTS (
            SELECT 1 
            FROM Posts p3 
            WHERE p3.OwnerUserId = um.Id 
                AND p3.AcceptedAnswerId IS NOT NULL
        )
    )
ORDER BY 
    um.Reputation DESC,
    COALESCE(ba.GoldBadges, 0) DESC,
    um.QuestionCount + um.AnswerCount DESC
LIMIT 100;
