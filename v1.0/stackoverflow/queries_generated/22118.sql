WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.OwnerUserId, 
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserTotalPosts
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 -- Considering only questions
        AND p.Title IS NOT NULL
),
BadgedUsers AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
    HAVING 
        COUNT(b.Id) > 0
),
QuestionStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS QuestionCount,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        AVG(COALESCE(p.Score, 0)) AS AvgScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 -- Questions only
    GROUP BY 
        p.OwnerUserId
),
FinalReport AS (
    SELECT 
        u.DisplayName,
        u.Reputation,
        qs.QuestionCount,
        qs.TotalViews,
        qs.AvgScore,
        COALESCE(bu.BadgeCount, 0) AS BadgeCount,
        CASE 
            WHEN qs.AvgScore IS NULL THEN 'No Score'
            WHEN qs.AvgScore > 5 THEN 'High Achiever'
            ELSE 'Needs Improvement'
        END AS PerformanceCategory
    FROM 
        Users u
    LEFT JOIN 
        QuestionStats qs ON u.Id = qs.OwnerUserId
    LEFT JOIN 
        BadgedUsers bu ON u.Id = bu.UserId
    WHERE 
        u.Reputation > (SELECT AVG(Reputation) FROM Users) -- Only above average reputation
)
SELECT 
    fr.DisplayName,
    fr.Reputation,
    fr.QuestionCount,
    fr.TotalViews,
    fr.AvgScore,
    fr.BadgeCount,
    fr.PerformanceCategory
FROM 
    FinalReport fr
WHERE 
    fr.QuestionCount BETWEEN 5 AND 15 
    AND fr.TotalViews IS NOT NULL 
ORDER BY 
    fr.AvgScore DESC NULLS LAST
LIMIT 10;

-- Also evaluating post links with bizarre link types and closure reasons
SELECT 
    p.Title AS PostTitle, 
    pl.LinkTypeId, 
    CASE 
        WHEN pl.LinkTypeId = 3 THEN 'Duplicate'
        WHEN pl.LinkTypeId = 1 THEN 'Linked'
        ELSE 'Unknown Link Type'
    END AS LinkTypeDescription
FROM 
    PostLinks pl
JOIN 
    Posts p ON pl.PostId = p.Id
WHERE 
    EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.PostId = pl.RelatedPostId 
        AND ph.PostHistoryTypeId IN (10, 11) -- Times post closed/reopened
    )
ORDER BY 
    p.CreationDate DESC
LIMIT 5;
