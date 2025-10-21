-- {"query": "26096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 518} 

WITH 
    -- CTE to get top 10 users with the most badges
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
    
    -- CTE to get top 10 posts with the most comments
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
    
    -- CTE to get users who have posted at least 5 questions
    active_users AS (
        SELECT 
            u.Id, 
            u.DisplayName
        FROM 
            Users u
        JOIN 
            Posts p ON u.Id = p.OwnerUserId
        WHERE 
            p.PostTypeId = 1
        GROUP BY 
            u.Id, u.DisplayName
        HAVING 
            COUNT(p.Id) >= 5
    )

SELECT 
    u.Id, 
    u.DisplayName, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    b.badge_count, 
    ph.Comment AS post_history_comment
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    top_users b ON u.Id = b.Id
WHERE 
    p.PostTypeId = 1
    AND u.Id IN (SELECT Id FROM active_users)
    AND p.Id IN (SELECT Id FROM top_posts)
    AND ph.PostHistoryTypeId = 10
    AND ph.Comment LIKE '%Duplicate%'
    AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
    AND p.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
    AND b.badge_count > (SELECT AVG(badge_count) FROM top_users)
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    b.badge_count DESC;
