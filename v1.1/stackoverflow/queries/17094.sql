WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        EXTRACT(YEAR FROM AGE(CAST('2024-10-01' AS DATE), u.CreationDate)) AS YearsActive,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(AVG(p.Score), 0) AS AvgScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        STRING_AGG(DISTINCT SUBSTRING(UPPER(COALESCE(u.Location, 'Unknown')) FROM 1 FOR 3), '|' ORDER BY SUBSTRING(UPPER(COALESCE(u.Location, 'Unknown')) FROM 1 FOR 3)) AS LocationCode
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
        AND u.CreationDate < CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
        AVG(p.Score) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        MAX(p.Score) - MIN(p.Score) AS ScoreRange,
        STDDEV_SAMP(p.Score) AS ScoreStdDev,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS PopularityRank,
        DENSE_RANK() OVER (ORDER BY AVG(p.Score) DESC NULLS LAST) AS QualityRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
        AND p.Score >= 0
        AND t.Count > 100
    GROUP BY t.TagName, t.Count
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        c.CommentActivity,
        v.VoteActivity,
        ph.EditCount,
        CASE 
            WHEN p.ViewCount > 0 THEN (CAST(p.Score AS DECIMAL) / NULLIF(p.ViewCount, 0)) * 1000
            ELSE 0 
        END AS EngagementRatio,
        NTILE(10) OVER (ORDER BY p.Score DESC NULLS LAST) AS ScoreDecile,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts p
    LEFT JOIN (
        SELECT c.PostId, COUNT(*) AS CommentActivity
        FROM Comments c
        WHERE c.Score > 0
        GROUP BY c.PostId
    ) c ON c.PostId = p.Id
    LEFT JOIN (
        SELECT v.PostId, COUNT(DISTINCT v.VoteTypeId) AS VoteActivity
        FROM Votes v
        WHERE v.VoteTypeId IN (2, 3, 5)
        GROUP BY v.PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN (
        SELECT ph.PostId, COUNT(*) AS EditCount
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4, 5, 6)
        GROUP BY ph.PostId
    ) ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR
        AND p.ClosedDate IS NULL
)
SELECT 
    um.DisplayName,
    um.Location,
    um.Reputation,
    (CAST(um.YearsActive AS VARCHAR) || ' years') AS Tenure,
    um.TotalPosts,
    ROUND(CAST(um.AvgScore AS DECIMAL), 2) AS AvgPostScore,
    (CAST(um.GoldBadges AS VARCHAR) || '/' || CAST(um.BadgeCount AS VARCHAR)) AS BadgeRatio,
    COALESCE(ta.TagName, 'No Popular Tags') AS TopTag,
    ta.PopularityRank AS TagRank,
    ROUND(CAST(COALESCE(ta.AvgPostScore, 0) AS DECIMAL), 2) AS TagAvgScore,
    pe.Title AS BestPost,
    pe.Score AS BestPostScore,
    pe.EngagementRatio,
    pe.ScoreDecile,
    CASE 
        WHEN pe.Score > COALESCE(pe.PrevPostScore, 0) AND pe.Score > COALESCE(pe.NextPostScore, 0) THEN 'Peak Performance'
        WHEN pe.Score > COALESCE(pe.PrevPostScore, 0) THEN 'Improving'
        WHEN pe.Score < COALESCE(pe.PrevPostScore, 0) THEN 'Declining'
        ELSE 'Stable'
    END AS PerformanceTrend,
    CASE
        WHEN um.Reputation > 10000 AND um.GoldBadges > 5 THEN 'Elite'
        WHEN um.Reputation > 5000 OR um.GoldBadges > 2 THEN 'Expert'
        WHEN um.Reputation > 2000 THEN 'Experienced'
        ELSE 'Active'
    END AS UserTier,
    COALESCE(NULLIF(TRIM(BOTH FROM um.LocationCode), ''), 'N/A') AS LocationAbbrev
FROM UserMetrics um
LEFT JOIN LATERAL (
    SELECT pe.*
    FROM PostEngagement pe
    WHERE pe.OwnerUserId = um.Id
    ORDER BY pe.Score DESC
    FETCH FIRST 1 ROW ONLY
) pe ON true
LEFT JOIN LATERAL (
    SELECT ta.*
    FROM TagAnalysis ta
    WHERE EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = um.Id
            AND p.Tags LIKE '%' || '<' || ta.TagName || '>' || '%'
    )
    ORDER BY ta.PopularityRank
    FETCH FIRST 1 ROW ONLY
) ta ON true
WHERE um.TotalPosts > 10
    AND (COALESCE(pe.Score, 0) > 10 OR um.BadgeCount > 20)
    AND um.DisplayName IS NOT NULL
    AND LENGTH(um.DisplayName) > 0
ORDER BY 
    COALESCE(pe.EngagementRatio, 0) DESC,
    um.Reputation DESC,
    um.GoldBadges DESC
FETCH FIRST 100 ROWS ONLY;