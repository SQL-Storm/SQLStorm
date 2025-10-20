WITH
  question_tags AS (
    SELECT
      p.Id          AS qid,
      UPPER(regexp_replace(value, '^<|>$', '', 'g')) AS tag
    FROM
      Posts p,
      UNNEST(string_to_array(p.Tags, '>')) AS t(value)
    WHERE p.PostTypeId = 1
      AND value <> ''
  ),
  answers AS (
    SELECT
      a.Id           AS aid,
      a.ParentId     AS qid,
      a.Score        AS answer_score,
      a.CreationDate AS answer_date,
      a.OwnerUserId  AS u_id
    FROM Posts a
    WHERE a.PostTypeId = 2
  ),
  answer_votes AS (
    SELECT
      v.PostId AS aid,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
    GROUP BY v.PostId
  ),
  answer_metrics AS (
    SELECT
      a.aid,
      a.qid,
      a.answer_score,
      COALESCE(av.upvotes,0)  AS upvotes,
      COALESCE(av.downvotes,0) AS downvotes,
      COALESCE(av.upvotes,0)-COALESCE(av.downvotes,0) AS net_votes,
      CASE WHEN a.answer_score >= 10 THEN 1 ELSE 0 END AS high_score_flag
    FROM answers a
    LEFT JOIN answer_votes av ON av.aid = a.aid
  ),
  tag_stats AS (
    SELECT
      qt.tag,
      COUNT(DISTINCT qt.qid) AS question_cnt,
      AVG(am.upvotes) AS avg_upvotes,
      AVG(am.downvotes) AS avg_downvotes,
      MAX(am.net_votes) AS max_net_vote,
      MIN(am.net_votes) AS min_net_vote,
      SUM(am.high_score_flag) AS high_scoring_answers,
      -- approximate median using percentile approximation compatible across dialects:
      -- compute median by taking value at 50th percentile via ordered aggregation using window and filtering
      (SELECT AVG(net_votes) FROM (
         SELECT am2.net_votes,
                ROW_NUMBER() OVER (ORDER BY am2.net_votes) AS rn,
                COUNT(*) OVER () AS cnt
         FROM answer_metrics am2
         JOIN question_tags qt2 ON am2.qid = qt2.qid
         WHERE qt2.tag = qt.tag
       ) sub
       WHERE rn IN (FLOOR((cnt+1)/2.0), CEIL((cnt+1)/2.0))
      ) AS median_net_vote
    FROM question_tags qt
    JOIN answer_metrics am ON am.qid = qt.qid
    GROUP BY qt.tag
  )
SELECT
  ts.tag,
  ts.question_cnt,
  ts.avg_upvotes,
  ts.avg_downvotes,
  ts.max_net_vote,
  ts.min_net_vote,
  ts.median_net_vote,
  ts.high_scoring_answers,
  ROW_NUMBER() OVER (ORDER BY ts.question_cnt DESC) AS rank
FROM tag_stats ts
ORDER BY ts.question_cnt DESC
LIMIT 50;