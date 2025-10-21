-- {"query": "47080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1663}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.PostId) as direct_posts,
        0 as level
    FROM Tags t
    INNER JOIN Posts p ON p.Id IN (t.ExcerptPostId, t.WikiPostId)
    LEFT JOIN LATERAL (
        SELECT q.Id as PostId
        FROM Posts q
        WHERE q.PostTypeId = 1 
        AND q.Tags LIKE '%<' || t.TagName || '>%'
    ) pt ON true
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t.Id,
        t.TagName,
        th.direct_posts,
        th.level + 1
    FROM Tags t
    INNER JOIN tag_hierarchy th ON t.Id != th.Id
    WHERE th.level < 2
),
power_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT b.Name) FILTER (WHERE b.Class = 1) as gold_badges,
        COUNT(DISTINCT b.Name) FILTER (WHERE b.Class = 2) as silver_badges,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as reputation_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as activity_rank
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 10000
    AND u.CreationDate < CURRENT_TIMESTAMP - INTERVAL '365 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
post_analytics AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT pl.RelatedPostId) as linked_posts,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
        MAX(ph.CreationDate) as last_edit_date,
        EXTRACT(EPOCH FROM (MIN(a.CreationDate) - p.CreationDate))/3600 as hours_to_first_answer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Unanswered'
        END as status,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as user_post_rank
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '730 days'
    AND p.Score > 0
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
             p.OwnerUserId, p.CreationDate, p.Tags, p.ClosedDate, p.AcceptedAnswerId
)
SELECT 
    pu.DisplayName,
    pu.Reputation,
    pu.reputation_rank,
    pu.activity_rank,
    pu.gold_badges,
    pu.silver_badges,
    COUNT(DISTINCT pa.Id) as high_score_questions,
    AVG(pa.Score) as avg_question_score,
    AVG(pa.ViewCount) as avg_views,
    AVG(pa.AnswerCount) as avg_answers,
    AVG(pa.hours_to_first_answer) FILTER (WHERE pa.hours_to_first_answer IS NOT NULL) as avg_hours_to_first_answer,
    COUNT(DISTINCT pa.Id) FILTER (WHERE pa.status = 'Answered') as answered_questions,
    COUNT(DISTINCT pa.Id) FILTER (WHERE pa.status = 'Closed') as closed_questions,
    STRING_AGG(DISTINCT th.TagName, ', ' ORDER BY th.TagName) FILTER (WHERE pa.user_post_rank <= 5) as top_tags,
    JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'title', pa.Title,
            'score', pa.Score,
            'views', pa.ViewCount,
            'answers', pa.AnswerCount
        ) ORDER BY pa.Score DESC
    ) FILTER (WHERE pa.user_post_rank <= 3) as top_questions
FROM power_users pu
INNER JOIN post_analytics pa ON pa.OwnerUserId = pu.Id
LEFT JOIN tag_hierarchy th ON pa.Tags LIKE '%<' || th.TagName || '>%'
WHERE pu.reputation_rank <= 100
GROUP BY pu.DisplayName, pu.Reputation, pu.reputation_rank, 
         pu.activity_rank, pu.gold_badges, pu.silver_badges
HAVING COUNT(DISTINCT pa.Id) >= 5
ORDER BY pu.Reputation DESC, AVG(pa.Score) DESC
LIMIT 50;
