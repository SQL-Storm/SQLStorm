-- {"query": "11009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 617} 

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
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    WHERE p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        OwnerUserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore, 
        SUM(ViewCount) AS TotalViews, 
        SUM(AnswerCount) AS TotalAnswers
    FROM Posts
    WHERE CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY OwnerUserId
    HAVING COUNT(Id) > 5
),
PostTags AS (
    SELECT 
        p.Id, 
        t.TagName, 
        COUNT(*) AS TagCount
    FROM Posts p
    JOIN Tags t ON p.Id = t.ExcerptPostId
    GROUP BY p.Id, t.TagName
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
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.TotalBounty,
    pt.TagName,
    pt.TagCount,
    pa.EditCount,
    pa.CommentCount,
    tu.PostCount,
    tu.AvgScore,
    tu.TotalViews,
    tu.TotalAnswers
FROM RecentPosts rp
JOIN PostTags pt ON rp.Id = pt.Id
JOIN PostActivity pa ON rp.Id = pa.Id
JOIN TopUsers tu ON rp.OwnerUserId = tu.OwnerUserId
ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.AnswerCount DESC
LIMIT 10;
