-- {"query": "51019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 939} 

WITH popular_tags AS (
  SELECT t.TagName, COUNT(*) as tag_usage
  FROM Tags t
  JOIN Posts p ON string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') @> ARRAY[t.TagName]::text[]
  WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '5 years'
  GROUP BY t.TagName
  HAVING COUNT(*) > 1000
),
active_users AS (
  SELECT u.Id, u.Reputation, u.UpVotes, u.DownVotes,
         COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5,8) THEN ph.PostId END) as edits_made,
         COUNT(DISTINCT v.PostId) as votes_cast
  FROM Users u
  JOIN PostHistory ph ON ph.UserId = u.Id AND ph.CreationDate > NOW() - INTERVAL '3 years'
  LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate > NOW() - INTERVAL '3 years'
  WHERE u.Reputation > 1000 AND u.LastAccessDate > NOW() - INTERVAL '1 year'
  GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
  HAVING COUNT(DISTINCT ph.PostId) > 5
),
question_stats AS (
  SELECT p.Id as question_id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
         p.CreationDate, p.LastActivityDate,
         COALESCE(accepted.score, 0) as accepted_score,
         AVG(ans.score) as avg_answer_score,
         COUNT(DISTINCT c.Id) as total_comments,
         COUNT(DISTINCT pl.RelatedPostId) as external_links
  FROM Posts p
  LEFT JOIN Posts accepted ON p.AcceptedAnswerId = accepted.Id
  LEFT JOIN Posts ans ON p.Id = ans.ParentId AND ans.PostTypeId = 2 AND ans.Score > -5
  LEFT JOIN Comments c ON p.Id = c.PostId AND c.Score >= 0
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
  WHERE p.PostTypeId = 1 AND p.Score > 0 AND p.CreationDate > NOW() - INTERVAL '2 years'
  GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.LastActivityDate, accepted.score
),
engagement_metrics AS (
  SELECT qs.question_id, au.Id as user_id,
         (qs.score + qs.accepted_score + COALESCE(qs.avg_answer_score, 0)) as total_question_value,
         (qs.viewcount * 0.1 + qs.total_comments * 0.5 + qs.external_links * 2) as engagement_score,
         CASE 
           WHEN qs.answer_count >= 3 AND qs.avg_answer_score > 5 THEN 'Highly Answered'
           WHEN qs.answer_count >= 1 AND qs.avg_answer_score > 0 THEN 'Moderately Answered'
           ELSE 'Low Engagement'
         END as engagement_category
  FROM question_stats qs
  JOIN active_users au ON qs.OwnerUserId = au.Id
  WHERE qs.viewcount > 100
)
SELECT 
  pt.TagName,
  em.engagement_category,
  COUNT(*) as question_count,
  AVG(em.total_question_value) as avg_question_value,
  AVG(em.engagement_score) as avg_engagement,
  SUM(au.reputation) as total_user_reputation,
  COUNT(DISTINCT em.user_id) as distinct_contributors,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY em.total_question_value) as p90_question_value,
  MAX(qs.lastactivitydate) as most_recent_activity
FROM engagement_metrics em
JOIN question_stats qs ON em.question_id = qs.question_id
JOIN active_users au ON em.user_id = au.Id
JOIN Posts p ON em.question_id = p.Id
JOIN popular_tags pt ON string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') @> ARRAY[pt.TagName]::text[]
WHERE em.engagement_score > 10
  AND au.edits_made > 2
  AND au.upvotes > au.downvotes
GROUP BY pt.TagName, em.engagement_category
HAVING COUNT(*) > 50
ORDER BY avg_engagement DESC, question_count DESC
LIMIT 20;
