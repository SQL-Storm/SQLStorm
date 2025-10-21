-- {"query": "31036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 435} 
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(b.BadgeCount, 0) AS BadgeCount,
        COALESCE(v.VoteCount, 0) AS VoteCount,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        (SELECT UserId, COUNT(*) AS BadgeCount FROM Badges GROUP BY UserId) b ON b.UserId = u.Id
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes GROUP BY PostId) v ON v.PostId = p.Id
    WHERE 
        p.PostTypeId = 1 AND 
        p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
TopPosts AS (
    SELECT * FROM RankedPosts WHERE PostRank <= 100
)
SELECT 
    p.PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.OwnerDisplayName,
    p.BadgeCount,
    p.VoteCount,
    COUNT(c.Id) AS CommentCount,
    ARRAY_AGG(DISTINCT t.TagName) AS Tags
FROM 
    TopPosts p
LEFT JOIN 
    Comments c ON c.PostId = p.PostId
LEFT JOIN 
    (SELECT DISTINCT unnest(string_to_array(p.Tags, '><')) AS TagName FROM Posts p WHERE p.PostTypeId = 1) t ON t.TagName IS NOT NULL
GROUP BY 
    p.PostId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.OwnerDisplayName, p.BadgeCount, p.VoteCount
ORDER BY 
    p.Score DESC, p.ViewCount DESC;