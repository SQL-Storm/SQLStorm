-- {"query": "56100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 390} 

WITH top_users AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS num_posts, 
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS num_upvoted_posts
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
top_tags AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS num_posts
    FROM 
        Tags t
    JOIN 
        Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
tag_scores AS (
    SELECT 
        t.TagName, 
        SUM(p.Score) AS total_score
    FROM 
        Tags t
    JOIN 
        Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
    GROUP BY 
        t.TagName
)
SELECT 
    tu.DisplayName, 
    tu.num_posts, 
    tu.num_upvoted_posts, 
    tt.num_posts AS num_tag_posts, 
    ts.total_score AS total_tag_score
FROM 
    top_users tu
JOIN 
    top_tags tt ON tu.Id = ANY(
        SELECT 
            p.OwnerUserId
        FROM 
            Posts p
        WHERE 
            tt.TagName = ANY(string_to_array(p.Tags, '><'))
    )
JOIN 
    tag_scores ts ON tt.TagName = ts.TagName
ORDER BY 
    tu.num_posts DESC, 
    tu.num_upvoted_posts DESC, 
    tt.num_posts DESC, 
    ts.total_score DESC;
