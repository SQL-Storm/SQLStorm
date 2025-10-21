-- {"query": "11034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 645} 

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
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS RowNum
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName, u.Reputation
),
TopContributors AS (
    SELECT 
        UserId, 
        SUM(Score) AS TotalScore
    FROM 
        Posts
    WHERE 
        CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        UserId
    HAVING 
        SUM(Score) > 100
    ORDER BY 
        TotalScore DESC
    LIMIT 10
),
PostActivity AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate
)
SELECT 
    RecentPosts.Id, 
    RecentPosts.Title, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.AnswerCount, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.Reputation, 
    RecentPosts.VoteCount, 
    RecentPosts.UpvoteCount, 
    RecentPosts.DownvoteCount, 
    COALESCE(PostActivity.CommentCount, 0) AS CommentCount, 
    COALESCE(PostActivity.EditCount, 0) AS EditCount
FROM 
    RecentPosts
LEFT JOIN 
    PostActivity ON RecentPosts.Id = PostActivity.Id
WHERE 
    RecentPosts.RowNum = 1
ORDER BY 
    RecentPosts.Score DESC, 
    RecentPosts.ViewCount DESC, 
    RecentPosts.AnswerCount DESC
