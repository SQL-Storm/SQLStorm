-- {"query": "56060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 391} 

WITH top_users AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS post_count, 
        SUM(p.Score) AS total_score
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        u.Id, 
        u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
top_posts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
        AND p.Score > 10
        AND p.ViewCount > 1000
),
top_tags AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS post_count
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE '%' + t.TagName + '%'
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 50
)
SELECT 
    tu.DisplayName, 
    tu.post_count, 
    tu.total_score, 
    tp.Title, 
    tp.Score, 
    tp.ViewCount, 
    tp.AnswerCount, 
    tp.CommentCount, 
    tt.TagName, 
    tt.post_count
FROM 
    top_users tu
JOIN 
    top_posts tp ON tu.Id = tp.OwnerUserId
JOIN 
    top_tags tt ON tp.Tags LIKE '%' + tt.TagName + '%'
ORDER BY 
    tu.post_count DESC, 
    tp.Score DESC, 
    tt.post_count DESC;
