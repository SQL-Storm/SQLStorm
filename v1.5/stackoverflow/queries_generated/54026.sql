-- {"query": "54026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1876} 
WITH question_tags AS (
  SELECT
    P.Id          AS qid,
    P.AcceptedAnswerId,
    P.CreationDate AS qdate,
    P.Score       AS qscore,
    tags.tag
  FROM Posts P
  JOIN LATERAL regexp_matches(P.Tags, '<([^>]+)>', 'g') AS tags(tag) ON true
  WHERE P.PostTypeId = 1
),
accept_stats AS (
  SELECT
    qt.tag,
    COUNT(DISTINCT qt.qid)                                       AS total_questions,
    COUNT(qt.AcceptedAnswerId)                                   AS accepted_answers,
    AVG(qt.qscore)                                               AS avg_qscore,
    AVG(EXTRACT(EPOCH FROM (A.CreationDate - qt.qdate))/86400)   AS avg_days_to_accept
  FROM question_tags qt
  LEFT JOIN Posts A
    ON A.Id = qt.AcceptedAnswerId
  GROUP BY qt.tag
),
edit_counts AS (
  SELECT
    pq.tag,
    COUNT(ph.Id) AS edit_count
  FROM question_tags pq
  JOIN PostHistory ph
    ON ph.PostId = pq.qid
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)  -- title, body, tags edits
  GROUP BY pq.tag
)
SELECT
  s.tag,
  s.total_questions,
  s.accepted_answers,
  ROUND(s.avg_qscore, 2)          AS avg_qscore,
  ROUND(s.avg_days_to_accept, 2)  AS avg_days_to_accept,
  COALESCE(e.edit_count, 0)       AS edit_count,
  RANK() OVER (ORDER BY s.avg_days_to_accept) AS rank_by_accept_time
FROM accept_stats s
LEFT JOIN edit_counts e
  ON e.tag = s.tag
WHERE s.total_questions >= 50
ORDER BY rank_by_accept_time;