WITH top_users AS (
  SELECT u.Id, u.Reputation, u.UpVotes, u.DownVotes,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank,
         ROW_NUMBER() OVER (ORDER BY u.UpVotes DESC) as upvote_rank
  FROM Users u
  WHERE u.Reputation > 1000
),
active_posts AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.LastActivityDate,
         pt.Name as post_type,
         tu.rep_rank, tu.upvote_rank
  FROM Posts p
  INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
  INNER JOIN top_users tu ON p.OwnerUserId = tu.Id
  WHERE p.CreationDate > DATE '2024-10-01' - INTERVAL '5 years'
    AND p.Score > 0
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
tag_posts AS (
  SELECT ap.Id, ap.post_type, ap.OwnerUserId, ap.Score, ap.ViewCount, ap.AnswerCount,
         ap.rep_rank, ap.upvote_rank,
         t.TagName,
         COUNT(DISTINCT v.Id) as vote_count,
         AVG(v.BountyAmount) as avg_bounty,
         COUNT(DISTINCT c.Id) as comment_count,
         COUNT(DISTINCT ph.Id) as history_count
  FROM active_posts ap
  INNER JOIN Posts p2 ON ap.Id = p2.Id
  LEFT JOIN Tags t ON p2.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Votes v ON ap.Id = v.PostId 
     AND v.VoteTypeId IN (2, 3, 8)
     AND v.CreationDate > ap.CreationDate
  LEFT JOIN Comments c ON ap.Id = c.PostId 
     AND c.CreationDate > ap.CreationDate 
     AND c.Score > 0
  LEFT JOIN PostHistory ph ON ap.Id = ph.PostId
     AND ph.PostHistoryTypeId IN (5, 6, 10, 11)
  WHERE ap.post_type IN ('Question', 'Answer')
    AND t.TagName IS NOT NULL
  GROUP BY ap.Id, ap.post_type, ap.OwnerUserId, ap.Score, ap.ViewCount, 
           ap.AnswerCount, ap.rep_rank, ap.upvote_rank, t.TagName
  HAVING COUNT(DISTINCT v.Id) > 5 OR COUNT(DISTINCT c.Id) > 10
),
user_stats AS (
  SELECT tu.Id,
         tu.Reputation,
         tu.upvote_rank,
         COUNT(DISTINCT tp.Id) as total_posts,
         AVG(tp.Score) as avg_post_score,
         SUM(tp.vote_count) as total_votes_received,
         SUM(tp.ViewCount) as total_views,
         COUNT(DISTINCT tp.TagName) as unique_tags_used,
         STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagName) as top_tags,
         COUNT(DISTINCT CASE WHEN tp.post_type = 'Question' THEN tp.Id END) as question_count,
         COUNT(DISTINCT CASE WHEN tp.post_type = 'Answer' THEN tp.Id END) as answer_count,
         SUM(CASE WHEN tp.post_type = 'Question' THEN tp.AnswerCount ELSE 0 END) as total_answers_to_questions
  FROM top_users tu
  INNER JOIN tag_posts tp ON tu.Id = tp.OwnerUserId
  GROUP BY tu.Id, tu.Reputation, tu.upvote_rank
  HAVING COUNT(DISTINCT tp.Id) >= 10
)
SELECT us.Id as user_id,
       us.Reputation,
       us.upvote_rank,
       us.total_posts,
       us.avg_post_score,
       us.total_votes_received,
       us.total_views,
       us.unique_tags_used,
       us.top_tags,
       us.question_count,
       us.answer_count,
       us.total_answers_to_questions,
       tp.popular_tags,
       tp.overall_avg_score,
       tp.max_single_post_score,
       ROUND(us.total_views * 1.0 / NULLIF(us.total_posts, 0), 2) as views_per_post,
       ROUND(us.total_votes_received * 1.0 / NULLIF(us.total_posts, 0), 2) as votes_per_post,
       CASE 
         WHEN us.question_count > us.answer_count THEN 'Question Focused'
         WHEN us.answer_count > us.question_count * 2 THEN 'Answer Specialist'
         ELSE 'Balanced'
       END as activity_type
FROM user_stats us
INNER JOIN (
  SELECT TagName as popular_tags,
         AVG(Score) as overall_avg_score,
         MAX(Score) as max_single_post_score,
         COUNT(*) as tag_usage_count
  FROM tag_posts
  GROUP BY TagName
  ORDER BY COUNT(*) DESC
  LIMIT 10
) tp ON 1=1
WHERE us.upvote_rank <= 100
ORDER BY us.Reputation DESC, us.total_votes_received DESC
LIMIT 50;