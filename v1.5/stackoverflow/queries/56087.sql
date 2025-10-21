WITH top_users AS (
  SELECT 
    u.Id,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS num_posts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS num_questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS num_answers,
    SUM(p.Score) AS total_score
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId IN (1, 2)
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    COUNT(DISTINCT p.Id) > 100
),
top_tags AS (
  SELECT 
    t.TagName,
    COUNT(DISTINCT p.Id) AS num_posts,
    SUM(p.Score) AS total_score
  FROM 
    Posts p
  JOIN 
    Tags t ON CAST(',' || p.Tags || ',' AS TEXT) LIKE '%,' || t.TagName || ',%'
  GROUP BY 
    t.TagName
  HAVING 
    COUNT(DISTINCT p.Id) > 50
),
question_answer_stats AS (
  SELECT 
    p.Id,
    p.Score,
    COUNT(DISTINCT a.Id) AS num_answers,
    MAX(a.Score) AS best_answer_score
  FROM 
    Posts p
  LEFT JOIN 
    Posts a ON p.Id = a.ParentId
  WHERE 
    p.PostTypeId = 1
  GROUP BY 
    p.Id, p.Score
),
voting_stats AS (
  SELECT 
    p.Id,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
  FROM 
    Posts p
  JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    p.Id
)
SELECT 
  tu.DisplayName,
  tu.num_posts,
  tu.num_questions,
  tu.num_answers,
  tu.total_score,
  tt.TagName,
  tt.num_posts AS tag_num_posts,
  tt.total_score AS tag_total_score,
  qas.num_answers AS qas_num_answers,
  qas.best_answer_score AS qas_best_answer_score,
  vs.upvotes,
  vs.downvotes
FROM 
  top_users tu
JOIN 
  top_tags tt ON 1 = 1
JOIN 
  question_answer_stats qas ON 1 = 1
JOIN 
  voting_stats vs ON 1 = 1
ORDER BY 
  tu.total_score DESC;