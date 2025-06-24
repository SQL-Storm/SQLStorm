WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 -- Only questions
        AND p.CreationDate >= NOW() - INTERVAL '1 year' -- Posts from the last year
),
AggregateData AS (
    SELECT 
        rp.OwnerDisplayName,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(rp.Score) AS TotalScore,
        SUM(rp.ViewCount) AS TotalViews
    FROM 
        RankedPosts rp
    WHERE 
        rp.PostRank <= 5 -- Top 5 posts per user
    GROUP BY 
        rp.OwnerDisplayName
),
ClosedPosts AS (
    SELECT 
        p.OwnerUserId,
        COUNT(ph.Id) AS TotalClosed
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY 
        p.OwnerUserId
)
SELECT 
    ad.OwnerDisplayName,
    ad.TotalPosts,
    ad.TotalScore,
    ad.TotalViews,
    COALESCE(cp.TotalClosed, 0) AS TotalClosedPosts
FROM 
    AggregateData ad
LEFT JOIN 
    ClosedPosts cp ON ad.OwnerDisplayName = (SELECT DisplayName FROM Users WHERE Id = cp.OwnerUserId)
ORDER BY 
    ad.TotalScore DESC, ad.TotalPosts DESC;
