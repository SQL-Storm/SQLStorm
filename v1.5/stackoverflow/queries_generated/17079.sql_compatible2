WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        EXTRACT(year FROM AGE(DATE '2024-10-01', u.CreationDate)) AS YearsActive,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL), 0) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
TagExperts AS (
    SELECT 
        t.TagName,
        p.OwnerUserId,
        COUNT(*) AS TagPostCount,
        SUM(p.Score) AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC, COUNT(*) DESC) AS TagRank,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS GlobalTagPopularityRank
    FROM Tags t
    CROSS JOIN LATERAL (
        SELECT * FROM Posts 
        WHERE Tags LIKE '%' || '<' || t.TagName || '>' || '%'
        AND OwnerUserId IS NOT NULL
    ) p
    GROUP BY t.TagName, p.OwnerUserId
),
EditPatterns AS (
    SELECT 
        ph.UserId,
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 8) AS RollbackCount,
        FIRST_VALUE(ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) AS FirstEditDate,
        LAST_VALUE(ph.CreationDate) OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastEditDate,
        CASE 
            WHEN EXTRACT(HOUR FROM ph.CreationDate) BETWEEN 6 AND 12 THEN 'Morning'
            WHEN EXTRACT(HOUR FROM ph.CreationDate) BETWEEN 12 AND 18 THEN 'Afternoon'
            WHEN EXTRACT(HOUR FROM ph.CreationDate) BETWEEN 18 AND 24 THEN 'Evening'
            ELSE 'Night'
        END AS EditTimeOfDay
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, ph.PostId, ph.CreationDate
),
BadgeAchievements AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) FILTER (WHERE b.TagBased = '1') AS TagBadges,
        LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS PreviousBadgeDate,
        b.Date - LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS DaysSincePreviousBadge
    FROM Badges b
    GROUP BY b.UserId, b.Date
)
SELECT 
    um.DisplayName,
    um.Reputation,
    UPPER(SUBSTRING(um.Location FROM 1 FOR 3)) || LOWER(SUBSTRING(um.Location FROM 4)) AS FormattedLocation,
    um.YearsActive || ' years' AS Tenure,
    um.PostCount,
    ROUND(um.AvgPostScore, 2) AS AvgScore,
    um.MedianPostScore,
    CASE 
        WHEN um.QuestionCount > um.AnswerCount * 2 THEN 'Asker'
        WHEN um.AnswerCount > um.QuestionCount * 2 THEN 'Answerer'
        ELSE 'Balanced'
    END AS UserType,
    COALESCE(te.TagName, 'No Expertise') AS TopExpertiseTag,
    COALESCE(te.TagScore, 0) AS ExpertiseScore,
    COALESCE(
        (SELECT STRING_AGG(c.Text, ' | ' ORDER BY c.Score DESC)
         FROM Comments c 
         WHERE c.UserId = um.Id 
         AND c.Score > 5
         AND LENGTH(c.Text) > 50
         LIMIT 3), 
        'No popular comments'
    ) AS TopComments,
    COALESCE(ba.GoldBadges, 0) + COALESCE(ba.SilverBadges, 0) * 0.5 + COALESCE(ba.BronzeBadges, 0) * 0.25 AS WeightedBadgeScore,
    EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = um.Id 
        AND p2.AcceptedAnswerId IS NOT NULL
        AND p2.Score > 100
    ) AS HasHighScoringAcceptedAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT pl.RelatedPostId)
         FROM PostLinks pl
         JOIN Posts p3 ON pl.PostId = p3.Id
         WHERE p3.OwnerUserId = um.Id
         AND pl.LinkTypeId = 3),
        0
    ) AS LinkedDuplicateCount,
    CASE 
        WHEN um.Reputation > 10000 AND um.PostCount > 500 THEN 'Elite'
        WHEN um.Reputation > 5000 OR um.PostCount > 200 THEN 'Veteran'
        WHEN um.Reputation > 2000 OR um.PostCount > 50 THEN 'Regular'
        ELSE 'Contributor'
    END AS UserTier,
    COALESCE(ep.EditCount, 0) AS TotalEdits,
    GREATEST(
        0,
        (SELECT MAX(v.BountyAmount) 
         FROM Votes v 
         JOIN Posts p4 ON v.PostId = p4.Id
         WHERE p4.OwnerUserId = um.Id 
         AND v.VoteTypeId = 8)
    ) AS MaxBountyOffered
FROM UserMetrics um
LEFT JOIN LATERAL (
    SELECT * FROM TagExperts 
    WHERE OwnerUserId = um.Id 
    AND TagRank = 1
    ORDER BY TagScore DESC
    LIMIT 1
) te ON TRUE
LEFT JOIN LATERAL (
    SELECT * FROM BadgeAchievements
    WHERE UserId = um.Id
    ORDER BY GoldBadges DESC, SilverBadges DESC, BronzeBadges DESC
    LIMIT 1
) ba ON TRUE
LEFT JOIN LATERAL (
    SELECT SUM(EditCount) AS EditCount
    FROM EditPatterns
    WHERE UserId = um.Id
) ep ON TRUE
WHERE um.PostCount > 10
AND (um.Location IS NULL OR um.Location NOT LIKE '%test%')
ORDER BY 
    um.Reputation DESC,
    um.TotalPostScore DESC,
    um.PostCount DESC
LIMIT 100;