-- {"query": "51041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1079} 

WITH popular_tags AS (
    SELECT t.TagName, COUNT(DISTINCT p.Id) as tag_usage_count
    FROM Tags t
    JOIN Posts p ON position(t.TagName in p.Tags) > 0
    WHERE p.PostTypeId = 1 AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 100
),
active_users AS (
    SELECT u.Id as user_id, u.Reputation, u.UpVotes
    FROM Users u
    WHERE u.LastAccessDate >= CURRENT_DATE - INTERVAL '30 days'
      AND u.Reputation >= 1000
),
top_answered_questions AS (
    SELECT p.Id as question_id, p.CreationDate, p.Score, p.ViewCount,
           p.AnswerCount, p.OwnerUserId, p.Title
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.AnswerCount >= 3
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
      AND p.ClosedDate IS NULL
),
engaged_posts AS (
    SELECT ptq.question_id, ptq.user_id as owner_id, ptq.reputation as owner_reputation,
           COUNT(v.Id) as total_votes,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) as upvotes,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) as downvotes,
           AVG(ptq.score) as avg_question_score
    FROM top_answered_questions ptq
    LEFT JOIN Votes v ON v.PostId = ptq.question_id 
                       AND v.VoteTypeId IN (2, 3)  -- UpMod, DownMod
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN active_users au ON ptq.OwnerUserId = au.user_id
    GROUP BY ptq.question_id, ptq.user_id, ptq.reputation
    HAVING COUNT(v.Id) > 10
),
tag_question_stats AS (
    SELECT ep.question_id, pt.tagname as tag_name,
           COUNT(DISTINCT c.Id) as comment_count,
           AVG(c.Score) as avg_comment_score,
           COUNT(DISTINCT a.Id) as answer_count
    FROM engaged_posts ep
    JOIN Posts p ON p.Id = ep.question_id AND position(pt.TagName in p.Tags) > 0
    JOIN popular_tags pt ON pt.TagName = tag_name
    LEFT JOIN Comments c ON c.PostId = ep.question_id
    LEFT JOIN Posts a ON a.ParentId = ep.question_id AND a.PostTypeId = 2 AND a.Score > 0
    GROUP BY ep.question_id, pt.tagname
),
user_activity AS (
    SELECT au.user_id, 
           COUNT(ph.Id) as edit_count,
           COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) as content_edits,
           AVG(EXTRACT(EPOCH FROM (ph.CreationDate - u.CreationDate))/86400) as days_since_join_for_edits
    FROM active_users au
    JOIN Users u ON u.Id = au.user_id
    LEFT JOIN PostHistory ph ON ph.UserId = au.user_id 
                             AND ph.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9)
                             AND ph.CreationDate >= u.CreationDate
    GROUP BY au.user_id
)
SELECT 
    tqs.tag_name,
    COUNT(DISTINCT tqs.question_id) as questions_in_tag,
    ROUND(AVG(tqs.comment_count), 2) as avg_comments_per_question,
    ROUND(AVG(tqs.avg_comment_score), 2) as avg_comment_score,
    ROUND(AVG(tqs.answer_count), 2) as avg_answers_per_question,
    ROUND(AVG(ep.total_votes), 0) as avg_votes_per_question,
    ROUND(AVG(ep.upvotes * 1.0 / NULLIF(ep.downvotes, 0)), 2) as avg_upvote_downvote_ratio,
    COUNT(DISTINCT ep.owner_id) as unique_active_owners,
    ROUND(AVG(ua.edit_count * 1.0 / NULLIF(ua.days_since_join_for_edits, 0)), 4) as avg_edits_per_day,
    COUNT(DISTINCT b.Id) as total_badges_earned_by_owners,
    ROUND(CORR(tqs.answer_count, ep.upvotes)::numeric, 4) as answer_upvote_correlation
FROM tag_question_stats tqs
JOIN engaged_posts ep ON tqs.question_id = ep.question_id
JOIN active_users au ON ep.owner_id = au.user_id
LEFT JOIN user_activity ua ON au.user_id = ep.owner_id
LEFT JOIN Badges b ON b.UserId = ep.owner_id 
                   AND b.Date >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY tqs.tag_name
HAVING COUNT(DISTINCT tqs.question_id) > 5
ORDER BY questions_in_tag DESC, avg_votes_per_question DESC
LIMIT 25;
