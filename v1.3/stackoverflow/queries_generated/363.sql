-- {"query": "363.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14601} 
WITH
  tag_unwind AS (
    SELECT
      p.Id AS question_id,
      unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  ),
  tag_stats AS (
    SELECT
      tu.tag,
      count(*) AS question_count,
      count(DISTINCT q.OwnerUserId) FILTER (WHERE q.OwnerUserId IS NOT NULL) AS distinct_askers,
      coalesce(sum(q.ViewCount),0) AS total_views,
      coalesce(avg(q.Score)::numeric,0) AS avg_score,
      rank() OVER (ORDER BY count(*) DESC) AS popularity_rank
    FROM tag_unwind tu
    JOIN Posts q ON q.Id = tu.question_id
    GROUP BY tu.tag
  ),
  median_answer_by_question AS (
    SELECT
      a.ParentId AS qid,
      percentile_disc(0.5) WITHIN GROUP (ORDER BY a.Score) AS median_ans_score
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
  ),
  answers_ranked AS (
    SELECT
      a.Id,
      a.ParentId,
      a.OwnerUserId,
      a.CreationDate,
      a.Score,
      row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS ans_row
    FROM Posts a
    WHERE a.PostTypeId = 2
  ),
  vote_pivots AS (
    SELECT
      v.PostId,
      count(*) FILTER (WHERE v.VoteTypeId = 1) AS vt_accepted,
      count(*) FILTER (WHERE v.VoteTypeId = 2) AS vt_up,
      count(*) FILTER (WHERE v.VoteTypeId = 3) AS vt_down,
      count(*) FILTER (WHERE v.VoteTypeId = 5) AS vt_fav,
      count(*) FILTER (WHERE v.VoteTypeId = 12) AS vt_spam,
      count(*) AS total_votes
    FROM Votes v
    GROUP BY v.PostId
  ),
  co_tag_pairs AS (
    SELECT
      t1.tag AS tag1,
      t2.tag AS tag2,
      count(*) AS pair_count
    FROM tag_unwind t1
    JOIN tag_unwind t2 ON t1.question_id = t2.question_id AND t1.tag < t2.tag
    GROUP BY t1.tag, t2.tag
  ),
  question_first_answer AS (
    SELECT
      q.Id AS qid,
      q.CreationDate AS q_created,
      (SELECT min(a.CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.CreationDate IS NOT NULL) AS first_answer_date,
      (SELECT EXTRACT(EPOCH FROM (min(a.CreationDate) - q.CreationDate)) FROM Posts a WHERE a.ParentId = q.Id AND a.CreationDate IS NOT NULL) AS seconds_to_first_answer
    FROM Posts q
    WHERE q.PostTypeId = 1
  ),
  top_users AS (
    SELECT
      u.Id,
      coalesce(u.DisplayName,'(no name)') AS display_name,
      u.Reputation,
      row_number() OVER (ORDER BY u.Reputation DESC) AS rep_rank
    FROM Users u
  ),
  tag_questions AS (
    SELECT
      ts.tag,
      array_agg(tu.question_id ORDER BY tu.question_id) AS question_ids
    FROM tag_unwind tu
    JOIN tag_stats ts ON ts.tag = tu.tag
    GROUP BY ts.tag
  ),
  user_summary AS (
    SELECT
      'user'::text AS row_type,
      u.Id::text AS key,
      coalesce(u.DisplayName,'(no name)')::text AS label,
      u.Reputation::text AS metric1,
      COALESCE((SELECT count(*) FROM Badges b WHERE b.UserId = u.Id),0)::text AS metric2,
      COALESCE((SELECT count(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1),0)::text AS metric3,
      COALESCE((SELECT count(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2),0)::text AS metric4,
      COALESCE((SELECT count(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3),0)::text AS metric5,
      COALESCE((SELECT count(*) FROM Posts p WHERE p.OwnerUserId = u.Id),0)::text AS metric6,
      COALESCE((SELECT round(avg(p.Score)::numeric,2) FROM Posts p WHERE p.OwnerUserId = u.Id),0)::text AS metric7,
      (
        SELECT jsonb_build_object(
          'top_tags',
            (SELECT coalesce(string_agg(tu.tag, ', ' ORDER BY cnt DESC), '') FROM (
               SELECT tu.tag, count(*) AS cnt
               FROM tag_unwind tu
               JOIN Posts p ON p.Id = tu.question_id
               WHERE p.OwnerUserId = u.Id
               GROUP BY tu.tag
               ORDER BY cnt DESC
               LIMIT 5
             ) t),
          'badges',
            (SELECT coalesce(jsonb_agg(jsonb_build_object('class', sb.Class, 'name', sb.Name)), '[]'::jsonb)
             FROM (
               SELECT b.Class, b.Name
               FROM Badges b
               WHERE b.UserId = u.Id
               ORDER BY b.Date DESC
               LIMIT 5
             ) sb)
        )::text
      )::text AS extra
    FROM Users u
    WHERE u.Reputation > (SELECT COALESCE(percentile_disc(0.75) WITHIN GROUP (ORDER BY Reputation), 1000) FROM Users)
  )
SELECT
  'tag'::text AS row_type,
  ts.tag::text AS key,
  ('tag:' || ts.tag)::text AS label,
  ts.question_count::text AS metric1,
  ts.distinct_askers::text AS metric2,
  ts.total_views::text AS metric3,
  round(ts.avg_score::numeric,2)::text AS metric4,
  ts.popularity_rank::text AS metric5,
  (
    SELECT COALESCE(string_agg(other_tag || '(' || pair_count::text || ')', ', ' ORDER BY pair_count DESC), '')
    FROM (
      SELECT
        CASE WHEN t1.tag = ts.tag THEN t2.tag ELSE t1.tag END AS other_tag,
        count(*) AS pair_count
      FROM tag_unwind t1
      JOIN tag_unwind t2 ON t1.question_id = t2.question_id AND t1.tag <> t2.tag
      WHERE t1.tag = ts.tag
      GROUP BY CASE WHEN t1.tag = ts.tag THEN t2.tag ELSE t1.tag END
      HAVING count(*) > 0
      ORDER BY pair_count DESC
      LIMIT 10
    ) x
  )::text AS metric6,
  (
    SELECT round(avg(qfa.seconds_to_first_answer)::numeric,2)
    FROM question_first_answer qfa
    WHERE qfa.seconds_to_first_answer IS NOT NULL
      AND EXISTS (SELECT 1 FROM tag_unwind tu WHERE tu.question_id = qfa.qid AND tu.tag = ts.tag)
  )::text AS metric7,
  (
    SELECT jsonb_build_object(
      'accepted_question_count', (SELECT COALESCE(count(*),0) FROM Posts q WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL AND EXISTS (SELECT 1 FROM tag_unwind tu WHERE tu.question_id = q.Id AND tu.tag = ts.tag)),
      'favorites', (SELECT COALESCE(count(*),0) FROM Votes v WHERE v.VoteTypeId = 5 AND EXISTS (SELECT 1 FROM tag_unwind tu WHERE tu.question_id = v.PostId AND tu.tag = ts.tag)),
      'net_votes', COALESCE((SELECT sum(vp.vt_up - vp.vt_down) FROM vote_pivots vp JOIN tag_unwind tu ON tu.question_id = vp.PostId WHERE tu.tag = ts.tag),0),
      'pct_gt_1k_views', CASE WHEN ts.question_count > 0 THEN round(100.0 * COALESCE((SELECT count(*) FROM Posts q WHERE q.PostTypeId = 1 AND q.ViewCount >= 1000 AND EXISTS (SELECT 1 FROM tag_unwind tu WHERE tu.question_id = q.Id AND tu.tag = ts.tag)),0)::numeric / ts.question_count,2) ELSE 0 END,
      'score_stats', (SELECT jsonb_build_object('median', percentile_disc(0.5) WITHIN GROUP (ORDER BY q.Score), 'min', min(q.Score), 'max', max(q.Score), 'count', count(*)) FROM Posts q WHERE q.PostTypeId = 1 AND EXISTS (SELECT 1 FROM tag_unwind tu WHERE tu.question_id = q.Id AND tu.tag = ts.tag))
    )::text
  ) AS extra
FROM tag_stats ts
LEFT JOIN tag_questions tq ON tq.tag = ts.tag
WHERE ts.question_count > 10
UNION ALL
SELECT *
FROM user_summary
ORDER BY metric1::numeric DESC NULLS LAST
LIMIT 200;