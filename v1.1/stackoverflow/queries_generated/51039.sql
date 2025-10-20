-- {"query": "51039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1418} 

WITH user_activity AS (
  SELECT 
    u.Id AS user_id,
    u.Reputation,
    u.CreationDate AS user_creation,
    COUNT(DISTINCT p.Id) AS total_posts,
    SUM(CASE WHEN pt.Id = 1 THEN 1 ELSE 0 END) AS questions_asked,
    SUM(CASE WHEN pt.Id = 2 THEN 1 ELSE 0 END) AS answers_given,
    AVG(p.Score) AS avg_post_score,
    MAX(p.CreationDate) AS last_post_date,
    COUNT(DISTINCT ph.Id) AS total_edits,
    COUNT(DISTINCT c.Id) AS total_comments,
    COUNT(DISTINCT v.Id) AS total_votes,
    COUNT(DISTINCT b.Id) AS total_badges,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS reputation_rank,
    NTILE(10) OVER (ORDER BY u.CreationDate) AS user_cohort
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
  LEFT JOIN Comments c ON u.Id = c.UserId AND c.PostId = p.Id
  LEFT JOIN Votes v ON u.Id = v.UserId AND v.PostId = p.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.Reputation, u.CreationDate
  HAVING u.CreationDate > CURRENT_TIMESTAMP - INTERVAL '5 years'
),
post_engagement AS (
  SELECT 
    p.Id AS post_id,
    p.CreationDate AS post_date,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Title,
    CASE 
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS post_type,
    COALESCE(aa.Score, 0) AS accepted_answer_score,
    COUNT(DISTINCT pl.RelatedPostId) AS linked_posts,
    SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS downvotes,
    DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS view_rank,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score
  FROM Posts p
  LEFT JOIN Posts aa ON p.AcceptedAnswerId = aa.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN Votes v ON p.Id = v.PostId
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.DeletionDate IS NULL
    AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '2 years'
  GROUP BY p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
           p.FavoriteCount, p.Title, p.PostTypeId, aa.Score
),
tag_analysis AS (
  SELECT 
    t.TagName,
    t.Count AS total_questions,
    AVG(pe.Score) AS avg_question_score,
    SUM(pe.ViewCount) AS total_views,
    COUNT(DISTINCT pe.post_id) AS active_posts,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY pe.ViewCount) AS p90_views,
    STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') AS related_tags
  FROM Tags t
  LEFT JOIN Posts p ON t.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))
  LEFT JOIN post_engagement pe ON p.Id = pe.post_id AND p.PostTypeId = 1
  WHERE t.Count > 100
  GROUP BY t.TagName, t.Count
  HAVING AVG(pe.Score) > 0
)
SELECT 
  ua.user_id,
  ua.DisplayName,
  ua.reputation_rank,
  ua.total_posts,
  ua.questions_asked,
  ua.answers_given,
  ROUND(ua.avg_post_score::numeric, 2) AS avg_score,
  EXTRACT(DAY FROM CURRENT_TIMESTAMP - ua.last_post_date) AS days_since_last_post,
  pe.post_id,
  pe.post_type,
  pe.score AS post_score,
  pe.view_rank,
  pe.upvotes,
  pe.downvotes,
  ROUND((pe.upvotes::float / NULLIF(pe.upvotes + pe.downvotes, 0)) * 100, 2) AS vote_ratio,
  ta.TagName AS top_tag,
  ta.avg_question_score AS tag_avg_score,
  ta.p90_views AS tag_high_views,
  CASE 
    WHEN ua.reputation_rank <= 100 THEN 'Power User'
    WHEN ua.total_posts > 50 THEN 'Active User'
    WHEN ua.questions_asked > 10 AND ua.answers_given = 0 THEN 'Questioner'
    ELSE 'Casual User'
  END AS user_category,
  ROW_NUMBER() OVER (PARTITION BY ua.user_cohort ORDER BY ua.total_badges DESC, ua.reputation DESC) AS cohort_rank
FROM user_activity ua
LEFT JOIN post_engagement pe ON ua.user_id = pe.OwnerUserId 
  AND pe.post_date = (SELECT MAX(CreationDate) FROM post_engagement pe2 WHERE pe2.OwnerUserId = ua.user_id)
LEFT JOIN (
  SELECT 
    p.OwnerUserId,
    STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), ',') AS all_tags
  FROM Posts p 
  WHERE p.PostTypeId = 1 AND p.OwnerUserId = ua.user_id
  GROUP BY p.OwnerUserId
) user_tags ON ua.user_id = user_tags.OwnerUserId
LEFT JOIN tag_analysis ta ON user_tags.all_tags LIKE '%' || ta.TagName || '%'
  AND ta.total_questions = (
    SELECT MAX(ta2.total_questions) 
    FROM tag_analysis ta2 
    WHERE user_tags.all_tags LIKE '%' || ta2.TagName || '%'
  )
WHERE ua.total_posts > 5
  AND pe.view_rank <= 1000
ORDER BY ua.reputation_rank, pe.view_rank, ta.total_views DESC
LIMIT 5000;
