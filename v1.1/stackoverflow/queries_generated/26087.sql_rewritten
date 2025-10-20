-- {"query": "26087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 472} 
WITH top_users AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
top_posts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.Tags, 
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS row_num
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
    LIMIT 100
),
closed_posts AS (
    SELECT 
        p.Id, 
        p.Title, 
        ph.Comment AS close_reason
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId
    WHERE 
        ph.PostHistoryTypeId = 10
)
SELECT 
    tu.Id, 
    tu.DisplayName, 
    tu.upvotes, 
    tu.downvotes, 
    tp.Id AS top_post_id, 
    tp.Title AS top_post_title, 
    tp.Score AS top_post_score, 
    tp.ViewCount AS top_post_view_count, 
    tp.Tags AS top_post_tags, 
    cp.Id AS closed_post_id, 
    cp.Title AS closed_post_title, 
    cp.close_reason, 
    CASE 
        WHEN tu.upvotes > tu.downvotes THEN 'Good'
        WHEN tu.upvotes < tu.downvotes THEN 'Bad'
        ELSE 'Neutral'
    END AS user_reputation
FROM 
    top_users tu
LEFT JOIN 
    top_posts tp ON tu.Id = tp.Id
LEFT JOIN 
    closed_posts cp ON tu.Id = cp.Id
WHERE 
    tu.upvotes > 500
ORDER BY 
    tu.upvotes DESC;