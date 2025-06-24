WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1  -- Select only questions
        AND p.CreationDate >= NOW() - INTERVAL '1 year' -- Within the last year
        AND p.ViewCount > 100 -- Only consider questions with more than 100 views
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1  -- Only questions
    GROUP BY 
        t.TagName
),
PostHistories AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        p.Title,
        pt.Name AS PostHistoryTypeName,
        COUNT(*) OVER (PARTITION BY ph.PostId) AS EditCount
    FROM 
        PostHistory ph
    JOIN 
        Posts p ON ph.PostId = p.Id
    JOIN 
        PostHistoryTypes pt ON ph.PostHistoryTypeId = pt.Id
    WHERE 
        pt.Id IN (4, 5, 6)  -- Include only relevant edit history types
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    ts.TagName,
    ts.PostCount,
    ts.TotalViews,
    ts.AvgScore,
    phs.EditCount
FROM 
    RankedPosts rp
LEFT JOIN 
    TagStats ts ON rp.Tags LIKE '%' || ts.TagName || '%'
LEFT JOIN 
    PostHistories phs ON rp.PostId = phs.PostId
WHERE 
    rp.PostRank = 1  -- Get the top-ranked post for each user
ORDER BY 
    rp.CreationDate DESC;
