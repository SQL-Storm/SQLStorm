-- {"query": "264.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4032} 
WITH
recent_posts AS (
  SELECT p.*,
    pt.Name AS post_type,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) rn_owner,
    COUNT(*) OVER (PARTITION BY p.OwnerUserId) cnt_owner
  FROM Posts p
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE p.CreationDate >= now() - INTERVAL '2 years'
),
tag_pairs AS (
  SELECT p.Id AS post_id, lower(trim(t)) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(
      string_to_array(
        substring(coalesce(p.Tags,'') FROM 2 FOR GREATEST(length(coalesce(p.Tags,'')) - 2,0)
        ),
      '><')
    ) AS t
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
tag_stats AS (
  SELECT tag,
    COUNT(DISTINCT p.Id) AS qcount,
    COUNT(DISTINCT p.OwnerUserId) AS ownercount,
    AVG(COALESCE(p.Score,0)) AS avg_score,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY COALESCE(p.Score,0)) AS p75_score
  FROM tag_pairs tp
  JOIN Posts p ON p.Id = tp.post_id
  GROUP BY tag
),
top_responders AS (
  SELECT a.ParentId AS question_id, a.OwnerUserId AS answerer_id, COUNT(*) AS answers_cnt,
    SUM(COALESCE(a.Score,0)) AS total_score,
    RANK() OVER (PARTITION BY a.ParentId ORDER BY COUNT(*) DESC, SUM(COALESCE(a.Score,0)) DESC) rnk
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId, a.OwnerUserId
),
question_snapshot AS (
  SELECT q.Id, q.Title, q.OwnerUserId, q.AcceptedAnswerId, q.Score AS qscore, q.ViewCount,
    q.CreationDate AS qcreated,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS comments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS downvotes,
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3) AS is_marked_duplicate,
    (SELECT ARRAY_AGG(DISTINCT lower(trim(t)))
       FROM (
         SELECT unnest(
           string_to_array(
             substring(coalesce(q.Tags,'') FROM 2 FOR GREATEST(length(coalesce(q.Tags,'')) - 2,0)
             ), '><')
         ) AS t
       ) sub
    ) AS tag_array
  FROM Posts q
  WHERE q.PostTypeId = 1
),
user_aggregates AS (
  SELECT u.Id AS user_id, u.DisplayName, u.Reputation,
    COUNT(DISTINCT b.Id) AS badge_count,
    MAX(b.Class) AS max_badge_class,
    SUM(CASE WHEN b.TagBased = B'1' THEN 1 ELSE 0 END) AS tag_badges,
    SUM(COALESCE(p.Score,0)) AS total_post_score,
    AVG(COALESCE(p.Score,0)) AS avg_post_score,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rep_rank
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
combined AS (
  SELECT qs.*,
    qs.tag_array,
    (SELECT u.DisplayName FROM Users u WHERE u.Id = qs.OwnerUserId) AS asked_by,
    (SELECT tr.answerer_id FROM top_responders tr WHERE tr.question_id = qs.Id AND tr.rnk = 1 LIMIT 1) AS top_answerer_id,
    (SELECT u2.DisplayName FROM Users u2 WHERE u2.Id = (SELECT tr.answerer_id FROM top_responders tr WHERE tr.question_id = qs.Id AND tr.rnk = 1 LIMIT 1)) AS top_answerer_name,
    (SELECT ts.tag FROM tag_stats ts WHERE ts.tag = COALESCE((SELECT unnest(qs.tag_array) LIMIT 1),'') ) AS first_tag_stat,
    (SELECT ts.qcount FROM tag_stats ts WHERE ts.tag = COALESCE((SELECT unnest(qs.tag_array) LIMIT 1),'') ) AS first_tag_qcount
  FROM question_snapshot qs
),
ranked AS (
  SELECT c.*,
    DENSE_RANK() OVER (ORDER BY COALESCE(c.qscore,0) DESC, COALESCE(c.ViewCount,0) DESC) AS qrank,
    NTILE(10) OVER (ORDER BY COALESCE(c.qscore,0) DESC) AS decile_score
  FROM combined c
)
SELECT r.Id,
  COALESCE(r.Title,'(no title)') AS title,
  r.asked_by,
  r.top_answerer_name,
  r.qscore,
  r.ViewCount,
  r.comments,
  r.upvotes,
  r.downvotes,
  r.is_marked_duplicate,
  array_to_string(r.tag_array,',') AS tags,
  r.qrank,
  r.decile_score,
  ts.qcount AS first_tag_question_count,
  us.badge_count,
  us.total_post_score,
  CASE
    WHEN r.AcceptedAnswerId IS NOT NULL THEN 'has_accepted'
    WHEN r.upvotes > r.downvotes AND r.ViewCount > 1000 THEN 'popular_unaccepted'
    WHEN r.is_marked_duplicate THEN 'duplicate'
    ELSE 'other' END AS classification,
  COALESCE( (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = r.OwnerUserId AND p2.PostTypeId = 1 AND p2.CreationDate > r.qcreated), 0) AS recent_questions_by_owner,
  (SELECT string_agg(s.x, '; ')
     FROM (
       SELECT u3.DisplayName || ':' || COUNT(*)::text AS x
       FROM Posts pa
       JOIN Users u3 ON pa.OwnerUserId = u3.Id
       WHERE pa.PostTypeId = 2 AND pa.ParentId = r.Id
       GROUP BY u3.Id, u3.DisplayName
       ORDER BY COUNT(*) DESC
       LIMIT 5
     ) s
  ) AS top_5_answerers,
  (SELECT bool_or(v.VoteTypeId = 4) FROM Votes v WHERE v.PostId = r.Id) AS any_flagged,
  (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = r.Id AND v.BountyAmount IS NOT NULL) AS total_bounties,
  (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = r.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS edits,
  us.rep_rank
FROM ranked r
LEFT JOIN tag_stats ts ON ts.tag = COALESCE((SELECT unnest(r.tag_array) LIMIT 1),'')
LEFT JOIN user_aggregates us ON us.user_id = r.OwnerUserId
WHERE (r.qscore IS NOT NULL OR r.ViewCount > 500)
  AND (us.Reputation > 100 OR r.upvotes > 10 OR r.comments > 2)
  AND EXISTS (SELECT 1 FROM Posts psub WHERE psub.ParentId = r.Id LIMIT 1)
ORDER BY r.qrank ASC, us.rep_rank ASC
LIMIT 200;