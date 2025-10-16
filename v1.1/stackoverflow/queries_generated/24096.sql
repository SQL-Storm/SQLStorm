-- {"query": "24096.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3121} 
WITH 
  question_posts AS (
    SELECT p.Id, p.OwnerUserId, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  exploded AS (
    SELECT qp.Id, qp.OwnerUserId,
           UNNEST(regexp_split_to_array(regexp_replace(regexp_replace(qp.Tags, '^\<|\>$', ''), '\<\>', '|'), '|')) AS tag
    FROM question_posts qp
  ),
  tag_counts AS (
    SELECT tag, COUNT(*) AS qcount
    FROM exploded
    GROUP BY tag
    UNION ALL
    SELECT TagName, 0
    FROM Tags
    WHERE TagName NOT IN (SELECT tag FROM exploded)
  ),
  tag_user_qcount AS (
    SELECT tag, OwnerUserId, COUNT(*) AS uqcount
    FROM exploded
    GROUP BY tag, OwnerUserId
  ),
  tag_top3 AS (
    SELECT tag, OwnerUserId, uqcount,
           ROW_NUMBER() OVER (PARTITION BY tag ORDER BY uqcount DESC, OwnerUserId) AS rn
    FROM tag_user_qcount
  ),
  tag_avg_votes AS (
    SELECT p.Tags AS tag,
           ROUND(AVG(CASE WHEN v.VoteTypeId = 2 THEN p.Score ELSE 0 END)::numeric, 2) AS avgvote
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Tags
  ),
  tag_highscore AS (
    SELECT t.TagName AS tag,
           (SELECT COUNT(DISTINCT p.Id)
            FROM Posts p
            WHERE p.PostTypeId = 1
              AND p.Tags LIKE '%'||t.TagName||'%'
              AND p.Score > 5) AS highq
    FROM Tags t
  ),
  final AS (
    SELECT t.TagName, 
           COALESCE(tc.qcount,0) AS total_q,
           COALESCE(th.highq,0) AS highscore_q,
           COALESCE(ta.avgvote,0) AS avgvote,
           t.Count AS tag_total_questions
    FROM Tags t
    LEFT JOIN tag_counts tc ON tc.tag = t.TagName
    LEFT JOIN tag_highscore th ON th.tag = t.TagName
    LEFT JOIN tag_avg_votes ta ON ta.tag = t.TagName
  )
SELECT f.TagName, f.total_q, f.highscore_q, f.avgvote, f.tag_total_questions,
       tu.OwnerUserId, u.DisplayName, tu.uqcount AS user_q_count, tu.rn AS user_rank
FROM final f
LEFT JOIN tag_top3 tu ON tu.tag = f.TagName AND tu.rn <= 3
LEFT JOIN Users u ON u.Id = tu.OwnerUserId
ORDER BY f.TagName, tu.rn NULLS LAST;