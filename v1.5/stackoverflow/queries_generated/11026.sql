-- {"query": "11026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 716} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId 
        AND v.VoteTypeId IN (8, 9)
    WHERE 
        p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        OwnerUserId, 
        COUNT(Id) AS TotalPosts, 
        AVG(Score) AS AvgScore, 
        SUM(ViewCount) AS TotalViews, 
        SUM(AnswerCount) AS TotalAnswers
    FROM 
        Posts
    WHERE 
        CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        OwnerUserId
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
PostCommentCounts AS (
    SELECT 
        PostId, 
        COUNT(Id) AS CommentCount
    FROM 
        Comments
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
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.TotalBounty, 
    STRING_AGG(DISTINCT pt.TagName, ', ') AS Tags, 
    pc.CommentCount,
    tu.TotalPosts, 
    tu.AvgScore, 
    tu.TotalViews, 
    tu.TotalAnswers
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    PostCommentCounts pc ON rp.Id = pc.PostId
LEFT JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.OwnerUserId
WHERE 
    rp.Score > 0
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.AnswerCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBounty, tu.TotalPosts, tu.AvgScore, tu.TotalViews, tu.TotalAnswers, pc.CommentCount
ORDER BY 
    rp.Score DESC, rp.ViewCount DESC, rp.AnswerCount DESC, rp.TotalBounty DESC
LIMIT 10;
