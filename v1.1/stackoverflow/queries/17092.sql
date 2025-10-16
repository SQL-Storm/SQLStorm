WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        (EXTRACT(YEAR FROM AGE(CAST('2024-10-01' AS date), u.CreationDate)) * 12 + 
         EXTRACT(MONTH FROM AGE(CAST('2024-10-01' AS date), u.CreationDate))) AS AccountAgeMonths,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedQuestions,
        AVG(p.Score) FILTER (WHERE p.Score > 0) AS AvgPositiveScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2)), ', ') 
            FILTER (WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2) AS TopTags,
        u.CreationDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '3 years'
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
-- compute per-user edit intervals in a separate CTE to avoid using window functions inside aggregates
EditIntervals AS (
    SELECT
        ph.UserId,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate))) / 3600.0 AS HoursSincePrev,
        LENGTH(ph.Text) AS EditLength,
        ph.PostHistoryTypeId
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
),
EditPatterns AS (
    SELECT 
        ei.UserId,
        COUNT(*) AS TotalEdits,
        COUNT(*) FILTER (WHERE ei.PostHistoryTypeId IN (4, 5, 6)) AS ContentEdits,
        COUNT(*) FILTER (WHERE ei.PostHistoryTypeId IN (7, 8, 9)) AS Rollbacks,
        AVG(ei.EditLength) FILTER (WHERE ei.EditLength IS NOT NULL) AS AvgEditSize,
        AVG(ei.HoursSincePrev) FILTER (WHERE ei.HoursSincePrev IS NOT NULL) AS EditTimeVariance
    FROM EditIntervals ei
    GROUP BY ei.UserId
),
VoteActivity AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
        SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) AS TotalBountiesStarted,
        CASE 
            WHEN COUNT(*) FILTER (WHERE v.VoteTypeId = 3) > 0 
            THEN (CAST(COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS DECIMAL)) / (COUNT(*) FILTER (WHERE v.VoteTypeId = 3))
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
        COUNT(*) FILTER (WHERE LOWER(c.Text) LIKE '%thank%' OR LOWER(c.Text) LIKE '%thanks%') AS ThankYouComments
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
    (UPPER(SUBSTRING(um.Location FROM 1 FOR 3)) || REPEAT('*', LEAST(GREATEST(LENGTH(um.Location) - 3, 0), 5))) AS MaskedLocation,
    um.AccountAgeMonths,
    (um.QuestionCount + um.AnswerCount) AS TotalPosts,
    ROUND( (CAST(um.AcceptedQuestions AS DECIMAL) / NULLIF(um.QuestionCount, 0)) * 100, 2) AS AcceptanceRate,
    COALESCE(um.AvgPositiveScore, 0) AS AvgPositiveScore,
    COALESCE(um.MedianScore, 0) AS MedianScore,
    LEFT(COALESCE(um.TopTags, 'No tags'), 50) AS TopTagsShort,
    (COALESCE(ba.GoldBadges, 0) + COALESCE(ba.SilverBadges, 0) * 0.3 + COALESCE(ba.BronzeBadges, 0) * 0.1) AS WeightedBadgeScore,
    EXTRACT(DAY FROM (CAST('2024-10-01' AS date) - COALESCE(ba.LastBadgeDate, um.CreationDate))) AS DaysSinceLastBadge,
    COALESCE(ep.TotalEdits, 0) AS TotalEdits,
    ROUND( (CAST(COALESCE(ep.ContentEdits, 0) AS DECIMAL) / NULLIF(ep.TotalEdits, 0)) * 100, 1) AS ContentEditPercent,
    COALESCE(ep.EditTimeVariance, 0) AS EditTimeVariance,
    (COALESCE(va.UpvotesGiven, 0) - COALESCE(va.DownvotesGiven, 0)) AS NetVotesGiven,
    ROUND(COALESCE(va.UpDownRatio, 0), 2) AS UpDownRatio,
    COALESCE(va.TotalBountiesStarted, 0) AS TotalBountiesStarted,
    COALESCE(ce.CommentCount, 0) AS CommentCount,
    ROUND(COALESCE(ce.AvgCommentScore, 0), 2) AS AvgCommentScore,
    ROUND(COALESCE(ce.AvgCommentLength, 0), 0) AS AvgCommentLength,
    CASE 
        WHEN COALESCE(ce.CommentCount, 0) > 0 
        THEN ROUND( (CAST(COALESCE(ce.ThankYouComments, 0) AS DECIMAL) / ce.CommentCount) * 100, 1)
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
                AND p2.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '6 months'
        ) THEN '*' 
        ELSE '' 
    END AS RecentHighScorer,
    um.Id
FROM UserMetrics um
LEFT JOIN BadgeAnalysis ba ON um.Id = ba.UserId
LEFT JOIN EditPatterns ep ON um.Id = ep.UserId
LEFT JOIN VoteActivity va ON um.Id = va.UserId
LEFT JOIN CommentEngagement ce ON um.Id = ce.UserId
LEFT JOIN LinkedPosts lp ON um.Id = lp.UserId
WHERE (um.QuestionCount + um.AnswerCount) > 0
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
GROUP BY
    um.Id,
    um.DisplayName,
    um.Reputation,
    um.Location,
    um.AccountAgeMonths,
    um.QuestionCount,
    um.AnswerCount,
    um.AcceptedQuestions,
    um.AvgPositiveScore,
    um.MedianScore,
    um.TopTags,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.LastBadgeDate,
    um.CreationDate,
    ep.TotalEdits,
    ep.ContentEdits,
    ep.EditTimeVariance,
    va.UpvotesGiven,
    va.DownvotesGiven,
    va.UpDownRatio,
    va.TotalBountiesStarted,
    ce.CommentCount,
    ce.AvgCommentScore,
    ce.AvgCommentLength,
    ce.ThankYouComments,
    lp.LinkedPostCount,
    um.Id
ORDER BY 
    um.Reputation DESC,
    COALESCE(ba.GoldBadges, 0) DESC,
    (um.QuestionCount + um.AnswerCount) DESC
LIMIT 100;