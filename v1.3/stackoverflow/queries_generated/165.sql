-- {"query": "165.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2089} 
WITH TagPosts AS (
  SELECT
    t.tag,
    p.Id AS question_id,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.OwnerUserId
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags,''), 2, greatest(length(coalesce(p.Tags,''))-2,0)), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1
),
TagAgg AS (
  SELECT
    tag,
    count(*) AS question_count,
    sum(coalesce(AnswerCount,0)) AS total_answers,
    sum(coalesce(ViewCount,0)) AS total_views,
    sum(case when Score>0 then 1 else 0 end) AS positive_questions,
    avg(coalesce(Score,0)) AS avg_question_score,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY Score) AS median_question_score
  FROM TagPosts
  GROUP BY tag
),
Answers AS (
  SELECT
    a.Id AS answer_id,
    a.ParentId AS question_id,
    a.CreationDate,
    a.Score AS answer_score,
    a.OwnerUserId AS answer_owner
  FROM Posts a
  WHERE a.PostTypeId = 2
),
TopAnswersPerQuestion AS (
  SELECT DISTINCT ON (question_id)
    question_id,
    answer_id,
    answer_score,
    answer_owner
  FROM Answers
  ORDER BY question_id, answer_score DESC NULLS LAST, CreationDate ASC
),
TagAnswerStats AS (
  SELECT
    tp.tag,
    count(a.answer_id) AS answers_count,
    avg(a.answer_score) AS avg_answer_score,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY a.answer_score) AS median_answer_score,
    sum(case when a.answer_score >= 10 then 1 else 0 end) AS high_score_answers
  FROM TagPosts tp
  LEFT JOIN Answers a ON a.question_id = tp.question_id
  GROUP BY tp.tag
),
UserBadgeSummary AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    count(b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
    count(b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
    count(b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
    coalesce(sum(b.Class),0) AS badge_score,
    row_number() OVER (PARTITION BY u.Id ORDER BY count(b.Id) DESC) rn
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
TagTopUsers AS (
  -- For each tag, find top 3 users by number of answers to questions with that tag
  SELECT
    tag,
    answer_owner AS user_id,
    count(*) AS answers_by_user,
    row_number() OVER (PARTITION BY tag ORDER BY count(*) DESC, answer_owner) AS rn
  FROM TagPosts tp
  JOIN Answers a ON a.question_id = tp.question_id
  WHERE a.OwnerUserId IS NOT NULL
  GROUP BY tag, answer_owner
),
TagTop3Users AS (
  SELECT tag, user_id, answers_by_user
  FROM TagTopUsers
  WHERE rn <= 3
),
TagLinkSummary AS (
  SELECT
    t.tag,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) AS outgoing_links,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) AS duplicate_links
  FROM TagPosts t
  LEFT JOIN PostLinks pl ON pl.PostId = t.question_id
  GROUP BY t.tag
),
TagActivityWindow AS (
  SELECT
    tag,
    date_trunc('month', CreationDate) AS mon,
    count(*) AS q_per_month,
    sum(coalesce(ViewCount,0)) AS views_per_month
  FROM TagPosts
  GROUP BY tag, date_trunc('month', CreationDate)
),
TagLatestActivity AS (
  SELECT tag, max(mon) AS last_month
  FROM TagActivityWindow
  GROUP BY tag
),
TagSeasonal AS (
  SELECT
    taw.tag,
    taw.mon,
    taw.q_per_month,
    taw.views_per_month,
    lag(taw.q_per_month) OVER (PARTITION BY taw.tag ORDER BY taw.mon) AS prev_q,
    lead(taw.q_per_month) OVER (PARTITION BY taw.tag ORDER BY taw.mon) AS next_q
  FROM TagActivityWindow taw
),
CombinedTagMetrics AS (
  SELECT
    ta.tag,
    ta.question_count,
    ta.total_answers,
    ta.total_views,
    ta.avg_question_score,
    ta.median_question_score,
    tas.answers_count,
    tas.avg_answer_score,
    tas.median_answer_score,
    tas.high_score_answers,
    coalesce(tls.outgoing_links,0) AS outgoing_links,
    coalesce(tls.duplicate_links,0) AS duplicate_links,
    coalesce(gold_users.gold_top_count,0) AS gold_top_contributors
  FROM TagAgg ta
  LEFT JOIN TagAnswerStats tas ON tas.tag = ta.tag
  LEFT JOIN TagLinkSummary tls ON tls.tag = ta.tag
  LEFT JOIN (
    SELECT tag, count(*) AS gold_top_count
    FROM TagTop3Users tu
    JOIN Users u ON u.Id = tu.user_id
    JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
    GROUP BY tag
  ) gold_users ON gold_users.tag = ta.tag
),
RankedTags AS (
  SELECT
    ctm.*,
    row_number() OVER (ORDER BY ctm.question_count DESC, ctm.total_views DESC, ctm.avg_answer_score DESC NULLS LAST) AS global_rank,
    dense_rank() OVER (ORDER BY ctm.median_question_score DESC NULLS LAST) AS median_rank
  FROM CombinedTagMetrics ctm
),
SelectedTags AS (
  SELECT *
  FROM RankedTags
  WHERE global_rank <= 50
  ORDER BY global_rank
),
-- A contrived union of two different tag selections to exercise set operators
Top50AndMedianTop5 AS (
  SELECT * FROM SelectedTags
  UNION ALL
  SELECT r.* FROM RankedTags r WHERE median_rank <= 5
)
SELECT
  s.tag,
  s.global_rank,
  s.median_rank,
  s.question_count,
  s.total_answers,
  s.total_views,
  s.avg_question_score,
  s.median_question_score,
  s.answers_count,
  s.avg_answer_score,
  s.median_answer_score,
  s.high_score_answers,
  s.outgoing_links,
  s.duplicate_links,
  s.gold_top_contributors,
  -- correlated subquery: latest highly scored answer in the tag's questions
  (SELECT a.answer_id
   FROM Answers a
   JOIN TagPosts tp ON tp.question_id = a.question_id
   WHERE tp.tag = s.tag AND a.answer_score = (SELECT max(answer_score) FROM Answers a2 JOIN TagPosts tp2 ON tp2.question_id = a2.question_id WHERE tp2.tag = s.tag)
   ORDER BY a.CreationDate DESC
   LIMIT 1) AS top_answer_id,
  -- correlated scalar: number of distinct answerers for this tag
  (SELECT count(DISTINCT a.OwnerUserId) FROM Posts a WHERE a.PostTypeId = 2 AND EXISTS (SELECT 1 FROM TagPosts tp WHERE tp.tag = s.tag AND tp.question_id = a.ParentId)) AS distinct_answerers,
  -- example string expressions and null logic
  concat('tag=', s.tag, ';q=', s.question_count, ';v=', s.total_views) AS tag_summary,
  CASE
    WHEN s.avg_answer_score IS NULL THEN 'no answers'
    WHEN s.avg_answer_score >= 5 THEN 'highly-answered'
    WHEN s.avg_answer_score BETWEEN 1 AND 4 THEN 'moderate'
    ELSE 'low-scoring'
  END AS answer_quality,
  -- windowed percentile across selected set
  percentile_cont(0.9) WITHIN GROUP (ORDER BY s.total_views) OVER () AS p90_views,
  -- include a hash-like expression to force CPU
  mod(abs(hashtext(coalesce(s.tag,''))), 1000000) AS tag_hash_mod
FROM Top50AndMedianTop5 s
LEFT JOIN TagLatestActivity tla ON tla.tag = s.tag
ORDER BY s.global_rank NULLS LAST, s.median_rank NULLS LAST, s.tag;