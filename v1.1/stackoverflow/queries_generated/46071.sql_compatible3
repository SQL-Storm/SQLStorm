WITH RECURSIVE user_influence AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT b.Id) as badge_count,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE u.Reputation > 5000
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
question_metrics AS (
  SELECT 
    p.Id as question_id,
    p.OwnerUserId,
    p.Score as q_score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.CreationDate as q_creation,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes,
    COUNT(DISTINCT c.Id) as comment_count,
    (CASE WHEN p.Tags IS NULL THEN NULL ELSE SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)) END) as tags_string,
    CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as has_accepted
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  LEFT JOIN Comments c ON p.Id = c.PostId
  WHERE p.PostTypeId = 1 
    AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '2 years')
    AND p.Score >= 5
  GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, 
           p.FavoriteCount, p.CreationDate, p.Tags, p.AcceptedAnswerId
),
answer_quality AS (
  SELECT 
    a.Id as answer_id,
    a.ParentId,
    a.OwnerUserId as answerer_id,
    a.Score as answer_score,
    a.CreationDate as answer_date,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as answer_upvotes,
    CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END as is_accepted,
    EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as hours_to_answer
  FROM Posts a
  INNER JOIN Posts q ON a.ParentId = q.Id
  LEFT JOIN Votes v ON a.Id = v.PostId
  WHERE a.PostTypeId = 2 
    AND a.Score >= 2
    AND a.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '2 years')
  GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, q.AcceptedAnswerId, q.CreationDate
),
tag_expertise AS (
  SELECT 
    s.splitted_tag AS tag,
    qm.OwnerUserId as user_id,
    COUNT(*) as questions_in_tag,
    AVG(qm.q_score) as avg_question_score,
    SUM(qm.ViewCount) as total_views
  FROM question_metrics qm
  CROSS JOIN LATERAL (
    SELECT NULLIF(splitted_tag, '') as splitted_tag
    FROM (
      SELECT regexp_split_to_table(qm.tags_string, '><') AS splitted_tag
    ) sub1
  ) s
  WHERE qm.OwnerUserId IS NOT NULL
    AND s.splitted_tag IS NOT NULL
  GROUP BY s.splitted_tag, qm.OwnerUserId
  HAVING COUNT(*) >= 3
),
collaboration_network AS (
  SELECT 
    qm.OwnerUserId as questioner_id,
    aq.answerer_id,
    COUNT(*) as interaction_count,
    AVG(aq.answer_score) as avg_answer_score,
    SUM(aq.is_accepted) as accepted_answers,
    AVG(aq.hours_to_answer) as avg_response_time
  FROM question_metrics qm
  INNER JOIN answer_quality aq ON qm.question_id = aq.ParentId
  WHERE qm.OwnerUserId IS NOT NULL 
    AND aq.answerer_id IS NOT NULL
    AND qm.OwnerUserId != aq.answerer_id
  GROUP BY qm.OwnerUserId, aq.answerer_id
  HAVING COUNT(*) >= 2
),
ranked_contributors AS (
  SELECT 
    ui.Id,
    ui.DisplayName,
    ui.Reputation,
    ui.badge_count,
    ui.gold_badges,
    COUNT(DISTINCT qm.question_id) as total_questions,
    COALESCE(AVG(qm.q_score), 0) as avg_q_score,
    COALESCE(SUM(qm.ViewCount), 0) as total_question_views,
    COUNT(DISTINCT aq.answer_id) as total_answers,
    COALESCE(AVG(aq.answer_score), 0) as avg_answer_score,
    COALESCE(SUM(aq.is_accepted), 0) as accepted_answer_count,
    COUNT(DISTINCT te.tag) as expertise_tags,
    (COUNT(DISTINCT cn.questioner_id) + COUNT(DISTINCT cn.answerer_id)) as collaboration_degree,
    ROW_NUMBER() OVER (ORDER BY ui.Reputation DESC, COUNT(DISTINCT qm.question_id) DESC) as rank
  FROM user_influence ui
  LEFT JOIN question_metrics qm ON ui.Id = qm.OwnerUserId
  LEFT JOIN answer_quality aq ON ui.Id = aq.answerer_id
  LEFT JOIN tag_expertise te ON ui.Id = te.user_id AND te.questions_in_tag >= 5
  LEFT JOIN collaboration_network cn ON ui.Id = cn.questioner_id OR ui.Id = cn.answerer_id
  GROUP BY ui.Id, ui.DisplayName, ui.Reputation, ui.badge_count, ui.gold_badges
  HAVING COUNT(DISTINCT qm.question_id) + COUNT(DISTINCT aq.answer_id) >= 10
)
SELECT 
  rc.rank,
  rc.DisplayName,
  rc.Reputation,
  rc.badge_count,
  rc.gold_badges,
  rc.total_questions,
  ROUND(CAST(rc.avg_q_score AS DECIMAL), 2) as avg_question_score,
  rc.total_question_views,
  rc.total_answers,
  ROUND(CAST(rc.avg_answer_score AS DECIMAL), 2) as avg_answer_score,
  rc.accepted_answer_count,
  rc.expertise_tags,
  rc.collaboration_degree,
  COALESCE(top_tags.tags, ARRAY[]::text[]) as top_expertise_tags,
  COALESCE(ROUND(CAST(collab_stats.avg_collab_score AS DECIMAL), 2), 0) as avg_collaboration_score
FROM ranked_contributors rc
LEFT JOIN LATERAL (
  SELECT array_agg(te.tag ORDER BY te.questions_in_tag DESC) as tags
  FROM tag_expertise te
  WHERE te.user_id = rc.Id
  LIMIT 5
) top_tags ON true
LEFT JOIN LATERAL (
  SELECT AVG(cn.avg_answer_score) as avg_collab_score
  FROM collaboration_network cn
  WHERE cn.answerer_id = rc.Id
) collab_stats ON true
WHERE rc.rank <= 100
ORDER BY rc.Reputation DESC, rc.total_questions DESC, rc.total_answers DESC
LIMIT 50;