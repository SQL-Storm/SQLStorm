-- {"query": "51018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 950} 
WITH popular_tags AS (
  SELECT t.tagname, COUNT(p.id) as post_count
  FROM tags t
  JOIN posts p ON position('<' || t.tagname || '>' in p.tags) > 0
  WHERE p.posttypeid = 1
  GROUP BY t.tagname
  HAVING COUNT(p.id) > 100
  ORDER BY post_count DESC
  LIMIT 20
),
user_activity AS (
  SELECT 
    u.id as user_id,
    u.displayname,
    u.reputation,
    COUNT(CASE WHEN ph.posthistorytypeid IN (4,5,6) THEN 1 END) as edits,
    COUNT(CASE WHEN v.votetypeid = 2 AND v.userid = u.id THEN 1 END) as upvotes_given,
    AVG(p.score) as avg_answer_score
  FROM users u
  LEFT JOIN posthistory ph ON ph.userid = u.id AND ph.postid IS NOT NULL
  LEFT JOIN posts p ON p.owneruserid = u.id AND p.posttypeid = 2
  LEFT JOIN votes v ON v.userid = u.id
  GROUP BY u.id, u.displayname, u.reputation
  HAVING COUNT(ph.id) > 0 OR COUNT(v.id) > 0
),
tag_experts AS (
  SELECT 
    ua.*,
    pt.tagname,
    COUNT(CASE WHEN p.posttypeid = 1 AND position('<' || pt.tagname || '>' in p.tags) > 0 THEN 1 END) as questions_answered,
    COUNT(CASE WHEN p.posttypeid = 2 AND position('<' || pt.tagname || '>' in parent.tags) > 0 THEN 1 END) as tag_specific_answers
  FROM user_activity ua
  JOIN posts p ON p.owneruserid = ua.user_id AND p.posttypeid IN (1,2)
  JOIN posts parent ON p.parentid = parent.id OR (p.posttypeid = 1 AND p.id = parent.id)
  JOIN popular_tags pt ON position('<' || pt.tagname || '>' in p.tags) > 0 
                    OR position('<' || pt.tagname || '>' in parent.tags) > 0
  WHERE p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
  GROUP BY ua.user_id, ua.displayname, ua.reputation, ua.edits, ua.upvotes_given, ua.avg_answer_score, pt.tagname
  HAVING COUNT(p.id) > 5
)
SELECT 
  te.displayname as expert_name,
  te.tagname,
  te.reputation,
  te.questions_answered,
  te.tag_specific_answers,
  te.edits,
  te.upvotes_given,
  te.avg_answer_score,
  (te.tag_specific_answers * 1.0 / NULLIF(te.questions_answered, 0)) as answer_ratio,
  RANK() OVER (PARTITION BY te.tagname ORDER BY (te.tag_specific_answers * te.reputation / 1000.0) DESC) as rank_in_tag,
  COUNT(DISTINCT c.id) as total_comments_on_expert_posts,
  AVG(EXTRACT(EPOCH FROM (ph.creationdate - p.creationdate))) as avg_time_to_first_edit_seconds
FROM tag_experts te
JOIN posts p ON p.owneruserid = te.user_id
LEFT JOIN comments c ON c.postid = p.id
LEFT JOIN posthistory ph ON ph.postid = p.id AND ph.posthistorytypeid IN (4,5,6) 
                         AND ph.creationdate = (SELECT MIN(ph2.creationdate) 
                                               FROM posthistory ph2 
                                               WHERE ph2.postid = p.id 
                                                 AND ph2.posthistorytypeid IN (4,5,6))
JOIN posts parent ON p.parentid = parent.id OR p.id = parent.id
WHERE position('<' || te.tagname || '>' in parent.tags) > 0
  AND p.score > 0
  AND p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
  te.user_id, te.displayname, te.tagname, te.reputation, 
  te.questions_answered, te.tag_specific_answers, te.edits, 
  te.upvotes_given, te.avg_answer_score, p.id
HAVING te.tag_specific_answers > 2 
  AND te.reputation > 1000
ORDER BY 
  te.tagname, 
  (te.tag_specific_answers * te.reputation / 1000.0) DESC,
  answer_ratio DESC
LIMIT 50;