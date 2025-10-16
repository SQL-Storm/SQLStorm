WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        u.DisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
        AND p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        p.OwnerUserId AS UserId, 
        COUNT(p.Id) AS PostCount, 
        AVG(p.Score) AS AvgScore
    FROM 
        Posts p
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
    GROUP BY 
        p.OwnerUserId
    HAVING 
        COUNT(p.Id) > 10
),
PostTags AS (
    SELECT 
        p.Id, 
        t.TagName
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.PostTypeId = 1
),
PostActivity AS (
    SELECT 
        v.PostId, 
        COUNT(*) AS ActivityCount, 
        AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) AS UpvoteRate
    FROM 
        Votes v
    GROUP BY 
        v.PostId
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.DisplayName, 
    rp.Reputation, 
    rp.TotalBounty, 
    STRING_AGG(DISTINCT pt.TagName, ', ') AS Tags,
    pa.ActivityCount,
    pa.UpvoteRate,
    tu.PostCount,
    tu.AvgScore
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.PostId
LEFT JOIN 
    TopUsers tu ON rp.Id = tu.UserId
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.AnswerCount, rp.CommentCount, rp.DisplayName, rp.Reputation, rp.TotalBounty, pa.ActivityCount, pa.UpvoteRate, tu.PostCount, tu.AvgScore
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC
LIMIT 10;