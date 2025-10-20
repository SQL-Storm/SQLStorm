-- {"query": "51062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 950} 

WITH tag_popularity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) as question_count,
        AVG(p.Score) as avg_question_score,
        SUM(COALESCE(v_up.count, 0)) as total_upvotes
    FROM Tags t
    JOIN Posts p ON position(t.TagName in p.Tags) > 0
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) as count
        FROM Votes 
        WHERE VoteTypeId = 2 
        GROUP BY PostId
    ) v_up ON p.Id = v_up.PostId
    WHERE pt.Name = 'Question'
        AND p.Score > 0
        AND p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers_count,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as avg_answer_score,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
        STRING_AGG(DISTINCT tp.Name, ', ') as popular_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT DISTINCT 
            p.OwnerUserId,
            SUBSTRING(p.Tags from '<([^>]+)>') as tag_name
        FROM Posts p
        JOIN PostTypes pt ON p.PostTypeId = pt.Id
        WHERE pt.Name = 'Question'
            AND p.Tags IS NOT NULL
            AND p.Tags != ''
    ) user_tags ON u.Id = user_tags.OwnerUserId
    LEFT JOIN Tags t ON user_tags.tag_name = t.TagName
    LEFT JOIN tag_popularity tp ON t.TagName = tp.TagName
    WHERE u.Reputation >= 1000
        AND u.CreationDate < NOW() - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 5
),
top_interactions AS (
    SELECT 
        ue.user_id,
        ue.DisplayName as expert_name,
        tp.TagName,
        COUNT(DISTINCT pl.PostId) as linked_posts,
        AVG(p.Score) as avg_score,
        COUNT(DISTINCT c.Id) as total_comments
    FROM user_expertise ue
    JOIN Posts p ON ue.user_id = p.OwnerUserId
    JOIN PostLinks pl ON p.Id = pl.PostId
    JOIN Tags t ON position(t.TagName in p.Tags) > 0
    JOIN tag_popularity tp ON t.TagName = tp.TagName
    LEFT JOIN Comments c ON p.Id = c.PostId AND (c.UserId = ue.user_id OR c.UserDisplayName = ue.DisplayName)
    WHERE p.PostTypeId = 2  -- Answers only
        AND pl.LinkTypeId = 1  -- Linked posts
        AND p.CreationDate > NOW() - INTERVAL '3 months'
    GROUP BY ue.user_id, ue.DisplayName, tp.TagName
    HAVING COUNT(DISTINCT pl.PostId) >= 2
)
SELECT 
    ti.TagName,
    ti.expert_name,
    ti.linked_posts,
    ti.avg_score,
    ti.total_comments,
    ue.Reputation as expert_reputation,
    ue.avg_answer_score,
    ue.gold_badges,
    ue.popular_tags,
    RANK() OVER (PARTITION BY ti.TagName ORDER BY ti.linked_posts * ti.avg_score DESC) as expertise_rank,
    COUNT(*) OVER (PARTITION BY ti.TagName) as competitors_count
FROM top_interactions ti
JOIN user_expertise ue ON ti.user_id = ue.user_id
JOIN tag_popularity tp ON ti.TagName = tp.TagName
WHERE tp.question_count > 50
    AND ti.avg_score > 2
ORDER BY tp.total_upvotes DESC, ti.linked_posts DESC, ue.Reputation DESC
LIMIT 100;
