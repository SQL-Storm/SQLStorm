WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
        p.OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    WHERE 
        CAST(p.CreationDate AS date) >= CAST('2024-10-01' AS date) - INTERVAL '7' DAY
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, u.DisplayName, u.Reputation, p.OwnerUserId
),
TopUsers AS (
    SELECT 
        OwnerUserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore, 
        SUM(ViewCount) AS TotalViews, 
        SUM(CommentCount) AS TotalComments
    FROM 
        Posts
    WHERE 
        CAST(CreationDate AS date) >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 5
),
PostTags AS (
    SELECT 
        p.Id, 
        t.TagName
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
    WHERE 
        p.PostTypeId = 1
),
PostActivity AS (
    SELECT 
        PostId, 
        COUNT(*) AS ActivityCount
    FROM 
        PostHistory
    GROUP BY 
        PostId
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.TotalBountyAmount,
    STRING_AGG(DISTINCT pt.TagName, ', ') AS Tags,
    pa.ActivityCount,
    tu.PostCount, 
    tu.AvgScore, 
    tu.TotalViews, 
    tu.TotalComments
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.PostId
LEFT JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.OwnerUserId
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.AnswerCount, rp.CommentCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBountyAmount, pa.ActivityCount, tu.PostCount, tu.AvgScore, tu.TotalViews, tu.TotalComments, rp.OwnerUserId
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC
LIMIT 100;