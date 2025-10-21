WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            PostId, 
            BountyAmount
        FROM Votes 
        WHERE VoteTypeId IN (8, 9)
    ) v ON p.Id = v.PostId
    WHERE p.CreationDate > DATE '2024-10-01' - INTERVAL '30 days'
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        OwnerUserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore,
        SUM(ViewCount) AS TotalViews
    FROM Posts
    WHERE CreationDate > DATE '2024-10-01' - INTERVAL '30 days'
    GROUP BY OwnerUserId
    HAVING COUNT(Id) > 5
),
PostTags AS (
    SELECT 
        p.Id,
        -- Normalize tags into a proper array of text values
        REGEXP_REPLACE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '\\|', ',', 'g') AS TagList
    FROM Posts p
),
TaggedPosts AS (
    SELECT 
        pt.Id,
        t.TagName
    FROM PostTags pt
    CROSS JOIN LATERAL UNNEST(string_to_array(pt.TagList, ',')) AS TagId
    JOIN Tags t ON CAST(TagId AS INTEGER) = t.Id
),
PostActivity AS (
    SELECT 
        p.Id,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
)
SELECT 
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.TotalBounty,
    tp.PostCount,
    tp.AvgScore,
    tp.TotalViews,
    pa.EditCount,
    pa.CommentCount,
    STRING_AGG(t.TagName, ', ') AS Tags
FROM RecentPosts rp
JOIN TopUsers tp ON rp.Id = tp.OwnerUserId
JOIN PostActivity pa ON rp.Id = pa.Id
LEFT JOIN TaggedPosts t ON rp.Id = t.Id
GROUP BY rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBounty, tp.PostCount, tp.AvgScore, tp.TotalViews, pa.EditCount, pa.CommentCount
ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.TotalBounty DESC
LIMIT 10;