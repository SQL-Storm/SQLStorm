WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY STRING_AGG(tag.TagName, ', ') ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    CROSS JOIN 
        LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag(TagName)
    WHERE 
        p.PostTypeId = 1 -- Only Questions
        AND p.CreationDate > NOW() - INTERVAL '30 days' -- Posts created in the last 30 days
    GROUP BY 
        p.Id, p.Title, u.DisplayName, p.CreationDate, p.ViewCount, p.Score
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        OwnerDisplayName,
        CreationDate,
        ViewCount,
        Score,
        ROW_NUMBER() OVER (ORDER BY Score DESC) AS OverallRank
    FROM 
        RankedPosts
    WHERE 
        Rank = 1 -- Only the top-ranking post per tag
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.OwnerDisplayName,
    tp.CreationDate,
    tp.ViewCount,
    tp.Score
FROM 
    TopPosts tp
JOIN 
    (SELECT 
        COUNT(*) AS TotalQuestions,
        AVG(ViewCount) AS AvgViewCount
     FROM 
        RankedPosts) stats ON true
ORDER BY 
    tp.OverallRank
LIMIT 10; -- Limit for benchmarking purposes
