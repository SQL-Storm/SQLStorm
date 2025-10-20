WITH top_tags AS (
  SELECT tag AS TagName, COUNT(*) AS tag_usage
  FROM (
    SELECT unnest(string_to_array(substring(Tags FROM 2 FOR (length(Tags)-2)), '><')) AS tag
    FROM Posts 
    WHERE PostTypeId = 1 AND Tags IS NOT NULL AND length(Tags) > 2
  ) exploded_tags
  GROUP BY tag
  HAVING COUNT(*) >= 10
  ORDER BY tag_usage DESC 
  LIMIT 50
),
user_expertise AS (
  SELECT 
    u.Id AS user_id,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) AS questions_asked,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answers_given,
    AVG(p.Score) AS avg_score,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_received,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_received,
    COUNT(DISTINCT b.Id) AS badges_earned,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id 
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
  HAVING COUNT(DISTINCT p.Id) >= 5
),
question_complexity AS (
  SELECT 
    p.Id AS question_id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    ARRAY_AGG(DISTINCT tt.TagName) FILTER (WHERE tt.TagName IS NOT NULL) AS tags,
    AVG(DISTINCT a.Score) AS avg_answer_score,
    COUNT(DISTINCT a.Id) AS total_answers,
    MAX(a.CreationDate) - p.CreationDate AS response_time,
    COUNT(DISTINCT c.Id) AS total_comments,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
      ELSE 'Open'
    END AS status,
    p.OwnerUserId
  FROM Posts p
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN (
    SELECT 
      p.Id AS q_id,
      unnest(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><')) AS tag
    FROM Posts p 
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  ) tag_explosion ON tag_explosion.q_id = p.Id
  LEFT JOIN top_tags tt ON tt.TagName = tag_explosion.tag
  WHERE p.PostTypeId = 1 
    AND p.Score >= -5 
    AND p.ViewCount >= 100
    AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '365 days')
  GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
           p.FavoriteCount, p.CreationDate, p.ClosedDate, p.AcceptedAnswerId, p.OwnerUserId
  HAVING COUNT(DISTINCT a.Id) >= 1
)
SELECT 
  qc.question_id,
  qc.Title,
  qc.Score AS question_score,
  qc.ViewCount,
  qc.AnswerCount,
  qc.avg_answer_score,
  qc.response_time,
  qc.status,
  qc.tags,
  ue.Reputation AS asker_reputation,
  ue.answers_given AS asker_answers_count,
  ue.upvotes_received AS asker_upvotes,
  ue.badges_earned,
  ue.rep_rank AS asker_rank,
  COUNT(DISTINCT pl.RelatedPostId) AS linked_posts,
  AVG(EXTRACT(EPOCH FROM ph.CreationDate)) AS avg_revision_epoch,
  TO_TIMESTAMP(AVG(EXTRACT(EPOCH FROM ph.CreationDate))) AT TIME ZONE 'UTC' AS avg_revision_date,
  COUNT(DISTINCT ph.Id) AS revision_count,
  ARRAY_AGG(DISTINCT vt.Name) FILTER (WHERE vt.Name IS NOT NULL) AS vote_types,
  STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN ph.Comment END, '; ') AS close_reopen_history,
  DENSE_RANK() OVER (ORDER BY qc.ViewCount DESC, qc.AnswerCount DESC) AS popularity_rank,
  NTILE(10) OVER (ORDER BY qc.avg_answer_score DESC) AS quality_quartile,
  qc.CreationDate
FROM question_complexity qc
JOIN Users u ON u.Id = qc.OwnerUserId
JOIN user_expertise ue ON ue.user_id = u.Id
LEFT JOIN PostLinks pl ON pl.PostId = qc.question_id AND pl.LinkTypeId = 1
LEFT JOIN PostHistory ph ON ph.PostId = qc.question_id 
  AND ph.PostHistoryTypeId IN (4,5,6,10,11,12,24)
LEFT JOIN VoteTypes vt ON vt.Id = (
    SELECT VoteTypeId FROM Votes WHERE PostId = qc.question_id LIMIT 1
)
LEFT JOIN Posts linked_posts ON linked_posts.Id = pl.RelatedPostId
WHERE array_length(qc.tags, 1) >= 2
  AND qc.AnswerCount >= 2
  AND ue.Reputation >= 100
  AND qc.response_time <= INTERVAL '7 days'
GROUP BY 
  qc.question_id, qc.Title, qc.Score, qc.ViewCount, qc.AnswerCount, 
  qc.avg_answer_score, qc.response_time, qc.status, qc.tags,
  ue.Reputation, ue.answers_given, ue.upvotes_received, ue.badges_earned, ue.rep_rank,
  qc.CreationDate
HAVING COUNT(DISTINCT ph.Id) >= 1
ORDER BY popularity_rank ASC, qc.CreationDate DESC
LIMIT 1000;