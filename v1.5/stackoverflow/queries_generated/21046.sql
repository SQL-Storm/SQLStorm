-- {"query": "21046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1787} 

WITH active_users AS (
  SELECT 
    u.Id AS user_id,
    u.Reputation,
    u.CreationDate AS user_creation,
    COUNT(DISTINCT p.Id) AS post_count,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
    AVG(p.Score) AS avg_post_score
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.DeletionDate IS NULL
  WHERE u.Reputation > 100
    AND u.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    AND u.Location IS NOT NULL
    AND LENGTH(u.Location) > 5
  GROUP BY u.Id, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) > 0
),
top_questions AS (
  SELECT 
    p.Id AS question_id,
    p.Title,
    p.CreationDate AS q_creation,
    p.Score AS q_score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    au.user_id,
    au.question_count,
    ROW_NUMBER() OVER (PARTITION BY au.user_id ORDER BY p.ViewCount DESC, p.Score DESC) AS q_rank
  FROM active_users au
  JOIN Posts p ON au.user_id = p.OwnerUserId 
    AND p.PostTypeId = 1 
    AND p.ClosedDate IS NULL
    AND p.DeletionDate IS NULL
  WHERE p.ViewCount > 1000
    AND (p.Tags LIKE '%sql%' OR p.Tags LIKE '%python%')
),
answer_stats AS (
  SELECT 
    ans.ParentId AS question_id,
    COUNT(ans.Id) AS total_answers,
    SUM(ans.Score) AS total_answer_score,
    AVG(ans.Score) AS avg_answer_score,
    MAX(ans.Score) AS max_answer_score,
    COUNT(CASE WHEN ans.Score >= 5 THEN 1 END) AS high_score_answers,
    STRING_AGG(
      COALESCE(u.DisplayName, 'Anonymous'), 
      ' | '
    ) AS answer_authors
  FROM Posts ans
  LEFT JOIN Users u ON ans.OwnerUserId = u.Id
  WHERE ans.PostTypeId = 2 
    AND ans.DeletionDate IS NULL
  GROUP BY ans.ParentId
),
comment_insights AS (
  SELECT 
    c.PostId AS question_id,
    COUNT(c.Id) AS comment_count,
    AVG(c.Score) AS avg_comment_score,
    MAX(LENGTH(c.Text)) AS longest_comment_length,
    SUM(CASE 
      WHEN c.Text LIKE '%thanks%' OR c.Text LIKE '%thank you%' THEN 1 
      ELSE 0 
    END) AS thanks_comments
  FROM Comments c
  WHERE c.Score >= 0 
    AND c.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
    AND (c.UserId IS NOT NULL OR c.UserDisplayName IS NOT NULL)
  GROUP BY c.PostId
),
badge_summary AS (
  SELECT 
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
    MAX(b.Date) AS latest_badge_date,
    SUM(CASE WHEN b.TagBased = 1 AND b.Name LIKE '%sql%' THEN 1 ELSE 0 END) AS sql_related_badges
  FROM Badges b
  WHERE b.Date > CURRENT_TIMESTAMP - INTERVAL '2 years'
  GROUP BY b.UserId
),
vote_patterns AS (
  SELECT 
    v.PostId AS question_id,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
    COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorites,
    COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) AS accepted,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS total_bounties,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS vote_popularity_rank
  FROM Votes v
  WHERE v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '3 months'
    AND v.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1 AND DeletionDate IS NULL)
  GROUP BY v.PostId
  HAVING COUNT(*) > 10
)
SELECT 
  tq.question_id,
  tq.Title,
  tq.q_creation,
  tq.q_score,
  tq.ViewCount,
  tq.AnswerCount,
  tq.FavoriteCount,
  tq.Tags,
  tq.user_id,
  au.Reputation AS user_reputation,
  au.post_count,
  au.question_count,
  au.avg_post_score,
  tq.q_rank,
  COALESCE(asr.total_answers, 0) AS total_answers,
  COALESCE(asr.total_answer_score, 0) AS total_answer_score,
  COALESCE(asr.avg_answer_score, 0) AS avg_answer_score,
  COALESCE(asr.max_answer_score, 0) AS max_answer_score,
  COALESCE(asr.high_score_answers, 0) AS high_score_answers,
  COALESCE(asr.answer_authors, 'No answers') AS answer_authors,
  COALESCE(ci.comment_count, 0) AS comment_count,
  COALESCE(ci.avg_comment_score, 0) AS avg_comment_score,
  COALESCE(ci.longest_comment_length, 0) AS longest_comment_length,
  COALESCE(ci.thanks_comments, 0) AS thanks_comments,
  COALESCE(bs.gold_badges, 0) AS gold_badges,
  COALESCE(bs.silver_badges, 0) AS silver_badges,
  COALESCE(bs.bronze_badges, 0) AS bronze_badges,
  COALESCE(bs.sql_related_badges, 0) AS sql_related_badges,
  COALESCE(vp.upvotes, 0) AS upvotes,
  COALESCE(vp.downvotes, 0) AS downvotes,
  COALESCE(vp.favorites, 0) AS favorites,
  COALESCE(vp.total_bounties, 0) AS total_bounties,
  COALESCE(vp.vote_popularity_rank, 999999) AS vote_popularity_rank,
  CASE 
    WHEN tq.AnswerCount > 0 AND tq.q_score > 10 THEN 'High Quality'
    WHEN tq.ViewCount > 5000 AND tq.q_score > 5 THEN 'Popular'
    WHEN tq.q_rank = 1 AND au.question_count > 5 THEN 'Top Performer'
    ELSE 'Standard'
  END AS question_category,
  CONCAT(
    SUBSTRING(tq.Tags FROM 2 FOR POSITION('><' IN tq.Tags) - 2),
    CASE 
      WHEN asr.max_answer_score > 20 THEN ' | Featured Answer'
      WHEN ci.thanks_comments > 5 THEN ' | Highly Appreciated'
      ELSE ''
    END
  ) AS tag_summary,
  (tq.ViewCount * 0.7 + tq.q_score * 30 + COALESCE(asr.total_answer_score, 0) * 0.1)::numeric(10,2) AS engagement_score,
  CASE 
    WHEN tq.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN tq.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    WHEN au.Reputation > 10000 THEN 'Expert Author'
    ELSE 'Active'
  END AS status_flag
FROM top_questions tq
JOIN active_users au ON tq.user_id = au.user_id
LEFT JOIN answer_stats asr ON tq.question_id = asr.question_id
LEFT JOIN comment_insights ci ON tq.question_id = ci.question_id
LEFT JOIN badge_summary bs ON tq.user_id = bs.UserId
LEFT JOIN vote_patterns vp ON tq.question_id = vp.question_id
WHERE tq.q_rank <= 3
  AND (au.question_count >= 2 OR tq.ViewCount > 10000)
  AND (tq.q_creation > CURRENT_TIMESTAMP - INTERVAL '6 months')
ORDER BY engagement_score DESC, tq.ViewCount DESC, tq.q_score DESC
LIMIT 50;
