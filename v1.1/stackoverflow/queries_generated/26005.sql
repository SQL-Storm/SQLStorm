-- {"query": "26005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 920} 

WITH 
    -- Get top 10 users with the most badges
    top_users AS (
        SELECT 
            u.Id, 
            u.DisplayName, 
            COUNT(b.Id) AS badge_count
        FROM 
            Users u
        JOIN 
            Badges b ON u.Id = b.UserId
        GROUP BY 
            u.Id, u.DisplayName
        ORDER BY 
            badge_count DESC
        LIMIT 10
    ),
    
    -- Get top 10 posts with the most comments
    top_posts AS (
        SELECT 
            p.Id, 
            p.Title, 
            COUNT(c.Id) AS comment_count
        FROM 
            Posts p
        JOIN 
            Comments c ON p.Id = c.PostId
        GROUP BY 
            p.Id, p.Title
        ORDER BY 
            comment_count DESC
        LIMIT 10
    ),
    
    -- Get top 10 tags with the most posts
    top_tags AS (
        SELECT 
            t.Id, 
            t.TagName, 
            COUNT(p.Id) AS post_count
        FROM 
            Tags t
        JOIN 
            Posts p ON t.Id = p.Id
        GROUP BY 
            t.Id, t.TagName
        ORDER BY 
            post_count DESC
        LIMIT 10
    ),
    
    -- Get top 10 users with the most upvotes
    top_upvoters AS (
        SELECT 
            u.Id, 
            u.DisplayName, 
            COUNT(v.Id) AS upvote_count
        FROM 
            Users u
        JOIN 
            Votes v ON u.Id = v.UserId
        WHERE 
            v.VoteTypeId = 2
        GROUP BY 
            u.Id, u.DisplayName
        ORDER BY 
            upvote_count DESC
        LIMIT 10
    )

SELECT 
    tu.Id AS top_user_id, 
    tu.DisplayName AS top_user_name, 
    tp.Id AS top_post_id, 
    tp.Title AS top_post_title, 
    tt.Id AS top_tag_id, 
    tt.TagName AS top_tag_name, 
    tuu.Id AS top_upvoter_id, 
    tuu.DisplayName AS top_upvoter_name,
    -- Calculate the average score of top posts
    AVG(p.Score) AS avg_score,
    -- Calculate the total number of comments on top posts
    SUM(c.comment_count) AS total_comments,
    -- Calculate the total number of badges for top users
    SUM(b.badge_count) AS total_badges,
    -- Calculate the total number of upvotes for top upvoters
    SUM(v.upvote_count) AS total_upvotes,
    -- Check if the top user has a badge
    CASE 
        WHEN b.UserId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS has_badge,
    -- Check if the top post has a comment
    CASE 
        WHEN c.PostId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS has_comment,
    -- Check if the top tag has a post
    CASE 
        WHEN p.Id IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS has_post,
    -- Calculate the total reputation of top users
    SUM(u.Reputation) AS total_reputation,
    -- Calculate the average creation date of top posts
    AVG(p.CreationDate) AS avg_creation_date,
    -- Calculate the total number of downvotes for top upvoters
    SUM(v2.downvote_count) AS total_downvotes
FROM 
    top_users tu
JOIN 
    top_posts tp ON tu.Id = tp.Id
JOIN 
    top_tags tt ON tp.Id = tt.Id
JOIN 
    top_upvoters tuu ON tu.Id = tuu.Id
JOIN 
    Posts p ON tp.Id = p.Id
JOIN 
    Comments c ON tp.Id = c.PostId
JOIN 
    Badges b ON tu.Id = b.UserId
JOIN 
    Votes v ON tuu.Id = v.UserId
JOIN 
    Votes v2 ON tuu.Id = v2.UserId
WHERE 
    v.VoteTypeId = 2
    AND v2.VoteTypeId = 3
GROUP BY 
    tu.Id, tu.DisplayName, tp.Id, tp.Title, tt.Id, tt.TagName, tuu.Id, tuu.DisplayName
ORDER BY 
    avg_score DESC, total_comments DESC, total_badges DESC, total_upvotes DESC;
