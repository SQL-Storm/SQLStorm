-- {"query": "47037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1804}

WITH RECURSIVE tag_hierarchy AS (
    SELECT t.Id, t.TagName, t.Count,
           string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS related_tags,
           1 AS level
    FROM Tags t
    INNER JOIN Posts p ON p.Id = t.WikiPostId
    WHERE t.Count > 10000
    
    UNION ALL
    
    SELECT t2.Id, t2.TagName, t2.Count,
           string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><') AS related_tags,
           th.level + 1
    FROM tag_hierarchy th
    CROSS JOIN LATERAL unnest(th.related_tags) AS rt(tag_name)
    INNER JOIN Tags t2 ON t2.TagName = rt.tag_name
    INNER JOIN Posts p2 ON p2.Id = t2.WikiPostId
    WHERE th.level < 3
),
expert_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COUNT(DISTINCT b.Name) AS unique_badges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges
    FROM Users u
    INNER JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 50000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT b.Name) > 20
),
question_metrics AS (
    SELECT q.Id AS QuestionId,
           q.Title,
           q.Score,
           q.ViewCount,
           q.AnswerCount,
           q.CreationDate AS QuestionDate,
           q.OwnerUserId AS QuestionUserId,
           a.Id AS AnswerId,
           a.Score AS AnswerScore,
           a.CreationDate AS AnswerDate,
           a.OwnerUserId AS AnswerUserId,
           EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS hours_to_answer,
           ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate) AS answer_rank,
           COUNT(DISTINCT c.UserId) OVER (PARTITION BY q.Id) AS unique_commenters,
           MAX(ph.CreationDate) OVER (PARTITION BY q.Id) AS last_edit_date
    FROM Posts q
    INNER JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId IN (q.Id, a.Id)
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= NOW() - INTERVAL '2 years'
      AND q.Score > 10
      AND q.AnswerCount BETWEEN 3 AND 20
),
voting_patterns AS (
    SELECT v.PostId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
           COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS bounties,
           SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS total_bounty,
           COUNT(DISTINCT DATE(v.CreationDate)) AS voting_days,
           STDDEV(EXTRACT(HOUR FROM v.CreationDate)) AS hour_stddev
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY v.PostId
    HAVING COUNT(*) > 10
),
linked_network AS (
    SELECT pl1.PostId AS source_post,
           pl1.RelatedPostId AS linked_post,
           pl2.RelatedPostId AS second_degree_post,
           COUNT(DISTINCT pl3.RelatedPostId) AS third_degree_connections
    FROM PostLinks pl1
    INNER JOIN PostLinks pl2 ON pl2.PostId = pl1.RelatedPostId
    LEFT JOIN PostLinks pl3 ON pl3.PostId = pl2.RelatedPostId
    WHERE pl1.LinkTypeId = 1
    GROUP BY pl1.PostId, pl1.RelatedPostId, pl2.RelatedPostId
)
SELECT 
    th.TagName AS primary_tag,
    th.level AS tag_depth,
    eu.DisplayName AS expert_user,
    eu.Reputation,
    eu.gold_badges,
    qm.Title AS question_title,
    qm.Score AS question_score,
    qm.ViewCount,
    qm.AnswerCount,
    qm.hours_to_answer AS fastest_answer_hours,
    qm.AnswerScore AS best_answer_score,
    qm.unique_commenters,
    vp.upvotes,
    vp.downvotes,
    COALESCE(vp.total_bounty, 0) AS total_bounty_amount,
    vp.voting_days,
    vp.hour_stddev AS voting_hour_variance,
    ln.third_degree_connections,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.Score) OVER (PARTITION BY th.TagName) AS median_score_for_tag,
    DENSE_RANK() OVER (PARTITION BY th.TagName ORDER BY qm.Score * LOG(qm.ViewCount + 1) DESC) AS tag_impact_rank,
    CASE 
        WHEN qm.hours_to_answer < 1 THEN 'Lightning Fast'
        WHEN qm.hours_to_answer < 24 THEN 'Same Day'
        WHEN qm.hours_to_answer < 168 THEN 'Within Week'
        ELSE 'Long Tail'
    END AS response_category,
    COUNT(*) OVER (PARTITION BY eu.Id, EXTRACT(YEAR FROM qm.QuestionDate), EXTRACT(MONTH FROM qm.QuestionDate)) AS user_monthly_activity
FROM tag_hierarchy th
CROSS JOIN expert_users eu
INNER JOIN question_metrics qm ON qm.QuestionUserId = eu.Id OR qm.AnswerUserId = eu.Id
LEFT JOIN voting_patterns vp ON vp.PostId = qm.QuestionId
LEFT JOIN linked_network ln ON ln.source_post = qm.QuestionId
WHERE qm.answer_rank = 1
  AND qm.hours_to_answer IS NOT NULL
  AND qm.Score > 0
ORDER BY th.Count DESC, qm.Score * LOG(qm.ViewCount + 1) DESC, eu.Reputation DESC
LIMIT 1000;
