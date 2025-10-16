-- {"query": "398.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14350} 
WITH
tags_exploded AS (
  SELECT p.Id AS question_id,
         trim(t.tag) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags) - 2), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
vote_summary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS net_score,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_by_originator,
    COUNT(*)::int AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
latest_comment AS (
  SELECT PostId, Text AS latest_comment_text, CreationDate AS latest_comment_date, UserId AS latest_comment_user
  FROM (
    SELECT c.*,
           ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC NULLS LAST) rn
    FROM Comments c
  ) cc
  WHERE rn = 1
),
answers_ranked AS (
  SELECT a.*,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(a.Score,0) DESC, a.CreationDate ASC) AS ans_row,
         RANK() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(a.Score,0) DESC) AS ans_tie_rank,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) OVER (PARTITION BY a.Id) AS answer_net_votes
  FROM Posts a
  LEFT JOIN Votes v ON v.PostId = a.Id
  WHERE a.PostTypeId = 2
),
top_answers AS (
  SELECT * FROM answers_ranked WHERE ans_row = 1
),
post_history_summary AS (
  SELECT ph.PostId,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (5,4,6,24,25)) AS edit_events,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13,14,15,19,20,35)) AS state_transitions,
         MAX(ph.CreationDate) AS last_history_date
  FROM PostHistory ph
  GROUP BY ph.PostId
),
duplicate_links AS (
  SELECT pl.PostId, COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS duplicate_count
  FROM PostLinks pl
  GROUP BY pl.PostId
),
tag_agg AS (
  SELECT te.tag,
         COUNT(*) AS question_count,
         SUM(COALESCE(q.ViewCount,0)) AS total_views,
         AVG(COALESCE(q.Score,0))::numeric(12,3) AS avg_score,
         COUNT(DISTINCT q.OwnerUserId) AS distinct_askers,
         MAX(q.CreationDate) AS most_recent_question
  FROM tags_exploded te
  JOIN Posts q ON q.Id = te.question_id
  GROUP BY te.tag
),
selected_tags AS (
  SELECT tag FROM tag_agg WHERE question_count > 100 OR total_views > 100000
  UNION
  SELECT tag FROM tag_agg WHERE avg_score >= 5.0
),
user_badge_summary AS (
  SELECT b.UserId,
         COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
         COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
         COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
         (MAX(CASE WHEN b.TagBased::text = '1' THEN 1 ELSE 0 END) = 1) AS has_tag_badges,
         MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
question_metrics AS (
  SELECT q.Id AS question_id,
         q.Title,
         q.OwnerUserId,
         COALESCE(u.DisplayName, q.OwnerDisplayName, 'unknown') AS asker_name,
         COALESCE(q.Score,0) AS q_score,
         COALESCE(vs.net_score,0) AS vote_net,
         COALESCE(vs.up_votes,0) AS up_votes,
         COALESCE(vs.down_votes,0) AS down_votes,
         COALESCE(q.ViewCount,0) AS views,
         COALESCE(q.AnswerCount,0) AS answer_count,
         COALESCE(phs.edit_events,0) AS edit_events,
         COALESCE(dl.duplicate_count,0) AS duplicate_count,
         COALESCE(la.latest_comment_text, '') AS latest_comment,
         COALESCE(la.latest_comment_date, q.CreationDate) AS last_comment_or_creation,
         (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = q.Id AND v.UserId IS NOT NULL) AS distinct_voters_on_question,
         (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS answer_rows,
         (SELECT COUNT(DISTINCT v2.UserId)
          FROM Votes v2
          JOIN Posts a2 ON a2.Id = v2.PostId
          WHERE a2.ParentId = q.Id AND v2.UserId IS NOT NULL AND v2.VoteTypeId IN (2,3)
         ) AS distinct_voters_on_answers,
         CASE WHEN EXISTS (SELECT 1 FROM Posts ans WHERE ans.Id = q.AcceptedAnswerId) THEN 1 ELSE 0 END AS has_accepted_answer,
         (
           (LN(GREATEST(q.ViewCount,1)) * 1.2)
           + (COALESCE(q.Score,0) * 3)
           + (COALESCE(q.AnswerCount,0) * 4)
           + (COALESCE(vs.up_votes,0) * 2)
           - (COALESCE(vs.down_votes,0) * 1.5)
           + (COALESCE(phs.edit_events,0) * 0.5)
           - (COALESCE(dl.duplicate_count,0) * 5)
         ) * EXP( - (EXTRACT(EPOCH FROM (NOW() - COALESCE(q.CreationDate, NOW()))) / (60*60*24*90)) ) AS hotness_score,
         COALESCE(array_length(string_to_array(substring(q.Tags,2,char_length(q.Tags)-2), '><'),1),0) as tag_count,
         q.Tags
  FROM Posts q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN vote_summary vs ON vs.PostId = q.Id
  LEFT JOIN post_history_summary phs ON phs.PostId = q.Id
  LEFT JOIN duplicate_links dl ON dl.PostId = q.Id
  LEFT JOIN latest_comment la ON la.PostId = q.Id
  WHERE q.PostTypeId = 1
),
answer_deltas AS (
  SELECT a.ParentId AS question_id,
         COUNT(*) FILTER (WHERE a.Score >= 0) AS non_negative_answers,
         COUNT(*) FILTER (WHERE a.Score < 0) AS negative_answers,
         MAX(a.Score) AS max_answer_score,
         MIN(a.Score) AS min_answer_score,
         AVG(a.Score) AS avg_answer_score,
         SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS has_accepted,
         MAX(a.CreationDate) FILTER (WHERE a.Id = q.AcceptedAnswerId) AS accepted_date,
         (SELECT COALESCE(STDDEV_POP(a2.Score),0) FROM Posts a2 WHERE a2.ParentId = a.ParentId) AS answer_score_stddev
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId, q.AcceptedAnswerId
),
top_tags_ranked AS (
  SELECT tag, question_count, total_views, avg_score,
         RANK() OVER (ORDER BY question_count DESC, total_views DESC) AS tag_rank
  FROM tag_agg
),
candidates AS (
  SELECT qm.*,
         COALESCE(ad.max_answer_score, 0) AS max_answer_score,
         COALESCE(ad.avg_answer_score, 0) AS avg_answer_score,
         COALESCE(ad.answer_score_stddev,0) AS answer_score_stddev
  FROM question_metrics qm
  LEFT JOIN answer_deltas ad ON ad.question_id = qm.question_id
  LEFT JOIN (
    SELECT a.ParentId AS question_id, MAX(a.Score) AS max_answer_score
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
  ) at ON at.question_id = qm.question_id
  WHERE (COALESCE(qm.hotness_score,0) > 10 OR EXISTS (
      SELECT 1 FROM tags_exploded te WHERE te.question_id = qm.question_id AND te.tag IN (SELECT tag FROM selected_tags)
  )) AND qm.answer_count > 0
),
final_ranked AS (
  SELECT c.*,
         RANK() OVER (
           ORDER BY
             has_accepted_answer DESC,
             hotness_score DESC NULLS LAST,
             views DESC,
             answer_count DESC,
             last_comment_or_creation DESC
         ) AS overall_rank,
         ROW_NUMBER() OVER (PARTITION BY COALESCE(OwnerUserId, -1) ORDER BY hotness_score DESC NULLS LAST) AS rank_per_user
  FROM candidates c
),
final_with_tags AS (
  SELECT fr.*,
         (SELECT array_agg(DISTINCT te.tag ORDER BY te.tag) FROM tags_exploded te WHERE te.question_id = fr.question_id) AS tag_list,
         COALESCE(ubs.gold_badges,0) AS gold_badges,
         COALESCE(ubs.silver_badges,0) AS silver_badges,
         COALESCE(ubs.bronze_badges,0) AS bronze_badges,
         COALESCE(ubs.has_tag_badges,false) AS has_tag_badges
  FROM final_ranked fr
  LEFT JOIN user_badge_summary ubs ON ubs.UserId = fr.OwnerUserId
)
SELECT
  fr.overall_rank,
  fr.question_id,
  COALESCE(fr.Title, '(no title)') AS title_snippet,
  COALESCE(fr.asker_name, 'unknown') AS asker,
  fr.views,
  fr.q_score,
  fr.vote_net,
  fr.hotness_score,
  fr.answer_count,
  fr.max_answer_score,
  ROUND(fr.avg_answer_score::numeric,3) AS avg_answer_score,
  ROUND(fr.answer_score_stddev::numeric,3) AS answer_score_stddev,
  fr.tag_count,
  COALESCE(array_to_string(fr.tag_list, ', '), '') AS tags,
  fr.latest_comment,
  fr.last_comment_or_creation,
  fr.has_accepted_answer,
  fr.duplicate_count,
  fr.edit_events,
  fr.distinct_voters_on_question,
  fr.distinct_voters_on_answers,
  fr.gold_badges,
  fr.silver_badges,
  fr.bronze_badges,
  fr.has_tag_badges,
  CONCAT(
    CASE
      WHEN fr.has_accepted_answer = 1 THEN 'A'
      WHEN fr.answer_count >= 5 THEN 'B'
      WHEN fr.hotness_score > 50 THEN 'H'
      ELSE 'N'
    END,
    '/',
    COALESCE(NULLIF(fr.OwnerUserId::text, ''), 'anon'),
    '/',
    COALESCE(NULLIF(fr.tag_count::text, '0'), '?'),
    '/',
    LPAD(CAST(fr.overall_rank AS TEXT), 4, '0')
  ) AS classification_code,
  (1 + (SELECT COUNT(*) FROM Posts q
        JOIN tags_exploded te ON te.question_id = q.Id
        WHERE te.tag = fr.tag_list[1] AND q.ViewCount > fr.views
       )
  ) AS rank_within_first_tag
FROM final_with_tags fr
ORDER BY fr.overall_rank, fr.hotness_score DESC NULLS LAST
LIMIT 100;