-- {"query": "51028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1257} 

WITH top_tags AS (
  SELECT TagName, COUNT(*) as tag_usage
  FROM (
    SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) as tag
    FROM Posts 
    WHERE PostTypeId = 1 AND Tags IS NOT NULL AND length(Tags) > 2
  ) exploded_tags
  GROUP BY TagName 
  HAVING COUNT(*) >= 10
  ORDER BY tag_usage DESC 
  LIMIT 50
),
user_expertise AS (
  SELECT 
    u.Id as user_id,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) as questions_asked,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers_given,
    AVG(p.Score) as avg_score,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as upvotes_received,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as downvotes_received,
    COUNT(DISTINCT b.Id) as badges_earned,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id 
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
  HAVING COUNT(DISTINCT p.Id) >= 5
),
question_complexity AS (
  SELECT 
    p.Id as question_id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    ARRAY_AGG(DISTINCT tt.TagName) FILTER (WHERE tt.TagName IS NOT NULL) as tags,
    AVG(DISTINCT a.Score) as avg_answer_score,
    COUNT(DISTINCT a.Id) as total_answers,
    MAX(a.CreationDate) - p.CreationDate as response_time,
    COUNT(DISTINCT c.Id) as total_comments,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
      ELSE 'Open'
    END as status
  FROM Posts p
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN (
    SELECT 
      p.Id as q_id,
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag
    FROM Posts p 
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  ) tag_explosion ON tag_explosion.q_id = p.Id
  LEFT JOIN top_tags tt ON tt.TagName = tag_explosion.tag
  WHERE p.PostTypeId = 1 
    AND p.Score >= -5 
    AND p.ViewCount >= 100
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
  GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
           p.FavoriteCount, p.CreationDate, p.ClosedDate, p.AcceptedAnswerId
  HAVING COUNT(DISTINCT a.Id) >= 1
)
SELECT 
  qc.question_id,
  qc.Title,
  qc.Score as question_score,
  qc.ViewCount,
  qc.AnswerCount,
  qc.avg_answer_score,
  qc.response_time,
  qc.status,
  qc.tags,
  ue.Reputation as asker_reputation,
  ue.answers_given as asker_answers_count,
  ue.upvotes_received as asker_upvotes,
  ue.badges_earned,
  ue.rep_rank as asker_rank,
  COUNT(DISTINCT pl.RelatedPostId) as linked_posts,
  AVG(DISTINCT ph.CreationDate) as avg_revision_date,
  COUNT(DISTINCT ph.Id) as revision_count,
  ARRAY_AGG(DISTINCT vt.Name) FILTER (WHERE vt.Name IS NOT NULL) as vote_types,
  STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN ph.Comment END, '; ') as close_reopen_history,
  DENSE_RANK() OVER (ORDER BY qc.ViewCount DESC, qc.AnswerCount DESC) as popularity_rank,
  NTILE(10) OVER (ORDER BY qc.avg_answer_score DESC) as quality_quartile
FROM question_complexity qc
JOIN Users u ON u.Id = qc.OwnerUserId
JOIN user_expertise ue ON ue.user_id = u.Id
LEFT JOIN PostLinks pl ON pl.PostId = qc.question_id AND pl.LinkTypeId = 1
LEFT JOIN PostHistory ph ON ph.PostId = qc.question_id 
  AND ph.PostHistoryTypeId IN (4,5,6,10,11,12,24)
LEFT JOIN VoteTypes vt ON vt.Id = (SELECT DISTINCT VoteTypeId FROM Votes WHERE PostId = qc.question_id LIMIT 1)
LEFT JOIN Posts linked_posts ON linked_posts.Id = pl.RelatedPostId
WHERE array_length(qc.tags, 1) >= 2
  AND qc.AnswerCount >= 2
  AND ue.Reputation >= 100
  AND qc.response_time <= INTERVAL '7 days'
GROUP BY 
  qc.question_id, qc.Title, qc.Score, qc.ViewCount, qc.AnswerCount, 
  qc.avg_answer_score, qc.response_time, qc.status, qc.tags,
  ue.Reputation, ue.answers_given, ue.upvotes_received, ue.badges_earned, ue.rep_rank
HAVING COUNT(DISTINCT ph.Id) >= 1
ORDER BY popularity_rank ASC, qc.CreationDate DESC
LIMIT 1000;
