-- {"query": "297.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5753} 
WITH recent_questions AS (
  SELECT p.*,
    substring(p.Tags from 2 for char_length(p.Tags)-2) AS tags_inner,
    coalesce(p.ViewCount,0) AS vc
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > NOW() - interval '5 years'
),
answers AS (
  SELECT a.*,
    a.ParentId AS QuestionId
  FROM Posts a
  WHERE a.PostTypeId = 2
),
answers_agg AS (
  SELECT q.Id AS QuestionId,
    count(a.Id) AS answer_count,
    avg(a.Score)::numeric(10,4) AS avg_answer_score,
    max(a.Score) AS max_answer_score,
    sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) AS accepted_exists,
    -- top answer as JSONB constructed from a windowed subquery
    (SELECT jsonb_build_object('Id', ta.Id, 'Score', ta.Score, 'OwnerUserId', ta.OwnerUserId, 'Snippet', left(regexp_replace(coalesce(ta.Body,''),'<[^>]+>',' ','g'),200))
     FROM (
       SELECT a2.*, row_number() OVER (PARTITION BY a2.ParentId ORDER BY a2.Score DESC NULLS LAST, a2.CreationDate ASC) rn
       FROM Posts a2
       WHERE a2.PostTypeId = 2
     ) ta
     WHERE ta.ParentId = q.Id AND ta.rn = 1
    ) AS top_answer
  FROM recent_questions q
  LEFT JOIN answers a ON a.ParentId = q.Id
  GROUP BY q.Id
),
tag_exploded AS (
  SELECT q.Id AS QuestionId, trim(t.Tag) AS Tag
  FROM recent_questions q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags,2,char_length(q.Tags)-2), '><')) AS Tag
  ) t
),
tag_stats AS (
  SELECT te.Tag,
    count(DISTINCT te.QuestionId) AS question_count,
    avg(q.ViewCount)::numeric(12,2) AS avg_views,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY q.Score) AS median_score,
    -- approximate top contributor userid (most answers in this tag)
    (SELECT u.Id FROM Users u
       JOIN Posts ans ON ans.OwnerUserId = u.Id AND ans.PostTypeId = 2
       JOIN Posts ques ON ques.Id = ans.ParentId
       WHERE ans.PostTypeId = 2 AND ques.Tags LIKE ('%' || '<' || te.Tag || '>' || '%')
       GROUP BY u.Id
       ORDER BY count(*) DESC NULLS LAST
       LIMIT 1
    ) AS top_contributor_userid,
    -- top 3 frequent words in titles for this tag
    (SELECT string_agg(word || ':' || cnt, ',') FROM (
       SELECT lower(regexp_replace(word,'[^a-z]','','g')) AS word, count(*) cnt
       FROM (
         SELECT unnest(string_to_array(regexp_replace(q.Title,'[^\\w]+',' ','g'),' ')) AS word
         FROM Posts q
         WHERE q.PostTypeId = 1 AND q.Tags LIKE ('%' || '<' || te.Tag || '>' || '%')
       ) w
       WHERE word <> ''
       GROUP BY lower(regexp_replace(word,'[^a-z]','','g'))
       ORDER BY cnt DESC
       LIMIT 3
    ) t) AS top_title_words
  FROM tag_exploded te
  JOIN recent_questions q ON q.Id = te.QuestionId
  GROUP BY te.Tag
),
user_badge_counts AS (
  SELECT b.UserId,
    count(*) FILTER (WHERE b.Class = 1) AS gold,
    count(*) FILTER (WHERE b.Class = 2) AS silver,
    count(*) FILTER (WHERE b.Class = 3) AS bronze,
    count(*) AS total
  FROM Badges b
  GROUP BY b.UserId
),
author_stats AS (
  SELECT u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(up.posts_count,0) AS posts_count,
    coalesce(up.avg_score,0)::numeric(10,4) AS avg_post_score,
    coalesce(ub.gold,0) AS gold_badges,
    coalesce(ub.silver,0) AS silver_badges,
    coalesce(ub.bronze,0) AS bronze_badges,
    row_number() OVER (ORDER BY coalesce(up.posts_count,0) DESC) AS rank_by_posts
  FROM Users u
  LEFT JOIN user_badge_counts ub ON ub.UserId = u.Id
  LEFT JOIN (
     SELECT OwnerUserId, count(*) AS posts_count, avg(Score) AS avg_score
     FROM Posts
     WHERE OwnerUserId IS NOT NULL
     GROUP BY OwnerUserId
  ) up ON up.OwnerUserId = u.Id
),
last_edits AS (
  SELECT ph.PostId,
    max(ph.CreationDate) AS last_edit_date,
    (array_agg(ph.UserId ORDER BY ph.CreationDate DESC) FILTER (WHERE ph.UserId IS NOT NULL))[1] AS last_editor_userid,
    (array_agg(ph.UserDisplayName ORDER BY ph.CreationDate DESC))[1] AS last_editor_displayname,
    (array_agg(ph.Comment ORDER BY ph.CreationDate DESC))[1] AS last_edit_comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,24)
  GROUP BY ph.PostId
),
duplicate_counts AS (
  SELECT pl.PostId, count(*) AS duplicates
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
  GROUP BY pl.PostId
),
vote_summaries AS (
  SELECT v.PostId,
    count(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
    count(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
    count(*) FILTER (WHERE v.VoteTypeId = 1) AS accepted_votes,
    sum(CASE WHEN v.VoteTypeId IN (8,9) THEN coalesce(v.BountyAmount,0) ELSE 0 END) AS bounty_total
  FROM Votes v
  GROUP BY v.PostId
),
question_complex AS (
  SELECT q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.ViewCount, q.Score, q.Tags,
    qa.answer_count, qa.avg_answer_score, qa.top_answer, qa.accepted_exists,
    qf.last_edit_date, qf.last_editor_userid, qf.last_editor_displayname, qf.last_edit_comment,
    dc.duplicates,
    vs.upvotes, vs.downvotes, vs.bounty_total,
    -- extract top tag for question by global tag popularity
    (SELECT ts.Tag
     FROM tag_exploded te JOIN tag_stats ts ON ts.Tag = te.Tag
     WHERE te.QuestionId = q.Id
     ORDER BY ts.question_count DESC NULLS LAST
     LIMIT 1) AS top_tag,
    -- correlated subquery: count of answers by the owner on other questions with the first tag of this question
    (SELECT count(*) FROM Posts p2 WHERE p2.PostTypeId = 2 AND p2.OwnerUserId = q.OwnerUserId AND EXISTS (
        SELECT 1 FROM tag_exploded te2 WHERE te2.QuestionId = p2.ParentId AND te2.Tag = (
           (string_to_array(substring(q.Tags,2,char_length(q.Tags)-2),'><'))[1]
        )
    )) AS owner_answers_in_same_first_tag,
    -- composite rank score mixing multiple signals with NULL logic
    (COALESCE(q.Score,0) * 0.6
     + COALESCE(qa.avg_answer_score,0) * 0.3
     + COALESCE(q.ViewCount,0) / GREATEST(NULLIF((SELECT avg(ViewCount) FROM recent_questions),0),1) * 0.1
     - COALESCE(vs.downvotes,0) * 0.05
    ) AS composite_rank_score
  FROM recent_questions q
  LEFT JOIN answers_agg qa ON qa.QuestionId = q.Id
  LEFT JOIN last_edits qf ON qf.PostId = q.Id
  LEFT JOIN duplicate_counts dc ON dc.PostId = q.Id
  LEFT JOIN vote_summaries vs ON vs.PostId = q.Id
)
SELECT qc.Id AS question_id,
  qc.Title,
  left(coalesce(qc.top_tag, ''),35) AS top_tag,
  qc.composite_rank_score,
  qc.answer_count,
  qc.avg_answer_score,
  qc.duplicates,
  qc.upvotes, qc.downvotes, qc.bounty_total,
  ua.DisplayName AS owner_name,
  ua.Reputation AS owner_reputation,
  ua.gold_badges, ua.silver_badges, ua.bronze_badges,
  qc.last_edit_date, qc.last_editor_displayname,
  -- top 5 tags for this question with counts
  (SELECT string_agg(ts.Tag || '(' || ts.question_count || ')' , ',') FROM (
     SELECT ts.Tag, ts.question_count
     FROM tag_exploded te JOIN tag_stats ts ON ts.Tag = te.Tag
     WHERE te.QuestionId = qc.Id
     ORDER BY ts.question_count DESC NULLS LAST
     LIMIT 5
  ) ts) AS top_tags_with_counts,
  -- top 3 commenters summary (name:count:score)
  (SELECT string_agg(cinfo, '; ')
   FROM (
     SELECT concat_ws(':', coalesce(u.DisplayName,c.UserDisplayName,'<anon>'), count(*)::text, sum(coalesce(c.Score,0))::text) AS cinfo
     FROM Comments c LEFT JOIN Users u ON u.Id = c.UserId
     WHERE c.PostId = qc.Id
     GROUP BY coalesce(u.DisplayName,c.UserDisplayName)
     ORDER BY count(*) DESC
     LIMIT 3
  ) x
  ) AS top_commenters,
  -- estimated top answer id when accepted flag not present
  CASE WHEN qc.top_answer IS NOT NULL AND (qc.accepted_exists IS NULL OR qc.accepted_exists = 0) THEN (qc.top_answer->>'Id')::int ELSE NULL END AS top_answer_id_estimated,
  CASE WHEN qc.duplicates > 0 THEN 'possibly duplicate' WHEN qc.answer_count = 0 THEN 'needs answers' ELSE 'normal' END AS status_hint
FROM question_complex qc
LEFT JOIN author_stats ua ON ua.UserId = qc.OwnerUserId
WHERE qc.composite_rank_score IS NOT NULL
ORDER BY qc.composite_rank_score DESC NULLS LAST
LIMIT 200

UNION ALL

-- Tag leaderboard branch to exercise set operator and different row shape (columns aligned with NULLs)
SELECT NULL AS question_id,
  'TAG_LEADERBOARD - ' || ts.Tag AS Title,
  ts.Tag AS top_tag,
  NULL::numeric AS composite_rank_score,
  ts.question_count AS answer_count,  -- reuse columns to fit union
  ts.median_score AS avg_answer_score,
  NULL::int AS duplicates,
  NULL::int AS upvotes,
  NULL::int AS downvotes,
  NULL::int AS bounty_total,
  NULL::varchar AS owner_name,
  NULL::int AS owner_reputation,
  NULL::int AS gold_badges,
  NULL::int AS silver_badges,
  NULL::int AS bronze_badges,
  NULL::timestamp AS last_edit_date,
  NULL::varchar AS last_editor_displayname,
  -- top_tags_with_counts holds top_title_words for tag branch
  ts.top_title_words AS top_tags_with_counts,
  NULL::text AS top_commenters,
  NULL::int AS top_answer_id_estimated,
  NULL::varchar AS status_hint
FROM tag_stats ts
ORDER BY 2 DESC
;