-- {"query": "56096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 450} 
WITH top_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS num_posts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS num_upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS num_downvotes
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1 AND v.VoteTypeId IN (2, 3)
    GROUP BY 
        u.Id, u.DisplayName
),
top_tags AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS num_posts,
        SUM(p.Score) AS total_score
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
),
question_answers AS (
    SELECT 
        p.Id AS question_id,
        COUNT(DISTINCT a.Id) AS num_answers,
        SUM(a.Score) AS total_answer_score
    FROM 
        Posts p
    JOIN 
        Posts a ON p.Id = a.ParentId
    WHERE 
        p.PostTypeId = 1 AND a.PostTypeId = 2
    GROUP BY 
        p.Id
)
SELECT 
    tu.DisplayName,
    tu.num_posts,
    tu.num_upvotes,
    tu.num_downvotes,
    tt.TagName,
    tt.num_posts,
    tt.total_score,
    qa.num_answers,
    qa.total_answer_score
FROM 
    top_users tu
JOIN 
    top_tags tt ON tu.num_posts > 10 AND tt.num_posts > 10
JOIN 
    question_answers qa ON tu.num_posts > 10 AND qa.num_answers > 2
WHERE 
    tu.num_upvotes > 100 AND tu.num_downvotes < 10
ORDER BY 
    tu.num_posts DESC, tu.num_upvotes DESC, tt.total_score DESC;