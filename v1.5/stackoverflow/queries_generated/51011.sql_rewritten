-- {"query": "51011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1163} 
WITH top_tags AS (
    SELECT t.TagName, t.Count as tag_usage_count
    FROM Tags t
    WHERE t.Count > 1000
    ORDER BY t.Count DESC
    LIMIT 20
),
active_users AS (
    SELECT u.Id as user_id, u.Reputation, u.UpVotes, u.DownVotes,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank
    FROM Users u
    WHERE u.Reputation > 10000
      AND u.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years'
    LIMIT 500
),
user_post_activity AS (
    SELECT au.user_id,
           COUNT(p.Id) as total_posts,
           AVG(p.Score) as avg_post_score,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as questions_asked,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answers_given,
           AVG(EXTRACT(EPOCH FROM AGE(p.LastActivityDate, p.CreationDate))) as avg_post_lifespan_seconds
    FROM active_users au
    JOIN Posts p ON p.OwnerUserId = au.user_id 
               OR (p.OwnerUserId IS NULL AND p.OwnerDisplayName IS NOT NULL)
    WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
      AND p.Score IS NOT NULL
    GROUP BY au.user_id
    HAVING COUNT(p.Id) >= 5
),
top_voted_posts_per_tag AS (
    SELECT p.Id as post_id, p.Title, p.Score, p.ViewCount, p.CreationDate,
           tt.TagName,
           ROW_NUMBER() OVER (PARTITION BY tt.TagName ORDER BY p.Score DESC, p.ViewCount DESC) as score_rank
    FROM Posts p
    JOIN top_tags tt ON position('<' || tt.TagName || '>' in p.Tags) > 0
    WHERE p.PostTypeId = 1
      AND p.Score >= 50
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
answer_quality AS (
    SELECT parent_post_id,
           AVG(answer.Score) as avg_answer_quality,
           COUNT(answer.Id) as answer_count,
           AVG(EXTRACT(EPOCH FROM AGE(answer.CreationDate, parent_post_id_creation))) as avg_response_time_seconds,
           SUM(CASE WHEN answer.Score > parent_post_score THEN 1 ELSE 0 END) as better_than_question_answers
    FROM (
        SELECT p.Id as parent_post_id, p.CreationDate as parent_post_id_creation, p.Score as parent_post_score
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) parent
    LEFT JOIN (
        SELECT pa.ParentId, pa.Id, pa.Score, pa.CreationDate
        FROM Posts pa
        WHERE pa.PostTypeId = 2
    ) answer ON answer.ParentId = parent.parent_post_id
    GROUP BY parent_post_id, parent_post_id_creation, parent_post_score
    HAVING COUNT(answer.Id) > 0
),
complex_interactions AS (
    SELECT v.PostId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as upvotes,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as downvotes,
           COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) as accepted,
           COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as bounties_started,
           SUM(v.BountyAmount) as total_bounty_amount
    FROM Votes v
    JOIN top_voted_posts_per_tag tvpt ON v.PostId = tvpt.post_id
    WHERE v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
    GROUP BY v.PostId
)
SELECT 
    tt.TagName,
    tvpt.Title,
    tvpt.Score as post_score,
    tvpt.ViewCount,
    tvpt.CreationDate as post_date,
    upa.avg_post_score as author_avg_score,
    upa.questions_asked,
    upa.answers_given,
    aq.avg_answer_quality,
    aq.answer_count,
    aq.avg_response_time_seconds,
    ci.upvotes,
    ci.downvotes,
    ci.accepted,
    ci.total_bounty_amount,
    (ci.upvotes * 1.0 / NULLIF(ci.upvotes + ci.downvotes, 0)) as vote_ratio,
    RANK() OVER (ORDER BY tvpt.Score DESC, tvpt.ViewCount DESC) as overall_rank,
    DENSE_RANK() OVER (PARTITION BY tt.TagName ORDER BY tvpt.Score DESC) as tag_rank
FROM top_voted_posts_per_tag tvpt
JOIN top_tags tt ON tvpt.TagName = tt.TagName
JOIN user_post_activity upa ON tvpt.post_id = (
    SELECT p.Id 
    FROM Posts p 
    WHERE p.Title = tvpt.Title 
      AND p.CreationDate = tvpt.CreationDate 
    LIMIT 1
) OR (
    SELECT au.user_id 
    FROM active_users au 
    JOIN Posts p ON p.OwnerUserId = au.user_id 
    WHERE p.Id = tvpt.post_id 
    LIMIT 1
) = upa.user_id
LEFT JOIN answer_quality aq ON tvpt.post_id = aq.parent_post_id
LEFT JOIN complex_interactions ci ON tvpt.post_id = ci.PostId
WHERE tvpt.score_rank <= 5
ORDER BY tvpt.Score DESC, tt.tag_usage_count DESC, tvpt.ViewCount DESC
LIMIT 100;