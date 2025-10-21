-- {"query": "9097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 4656} 

WITH
  -- recent 60‑day questions with split tags
  recent_q AS (
    SELECT
      p.Id,
      p.Title,
      p.CreationDate,
      p.Tags,
      unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= now() - interval '60 days'
  ),

  -- frequency of each tag in recent questions
  tag_freq AS (
    SELECT
      tag,
      count(*) AS cnt
    FROM recent_q
    GROUP BY tag
  ),

  -- per‑user vote aggregates and reputation ranking
  user_votes AS (
    SELECT
      u.Id                     AS user_id,
      u.DisplayName,
      sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
      sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
      sum(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes,
      (sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
       - sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) AS net_votes,
      dense_rank() OVER (ORDER BY u.Reputation DESC)     AS rep_rank
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
  ),

  -- basic statistics for each question
  question_stats AS (
    SELECT
      q.Id    AS qid,
      q.Title,
      count(a.Id) AS answer_count,
      max(a.Score) AS max_answer_score,
      row_number() OVER(PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST) AS best_ans_rank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title
  ),

  -- tags whose frequency is above average
  hot_tags AS (
    SELECT tag
    FROM tag_freq
    WHERE cnt > (SELECT avg(cnt) FROM tag_freq)
  ),

  -- distinct users commenting on recent questions
  recent_commenters AS (
    SELECT DISTINCT c.UserId
    FROM Comments c
    JOIN recent_q rq ON c.PostId = rq.Id
    WHERE c.CreationDate BETWEEN rq.CreationDate AND now()
      AND coalesce(c.Score,0) > 0
  )

SELECT
  uv.DisplayName,
  ht.tag                 AS hot_tag,
  qs.answer_count,
  qs.max_answer_score,
  coalesce(uv.upvotes,0) AS ups,
  coalesce(uv.downvotes,0) AS downs,
  CASE WHEN uv.net_votes >= 0 THEN uv.net_votes ELSE 0 END AS net_positive_votes,
  substring(qs.Title,1,40) || '...'                    AS snippet,
  length(qs.Title)                                    AS title_len,
  (uv.upvotes::decimal / NULLIF(uv.downvotes,0))       AS ups_to_downs_ratio,
  now() - min(rq.CreationDate) OVER ()                AS since_earliest_q,
  crt.Name                                            AS close_reason,
  t.TagName                                           AS related_tag
FROM hot_tags ht
CROSS JOIN user_votes uv
JOIN question_stats qs
  ON qs.qid = (
    SELECT Id
    FROM recent_q
    ORDER BY random()
    LIMIT 1
  )
LEFT JOIN recent_q rq
  ON rq.Id = qs.qid
LEFT JOIN CloseReasonTypes crt
  ON crt.Id = (
    SELECT ph.Comment::int
    FROM PostHistory ph
    WHERE ph.PostId = qs.qid
      AND ph.PostHistoryTypeId IN (10,12,20)
    ORDER BY ph.CreationDate DESC
    LIMIT 1
  )
FULL OUTER JOIN Tags t
  ON t.ExcerptPostId = qs.qid
  OR  t.WikiPostId    = qs.qid
WHERE uv.rep_rank <= 100
  AND ht.tag IN (SELECT tag FROM hot_tags LIMIT 5)
  AND uv.user_id IN (SELECT UserId FROM recent_commenters)
  AND (uv.DisplayName IS NOT NULL AND uv.DisplayName <> '')

UNION

SELECT
  uv2.DisplayName,
  'misc'            AS hot_tag,
  0                 AS answer_count,
  0                 AS max_answer_score,
  0,0,0,
  ''                AS snippet,
  0                 AS title_len,
  NULL              AS ups_to_downs_ratio,
  NULL              AS since_earliest_q,
  NULL              AS close_reason,
  NULL              AS related_tag
FROM user_votes uv2
WHERE uv2.rep_rank <= 5

EXCEPT

SELECT
  uv3.DisplayName,
  ht2.tag,
  qs2.answer_count,
  qs2.max_answer_score,
  0,0,0,
  '' AS snippet,
  0  AS title_len,
  NULL,
  NULL,
  NULL,
  NULL
FROM user_votes uv3
JOIN hot_tags ht2
  ON 1=1
JOIN question_stats qs2
  ON qs2.qid = (
    SELECT Id
    FROM Posts
    ORDER BY ViewCount DESC
    LIMIT 1
  )

ORDER BY net_positive_votes DESC, hot_tag, DisplayName
LIMIT 50 OFFSET 10;
