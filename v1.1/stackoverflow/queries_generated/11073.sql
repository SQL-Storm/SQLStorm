-- {"query": "11073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 701} 

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
        p.CreationDate > NOW() - INTERVAL '30 days' 
        AND p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore
    FROM 
        Posts
    WHERE 
        CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        UserId
    HAVING 
        COUNT(Id) > 10
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
        PostId, 
        COUNT(*) AS ActivityCount, 
        AVG(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteRate
    FROM 
        Votes 
    GROUP BY 
        PostId
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
