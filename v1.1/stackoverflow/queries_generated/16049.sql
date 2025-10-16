-- {"query": "16049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 116750, "output_tokens": 108084} 

WITH RECURSIVE user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as upvotes_received,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as downvotes_received
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT OUTER JOIN Comments c ON u.Id = c.UserId
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    LEFT OUTER JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
        AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
question_answer_stats AS (
    SELECT 
        q.Id as question_id,
        q.Title,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate as question_date,
        q.OwnerUserId as question_owner,
        a.Id as answer_id,
        a.Score as answer_score,
        a.OwnerUserId as answer_owner,
        CASE 
            WHEN q.AcceptedAnswerId = a.Id THEN 1 
            ELSE 0 
        END as is_accepted,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate) as answer_rank,
        DENSE_RANK() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) as user_question_sequence,
        LAG(a.Score, 1, 0) OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate) as prev_answer_score,
        AVG(a.Score) OVER (PARTITION BY a.OwnerUserId ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) as rolling_avg_answer_score
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.ClosedDate IS NULL
        AND q.Score >= 5
        AND q.Tags LIKE '%<sql>%'
        AND LENGTH(COALESCE(q.Body, '')) > 200
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name,
        COUNT(*) as tag_post_count,
        AVG(p.Score) as avg_tag_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL
        AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag_name
    HAVING COUNT(*) >= 3
),
correlated_activity AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.UserId = u.Id 
           AND ph.PostHistoryTypeId IN (4, 5, 6)
           AND ph.CreationDate > u.CreationDate + INTERVAL '30 days') as edit_count,
        (SELECT STRING_AGG(DISTINCT b.Name, ', ')
         FROM Badges b
         WHERE b.UserId = u.Id 
           AND b.Class = 1) as gold_badges,
        (SELECT MAX(v.CreationDate)
         FROM Votes v
         JOIN Posts p ON v.PostId = p.Id
         WHERE p.OwnerUserId = u.Id
           AND v.VoteTypeId = 8) as last_bounty_date,
        EXISTS(
            SELECT 1 
            FROM Comments c 
            WHERE c.UserId = u.Id 
              AND c.Score >= 5
        ) as has_upvoted_comments
    FROM Users u
    WHERE u.Reputation > 1000
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.post_count,
    uam.comment_count,
    uam.badge_count,
    COALESCE(qas.question_score, 0) as best_question_score,
    qas.Title as best_question_title,
    CASE 
        WHEN qas.AnswerCount = 0 THEN 'Unanswered'
        WHEN qas.is_accepted = 1 THEN 'Has Accepted Answer'
        WHEN qas.answer_rank = 1 AND qas.is_accepted = 0 THEN 'Highest Score Not Accepted'
        ELSE 'Other Answer'
    END as answer_status,
    ROUND(CAST(qas.rolling_avg_answer_score AS NUMERIC), 2) as rolling_avg_score,
    te.tag_name as primary_tag,
    te.tag_post_count,
    ROUND(CAST(te.avg_tag_score AS NUMERIC), 2) as avg_tag_score,
    ca.edit_count,
    COALESCE(ca.gold_badges, 'None') as gold_badges,
    ca.has_upvoted_comments,
    CASE 
        WHEN uam.upvotes_received > 0 THEN 
            ROUND(CAST(uam.upvotes_received AS NUMERIC) / NULLIF(uam.upvotes_received + uam.downvotes_received, 0), 3)
        ELSE NULL
    END as vote_ratio,
    EXTRACT(YEAR FROM uam.CreationDate) as join_year,
    NTILE(10) OVER (ORDER BY uam.Reputation DESC) as reputation_decile
FROM user_activity_metrics uam
INNER JOIN correlated_activity ca ON uam.Id = ca.user_id
LEFT JOIN LATERAL (
    SELECT * FROM question_answer_stats qas_inner
    WHERE qas_inner.question_owner = uam.Id
    ORDER BY qas_inner.question_score DESC NULLS LAST
    LIMIT 1
) qas ON TRUE
LEFT JOIN LATERAL (
    SELECT * FROM tag_expertise te_inner
    WHERE te_inner.OwnerUserId = uam.Id
    ORDER BY te_inner.tag_post_count DESC, te_inner.avg_tag_score DESC
    LIMIT 1
) te ON TRUE
WHERE (uam.post_count > 5 OR uam.comment_count > 20)
    AND (qas.answer_rank <= 3 OR qas.answer_rank IS NULL)
    AND COALESCE(te.median_score, 0) >= 2
    AND (ca.gold_badges IS NOT NULL OR ca.edit_count > 10)
ORDER BY 
    CASE 
        WHEN uam.badge_count > 50 THEN uam.Reputation * 1.5
        ELSE uam.Reputation 
    END DESC,
    uam.post_count DESC,
    qas.question_score DESC NULLS LAST
LIMIT 100;
