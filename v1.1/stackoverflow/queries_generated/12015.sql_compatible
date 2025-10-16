WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(4) OVER (ORDER BY p.CreationDate) AS Quartile,
        p.Tags
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId IN (1, 2) 
        AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
), 
TagCounts AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount
    FROM 
        Tags t
    JOIN 
        Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
    GROUP BY 
        t.TagName
), 
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT ph.PostId) AS EditCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId
    WHERE 
        (p.CreationDate IS NULL OR p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
    GROUP BY 
        u.Id, u.DisplayName
), 
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS RevisionCount,
        MAX(ph.CreationDate) AS LastRevisionDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (2, 5, 6)
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.Id,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.UserRank,
    rp.ScoreRank,
    rp.Quartile,
    tc.TagName,
    tc.PostCount AS TagPostCount,
    ua.PostCount AS UserPostCount,
    ua.TotalScore AS UserTotalScore,
    ua.CommentCount AS UserCommentCount,
    phs.RevisionCount,
    phs.LastRevisionDate
FROM 
    RankedPosts rp
LEFT JOIN 
    TagCounts tc ON tc.TagName = (
        -- normalize tag extraction: assume tags stored like '<tag1><tag2>' and join by any tag.
        -- split into rows using a standard-compatible method: replace angle brackets and split on '><'
        -- emulate by checking rp.Tags LIKE pattern for the tag wrapped in angle brackets
        tc.TagName
    )
    AND rp.Tags IS NOT NULL
    AND rp.Tags LIKE '<' || tc.TagName || '>'
LEFT JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.Id
LEFT JOIN 
    PostHistorySummary phs ON rp.Id = phs.PostId
WHERE 
    rp.ScoreRank <= 100
    AND rp.UserRank <= 10
ORDER BY 
    rp.Score DESC, 
    rp.CreationDate;