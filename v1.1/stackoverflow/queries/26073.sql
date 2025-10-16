WITH 
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
    top_tags AS (
        SELECT 
            t.TagName, 
            COUNT(p.Id) AS question_count
        FROM 
            Tags t
        JOIN 
            Posts p ON t.Id = p.Id
        WHERE 
            p.PostTypeId = 1
        GROUP BY 
            t.TagName
        ORDER BY 
            question_count DESC
        LIMIT 10
    )

SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    p.Id AS PostId,
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    t.TagName, 
    b.Name AS badge_name, 
    v.VoteTypeId, 
    ph.PostHistoryTypeId, 
    ph.Comment AS post_history_comment,
    CASE 
        WHEN u.Reputation > 1000 THEN 'High'
        WHEN u.Reputation > 500 THEN 'Medium'
        ELSE 'Low'
    END AS reputation_level,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS row_num,
    LAG(p.Score, 1) OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS prev_score,
    LEAD(p.Score, 1) OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS next_score,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS upvote_count,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS downvote_count,
    STRING_AGG(t.TagName, ', ') AS tag_list,
    BOOL_OR(ph.PostHistoryTypeId = 10) AS is_closed,
    MAX(ph.CreationDate) OVER (PARTITION BY p.Id) AS max_post_history_date,
    MIN(ph.CreationDate) OVER (PARTITION BY p.Id) AS min_post_history_date,
    AVG(p.Score) OVER (PARTITION BY u.Id) AS avg_score,
    PERCENT_RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS percent_rank
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
JOIN 
    Comments c ON p.Id = c.PostId
JOIN 
    Tags t ON p.Id = t.Id
JOIN 
    Badges b ON u.Id = b.UserId
JOIN 
    Votes v ON p.Id = v.PostId
JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Id IN (SELECT Id FROM top_users)
    AND p.Id IN (SELECT Id FROM top_posts)
    AND t.TagName IN (SELECT TagName FROM top_tags)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    t.TagName,
    b.Name,
    v.VoteTypeId,
    ph.PostHistoryTypeId,
    ph.Comment,
    ph.CreationDate
ORDER BY 
    u.Id, p.Score DESC;