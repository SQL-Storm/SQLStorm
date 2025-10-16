-- {"query": "321.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14593} 
WITH
q_tags AS (
  SELECT
    q.Id AS question_id,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    TRIM(t.tag) AS tag
  FROM Posts q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS tag
  ) t
  WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
),
answers AS (
  SELECT
    a.Id AS answer_id,
    a.ParentId AS question_id,
    a.OwnerUserId AS answer_owner,
    a.Score AS answer_score,
    a.CreationDate AS answer_date,
    CASE WHEN parent.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS is_accepted
  FROM Posts a
  LEFT JOIN Posts parent ON a.ParentId = parent.Id
  WHERE a.PostTypeId = 2
),
votes_agg AS (
  SELECT
    PostId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
    COUNT(*) AS total_votes
  FROM Votes
  GROUP BY PostId
),
comments_agg AS (
  SELECT
    PostId,
    COUNT(*) AS comment_count,
    SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS positive_comments
  FROM Comments
  GROUP BY PostId
),
badges_agg AS (
  SELECT
    UserId,
    COUNT(*) AS badges_total,
    COUNT(*) FILTER (WHERE Class = 1) AS gold,
    COUNT(*) FILTER (WHERE Class = 2) AS silver,
    COUNT(*) FILTER (WHERE Class = 3) AS bronze,
    SUM(
      CASE
        WHEN TagBased::text IN ('1','t','true','TRUE','True') THEN 1
        ELSE 0
      END
    ) AS tag_badges
  FROM Badges
  GROUP BY UserId
),
user_tag_answers AS (
  SELECT
    qt.tag,
    a.answer_owner AS user_id,
    COUNT(*) AS answers_count,
    COALESCE(SUM(a.answer_score),0) AS answers_score,
    COALESCE(SUM(a.is_accepted),0) AS accepted_count,
    MIN(a.answer_date) AS first_answer_date,
    MAX(a.answer_date) AS last_answer_date
  FROM answers a
  JOIN q_tags qt ON a.question_id = qt.question_id
  GROUP BY qt.tag, a.answer_owner
),
user_tag_questions AS (
  SELECT
    qt.tag,
    qt.OwnerUserId AS user_id,
    COUNT(*) AS questions_count,
    COALESCE(SUM(qt.Score),0) AS questions_score,
    COALESCE(SUM(qt.ViewCount),0) AS questions_views,
    MIN(qt.CreationDate) AS first_question_date,
    MAX(qt.CreationDate) AS last_question_date
  FROM q_tags qt
  GROUP BY qt.tag, qt.OwnerUserId
),
question_post_votes AS (
  SELECT
    qt.tag,
    qt.OwnerUserId AS user_id,
    SUM(COALESCE(v.upvotes,0)) AS upvotes,
    SUM(COALESCE(v.downvotes,0)) AS downvotes,
    SUM(COALESCE(v.total_votes,0)) AS total_votes
  FROM q_tags qt
  LEFT JOIN votes_agg v ON v.PostId = qt.question_id
  GROUP BY qt.tag, qt.OwnerUserId
),
answer_post_votes AS (
  SELECT
    qt.tag,
    a.answer_owner AS user_id,
    SUM(COALESCE(v.upvotes,0)) AS upvotes,
    SUM(COALESCE(v.downvotes,0)) AS downvotes,
    SUM(COALESCE(v.total_votes,0)) AS total_votes
  FROM answers a
  JOIN q_tags qt ON a.question_id = qt.question_id
  LEFT JOIN votes_agg v ON v.PostId = a.answer_id
  GROUP BY qt.tag, a.answer_owner
),
user_tag_votes AS (
  SELECT tag, user_id, SUM(upvotes) AS upvotes, SUM(downvotes) AS downvotes, SUM(total_votes) AS total_votes
  FROM (
    SELECT * FROM question_post_votes
    UNION ALL
    SELECT * FROM answer_post_votes
  ) x
  GROUP BY tag, user_id
),
question_post_comments AS (
  SELECT
    qt.tag,
    qt.OwnerUserId AS user_id,
    SUM(COALESCE(c.comment_count,0)) AS comment_count
  FROM q_tags qt
  LEFT JOIN comments_agg c ON c.PostId = qt.question_id
  GROUP BY qt.tag, qt.OwnerUserId
),
answer_post_comments AS (
  SELECT
    qt.tag,
    a.answer_owner AS user_id,
    SUM(COALESCE(c.comment_count,0)) AS comment_count
  FROM answers a
  JOIN q_tags qt ON a.question_id = qt.question_id
  LEFT JOIN comments_agg c ON c.PostId = a.answer_id
  GROUP BY qt.tag, a.answer_owner
),
user_tag_comments AS (
  SELECT tag, user_id, SUM(comment_count) AS comment_count
  FROM (
    SELECT * FROM question_post_comments
    UNION ALL
    SELECT * FROM answer_post_comments
  ) y
  GROUP BY tag, user_id
),
user_tag_agg AS (
  SELECT
    COALESCE(uta.tag, utq.tag) AS tag,
    COALESCE(uta.user_id, utq.user_id) AS user_id,
    COALESCE(utq.questions_count,0) AS questions_count,
    COALESCE(utq.questions_score,0) AS questions_score,
    COALESCE(utq.questions_views,0) AS questions_views,
    COALESCE(uta.answers_count,0) AS answers_count,
    COALESCE(uta.answers_score,0) AS answers_score,
    COALESCE(uta.accepted_count,0) AS accepted_count,
    COALESCE(v.upvotes,0) AS upvotes,
    COALESCE(v.downvotes,0) AS downvotes,
    COALESCE(v.total_votes,0) AS total_votes,
    COALESCE(uc.comment_count,0) AS comment_count,
    COALESCE(b.badges_total,0) AS badges_total,
    COALESCE(b.gold,0) AS gold_badges,
    COALESCE(b.silver,0) AS silver_badges,
    COALESCE(b.bronze,0) AS bronze_badges,
    COALESCE(b.tag_badges,0) AS tag_badges,
    GREATEST(utq.last_question_date, uta.last_answer_date) AS last_activity,
    COALESCE(LEAST(
      COALESCE(utq.first_question_date, 'infinity'::timestamp),
      COALESCE(uta.first_answer_date, 'infinity'::timestamp)
    ), NULL) AS first_activity
  FROM user_tag_answers uta
  FULL OUTER JOIN user_tag_questions utq
    ON uta.tag = utq.tag AND uta.user_id = utq.user_id
  LEFT JOIN user_tag_votes v
    ON COALESCE(uta.tag, utq.tag) = v.tag AND COALESCE(uta.user_id, utq.user_id) = v.user_id
  LEFT JOIN user_tag_comments uc
    ON COALESCE(uta.tag, utq.tag) = uc.tag AND COALESCE(uta.user_id, utq.user_id) = uc.user_id
  LEFT JOIN badges_agg b
    ON COALESCE(uta.user_id, utq.user_id) = b.UserId
),
user_tag_score AS (
  SELECT
    uta.*,
    COALESCE(EXTRACT(EPOCH FROM (NOW() - COALESCE(uta.last_activity, uta.first_activity)))/86400.0, 365.0) AS days_since_activity,
    (
      (COALESCE(answers_score,0) * 1.7)
      + (COALESCE(questions_score,0) * 0.8)
      + (COALESCE(accepted_count,0) * 12)
      + ((COALESCE(upvotes,0) - COALESCE(downvotes,0)) * 2.5)
      + (LN(GREATEST(COALESCE(questions_views,0),1)) * 0.3)
      + (GREATEST(COALESCE(badges_total,0),0) * 1.2)
      + (COALESCE(tag_badges,0) * 3.0)
    )::numeric AS raw_influence,
    (
      (
        (COALESCE(answers_score,0) * 1.7)
        + (COALESCE(questions_score,0) * 0.8)
        + (COALESCE(accepted_count,0) * 12)
        + ((COALESCE(upvotes,0) - COALESCE(downvotes,0)) * 2.5)
        + (LN(GREATEST(COALESCE(questions_views,0),1)) * 0.3)
        + (GREATEST(COALESCE(badges_total,0),0) * 1.2)
        + (COALESCE(tag_badges,0) * 3.0)
      ) * EXP(- (COALESCE(EXTRACT(EPOCH FROM (NOW() - COALESCE(uta.last_activity, uta.first_activity)))/86400.0, 365.0)) / 365.0)
    )::numeric AS decayed_influence,
    (
      ((COALESCE(answers_score,0) + COALESCE(questions_score,0))::numeric) /
      NULLIF(1 + COALESCE(answers_count,0) + COALESCE(questions_count,0), 0)
    )::numeric AS avg_score_per_post,
    (
      SELECT co.tag
      FROM q_tags co
      WHERE co.tag <> uta.tag
        AND EXISTS (
          SELECT 1
          FROM q_tags myq
          WHERE myq.tag = uta.tag
            AND myq.question_id = co.question_id
            AND (
              EXISTS (SELECT 1 FROM answers a2 WHERE a2.answer_owner = uta.user_id AND a2.question_id = myq.question_id)
              OR EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = uta.user_id AND p2.Id = myq.question_id)
            )
        )
      GROUP BY co.tag
      ORDER BY COUNT(*) DESC
      LIMIT 1
    ) AS favorite_cotag
  FROM user_tag_agg uta
),
tag_overview AS (
  SELECT
    tag,
    COUNT(*) AS contributors,
    SUM(questions_count) AS tag_total_questions,
    SUM(answers_count) AS tag_total_answers,
    SUM(questions_views) AS tag_total_views,
    SUM(answers_score) AS tag_total_answer_score,
    SUM(questions_score) AS tag_total_question_score
  FROM user_tag_agg
  GROUP BY tag
),
tag_influence_totals AS (
  SELECT tag, SUM(decayed_influence) AS sum_decayed
  FROM user_tag_score
  GROUP BY tag
),
emerging AS (
  SELECT tag, user_id
  FROM user_tag_score
  WHERE days_since_activity <= 180 AND decayed_influence > 2
),
established AS (
  SELECT tag, user_id
  FROM user_tag_score
  WHERE decayed_influence > 30
),
emerging_contributors AS (
  SELECT * FROM emerging
  EXCEPT
  SELECT * FROM established
)
SELECT *
FROM (
  SELECT
    uts.tag,
    uts.user_id,
    u.DisplayName,
    COALESCE(uts.questions_count,0) AS questions_count,
    COALESCE(uts.answers_count,0) AS answers_count,
    COALESCE(uts.questions_score,0) AS questions_score,
    COALESCE(uts.answers_score,0) AS answers_score,
    COALESCE(uts.accepted_count,0) AS accepted_count,
    COALESCE(uts.upvotes,0) AS upvotes,
    COALESCE(uts.downvotes,0) AS downvotes,
    COALESCE(uts.comment_count,0) AS comment_count,
    COALESCE(uts.badges_total,0) AS badges_total,
    uts.raw_influence,
    uts.decayed_influence,
    uts.avg_score_per_post,
    COALESCE(tit.sum_decayed, NULLIF(0,0)) AS tag_total_decayed,
    (uts.decayed_influence / NULLIF(tit.sum_decayed,0))::numeric(18,6) AS share_of_tag,
    ROW_NUMBER() OVER (PARTITION BY uts.tag ORDER BY uts.decayed_influence DESC, uts.raw_influence DESC NULLS LAST) AS tag_rank,
    DENSE_RANK() OVER (ORDER BY uts.decayed_influence DESC) AS global_rank,
    NTILE(100) OVER (PARTITION BY uts.tag ORDER BY uts.decayed_influence DESC) AS pct_in_tag,
    CASE WHEN ec.user_id IS NOT NULL THEN true ELSE false END AS is_emerging,
    uts.favorite_cotag,
    tag_overview.tag_total_questions,
    tag_overview.tag_total_answers,
    tag_overview.tag_total_views,
    -- correlated top post snippet (expensive text ops + regex)
    COALESCE(tp.top_post_id, NULL) AS top_post_id,
    COALESCE(tp.top_post_snippet, '') AS top_post_snippet,
    COALESCE(tp.top_post_type, '') AS top_post_type
  FROM user_tag_score uts
  JOIN Users u ON u.Id = uts.user_id
  JOIN tag_overview ON tag_overview.tag = uts.tag
  LEFT JOIN tag_influence_totals tit ON tit.tag = uts.tag
  LEFT JOIN emerging_contributors ec ON ec.tag = uts.tag AND ec.user_id = uts.user_id
  LEFT JOIN LATERAL (
    SELECT p.Id AS top_post_id,
           CASE WHEN p.Body IS NOT NULL THEN substring(regexp_replace(p.Body, '<[^>]*>', '', 'g') FROM 1 FOR 240)
                ELSE COALESCE(p.Title, '') END AS top_post_snippet,
           CASE WHEN p.PostTypeId = 1 THEN 'question' WHEN p.PostTypeId = 2 THEN 'answer' ELSE 'other' END AS top_post_type,
           ((COALESCE(v.upvotes,0) - COALESCE(v.downvotes,0)) * 2 + COALESCE(p.Score,0) + (CASE WHEN p.Id = parent.AcceptedAnswerId THEN 40 ELSE 0 END)) AS post_metric
    FROM Posts p
    LEFT JOIN Posts parent ON p.ParentId = parent.Id
    LEFT JOIN votes_agg v ON v.PostId = p.Id
    WHERE p.OwnerUserId = uts.user_id
      AND (
        (p.PostTypeId = 1 AND EXISTS (SELECT 1 FROM q_tags q WHERE q.question_id = p.Id AND q.tag = uts.tag))
        OR
        (p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM q_tags q WHERE q.question_id = p.ParentId AND q.tag = uts.tag))
      )
    ORDER BY post_metric DESC NULLS LAST
    LIMIT 1
  ) tp ON true
  WHERE tag_overview.tag_total_questions >= 10
    AND uts.decayed_influence > 0.5
    AND uts.tag IS NOT NULL
    AND uts.user_id IS NOT NULL
) ranked
WHERE tag_rank <= 5
ORDER BY tag ASC, tag_rank ASC;