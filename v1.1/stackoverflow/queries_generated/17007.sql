-- {"query": "17007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 18680, "output_tokens": 18558} 

WITH user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        EXTRACT(YEAR FROM u.CreationDate) AS join_year,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_post_score,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS used_tags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2020-01-01'
        AND u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, EXTRACT(YEAR FROM u.CreationDate)
),
elite_badges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
        MAX(b.Date) AS last_badge_date,
        ARRAY_AGG(b.Name ORDER BY b.Date DESC) FILTER (WHERE b.Class = 1) AS gold_badge_names
    FROM Badges b
    WHERE EXISTS (
        SELECT 1 FROM user_activity ua WHERE ua.Id = b.UserId
    )
    GROUP BY b.UserId
),
answer_quality AS (
    SELECT 
        a.OwnerUserId,
        a.Id AS answer_id,
        a.Score AS answer_score,
        q.Score AS question_score,
        a.CreationDate AS answer_date,
        q.CreationDate AS question_date,
        CASE 
            WHEN a.Id = q.AcceptedAnswerId THEN 1 
            ELSE 0 
        END AS is_accepted,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.Score DESC NULLS LAST) AS answer_rank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) OVER (PARTITION BY a.OwnerUserId) AS median_answer_score,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600 AS hours_to_answer
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
        AND a.OwnerUserId IN (SELECT Id FROM user_activity)
),
comment_engagement AS (
    SELECT 
        c.UserId,
        COUNT(*) AS total_comments,
        AVG(LENGTH(c.Text)) AS avg_comment_length,
        SUM(CASE WHEN c.Score > 5 THEN 1 ELSE 0 END) AS high_score_comments,
        COALESCE(STRING_AGG(
            CASE 
                WHEN c.Text ILIKE '%thank%' OR c.Text ILIKE '%thanks%' THEN 'grateful'
                WHEN c.Text ILIKE '%why%' OR c.Text ILIKE '%how%' THEN 'questioning'
                WHEN c.Text ILIKE '%wrong%' OR c.Text ILIKE '%incorrect%' THEN 'corrective'
                ELSE NULL
            END, '|'
        ), 'neutral') AS comment_sentiment
    FROM Comments c
    WHERE c.UserId IS NOT NULL
        AND c.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY c.UserId
),
recursive_post_chain AS (
    WITH RECURSIVE post_hierarchy AS (
        SELECT 
            p.Id,
            p.ParentId,
            p.OwnerUserId,
            1 AS depth,
            ARRAY[p.Id] AS path
        FROM Posts p
        WHERE p.PostTypeId = 1 
            AND p.AnswerCount > 10
            AND p.Score > 50
        
        UNION ALL
        
        SELECT 
            p.Id,
            p.ParentId,
            p.OwnerUserId,
            ph.depth + 1,
            ph.path || p.Id
        FROM Posts p
        INNER JOIN post_hierarchy ph ON p.ParentId = ph.Id
        WHERE p.PostTypeId = 2
            AND NOT p.Id = ANY(ph.path)
            AND ph.depth < 5
    )
    SELECT 
        OwnerUserId,
        MAX(depth) AS max_interaction_depth,
        COUNT(DISTINCT Id) AS posts_in_chains
    FROM post_hierarchy
    GROUP BY OwnerUserId
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    COALESCE(ua.total_posts, 0) AS total_posts,
    COALESCE(ua.questions, 0) + COALESCE(ua.answers, 0) AS qa_posts,
    ROUND(COALESCE(ua.avg_post_score, 0)::numeric, 2) AS avg_score,
    COALESCE(eb.gold_badges, 0) || '/' || COALESCE(eb.silver_badges, 0) || '/' || COALESCE(eb.bronze_badges, 0) AS badge_count,
    CASE 
        WHEN eb.gold_badge_names IS NOT NULL THEN 
            SUBSTRING(ARRAY_TO_STRING(eb.gold_badge_names[1:3], ', '), 1, 50)
        ELSE 'No gold badges'
    END AS top_gold_badges,
    COALESCE(
        (SELECT COUNT(*) 
         FROM answer_quality aq 
         WHERE aq.OwnerUserId = ua.Id AND aq.is_accepted = 1),
        0
    ) AS accepted_answers,
    COALESCE(
        (SELECT ROUND(AVG(hours_to_answer)::numeric, 2)
         FROM answer_quality aq
         WHERE aq.OwnerUserId = ua.Id 
            AND aq.answer_rank <= 5
            AND aq.hours_to_answer BETWEEN 0 AND 720),
        0
    ) AS avg_response_time_hours,
    COALESCE(ce.total_comments, 0) AS comments_made,
    COALESCE(ce.high_score_comments, 0) AS popular_comments,
    UPPER(LEFT(COALESCE(ce.comment_sentiment, 'unknown'), 20)) AS sentiment_profile,
    COALESCE(rpc.max_interaction_depth, 0) AS max_thread_depth,
    DENSE_RANK() OVER (
        ORDER BY 
            ua.Reputation * 0.3 + 
            COALESCE(ua.avg_post_score, 0) * 10 + 
            COALESCE(eb.gold_badges, 0) * 100 + 
            COALESCE(eb.silver_badges, 0) * 20 + 
            COALESCE((SELECT COUNT(*) FROM answer_quality WHERE OwnerUserId = ua.Id AND is_accepted = 1), 0) * 15
        DESC
    ) AS overall_rank,
    CASE
        WHEN ua.Reputation > 50000 THEN 'Legend'
        WHEN ua.Reputation > 25000 AND COALESCE(eb.gold_badges, 0) > 5 THEN 'Expert'
        WHEN ua.Reputation > 10000 OR COALESCE(eb.gold_badges, 0) > 2 THEN 'Veteran'
        WHEN ua.Reputation > 5000 THEN 'Experienced'
        ELSE 'Rising Star'
    END AS user_tier,
    COALESCE(NULLIF(TRIM(SUBSTRING(ua.used_tags FROM 1 FOR 100)), ''), 'No tags') AS primary_tags
FROM user_activity ua
LEFT JOIN elite_badges eb ON ua.Id = eb.UserId
LEFT JOIN comment_engagement ce ON ua.Id = ce.UserId
LEFT JOIN recursive_post_chain rpc ON ua.Id = rpc.OwnerUserId
WHERE ua.total_posts > 0
    OR eb.gold_badges > 0
ORDER BY overall_rank, ua.Reputation DESC
LIMIT 100;
