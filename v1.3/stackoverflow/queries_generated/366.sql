-- {"query": "366.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 13242} 
WITH
  all_question_tags AS (
    SELECT q.Id AS PostId,
           COALESCE(q.OwnerUserId, -1) AS OwnerUserId,
           lower(trim(tg)) AS Tag,
           q.Score, q.ViewCount, q.CreationDate
    FROM Posts q
    CROSS JOIN LATERAL (
      SELECT unnest(
        CASE
          WHEN q.Tags IS NULL OR char_length(q.Tags) < 2 THEN ARRAY[]::text[]
          ELSE string_to_array(substring(q.Tags FROM 2 FOR greatest(char_length(q.Tags) - 2, 0)), '><')
        END
      ) AS tg
    ) u
    WHERE q.PostTypeId = 1
  ),

  tag_stats AS (
    SELECT Tag, count(*) AS questions, sum(ViewCount) AS total_views, avg(Score) AS avg_score, max(Score) AS max_score
    FROM all_question_tags
    GROUP BY Tag
  ),

  user_post_agg AS (
    SELECT usr.Id AS UserId, usr.DisplayName,
           count(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions,
           count(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers,
           COALESCE(sum(p.Score),0) AS total_score,
           COALESCE(sum(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END),0) AS views_on_questions,
           min(p.CreationDate) AS first_post,
           max(p.CreationDate) AS last_post,
           count(distinct CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS distinct_questions_count,
           count(distinct CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS distinct_answers_count
    FROM Users usr
    LEFT JOIN Posts p ON p.OwnerUserId = usr.Id
    GROUP BY usr.Id, usr.DisplayName
  ),

  badge_summary AS (
    SELECT b.UserId,
           count(*) AS badges_total,
           count(*) FILTER (WHERE b.Class = 1) AS gold,
           count(*) FILTER (WHERE b.Class = 2) AS silver,
           count(*) FILTER (WHERE b.Class = 3) AS bronze
    FROM Badges b
    GROUP BY b.UserId
  ),

  candidate_answers AS (
    SELECT a.Id AS AnswerId,
           a.ParentId AS QuestionId,
           a.OwnerUserId,
           a.Score,
           a.CreationDate,
           row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS rn,
           avg(a.Score) OVER (PARTITION BY a.ParentId) AS avg_ans_score_for_question,
           percentile_disc(0.5) WITHIN GROUP (ORDER BY a.Score) OVER (PARTITION BY a.ParentId) AS median_ans_score_for_question
    FROM Posts a
    WHERE a.PostTypeId = 2
  ),

  best_answers_per_question AS (
    SELECT AnswerId, QuestionId, OwnerUserId, Score, CreationDate, avg_ans_score_for_question, median_ans_score_for_question
    FROM candidate_answers
    WHERE rn = 1
  ),

  recent_vote_rollup AS (
    SELECT v.PostId,
           sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_last_year,
           sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_last_year,
           count(*) AS total_votes_last_year
    FROM Votes v
    WHERE v.CreationDate >= now() - interval '365 days'
    GROUP BY v.PostId
  ),

  duplicate_chains AS (
    SELECT pl.PostId AS root, pl.RelatedPostId AS dup, ARRAY[pl.PostId, pl.RelatedPostId]::int[] AS path, 1 AS depth
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    UNION ALL
    SELECT dc.root, pl.RelatedPostId, dc.path || pl.RelatedPostId, dc.depth + 1
    FROM duplicate_chains dc
    JOIN PostLinks pl ON pl.PostId = dc.dup AND pl.LinkTypeId = 3
    WHERE NOT pl.RelatedPostId = ANY(dc.path)
      AND dc.depth < 8
  ),

  duplicate_summary AS (
    SELECT root, array_agg(DISTINCT dup) AS duplicates, count(DISTINCT dup) AS dup_count, min(depth) AS min_depth
    FROM duplicate_chains
    GROUP BY root
  ),

  recent_answerers AS (
    SELECT DISTINCT OwnerUserId AS UserId
    FROM Posts
    WHERE PostTypeId = 2 AND CreationDate >= now() - interval '180 days' AND OwnerUserId IS NOT NULL
  ),

  recent_askers AS (
    SELECT DISTINCT OwnerUserId AS UserId
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= now() - interval '180 days' AND OwnerUserId IS NOT NULL
  ),

  recent_active_users AS (
    (
      SELECT UserId FROM recent_answerers
      UNION
      SELECT UserId FROM recent_askers
    )
    EXCEPT
    SELECT Id FROM Users WHERE Reputation < 50
  ),

  user_score_calc AS (
    SELECT upa.UserId, upa.DisplayName, upa.questions, upa.answers, upa.total_score, upa.views_on_questions,
           COALESCE(bs.badges_total,0) AS badges_total,
           (COALESCE(upa.total_score,0) * 1.2 + COALESCE(bs.badges_total,0) * 8 + COALESCE(upa.answers,0) * 2.5 + sqrt(COALESCE(upa.views_on_questions,0)::numeric)) AS score_val
    FROM user_post_agg upa
    LEFT JOIN badge_summary bs ON bs.UserId = upa.UserId
  ),

  top_user_ranked AS (
    SELECT usc.*,
           rank() OVER (ORDER BY score_val DESC NULLS LAST) AS rank_global,
           ntile(10) OVER (ORDER BY score_val DESC) AS decile,
           percent_rank() OVER (ORDER BY score_val DESC) AS pct_rank
    FROM user_score_calc usc
  ),

  high_scorers AS (
    SELECT UserId FROM top_user_ranked WHERE score_val >= (SELECT COALESCE(max(score_val),0) * 0.10 FROM user_score_calc)
  ),

  influential_users AS (
    SELECT UserId FROM high_scorers
    INTERSECT
    SELECT UserId FROM recent_active_users
  ),

  user_tag_agg AS (
    SELECT OwnerUserId AS UserId, Tag, count(*) AS cnt
    FROM all_question_tags
    GROUP BY OwnerUserId, Tag
  )

SELECT
  ur.rank_global,
  ur.UserId,
  COALESCE(u.DisplayName, ur.displayname, '(unknown)') AS DisplayName,
  u.Reputation,
  round(ur.score_val,2) AS CompositeScore,
  ur.questions, ur.answers, ur.total_score,
  COALESCE(bs.gold,0) AS GoldBadges, COALESCE(bs.silver,0) AS SilverBadges, COALESCE(bs.bronze,0) AS BronzeBadges,
  COALESCE(tt.Tag, '(none)') AS TopTag,
  COALESCE(tt.cnt,0) AS TopTagCount,
  tq.qid AS TopQuestionId,
  tq.Title AS TopQuestionTitle,
  COALESCE(tq.ViewCount,0) AS TopQuestionViews,
  COALESCE(tq.Score,0) AS TopQuestionScore,
  COALESCE(tac.top_answers_count,0) AS TopAnswersInLastYear,
  COALESCE(du.total_duplicates,0) AS DuplicateCount,
  closed.has_closed AS HasClosedPosts,
  COALESCE(avg_ans.avg_user_answer_score, 0) AS AvgAnswerScoreByUser,
  COALESCE(round(((char_length(COALESCE(u.AboutMe,'')) - char_length(replace(COALESCE(u.AboutMe,''),'http','')))::double precision / 4.0)::numeric,2),0) AS ApproxUrlsInAboutMe,
  concat_ws(' | ', COALESCE(u.Location,'(no location)'), COALESCE(NULLIF(u.WebsiteUrl,''),'(no website)'), 'acct:' || COALESCE(u.AccountId::text,'N/A')) AS UserContactSummary,
  ur.decile, ur.pct_rank,
  row_number() OVER (ORDER BY ur.score_val DESC) AS global_rownum
FROM top_user_ranked ur
JOIN Users u ON u.Id = ur.UserId
LEFT JOIN badge_summary bs ON bs.UserId = ur.UserId
LEFT JOIN LATERAL (
  SELECT Tag, cnt FROM user_tag_agg uta WHERE uta.UserId = ur.UserId ORDER BY cnt DESC NULLS LAST, Tag LIMIT 1
) tt ON true
LEFT JOIN LATERAL (
  SELECT p.Id AS qid, p.Title, p.ViewCount, p.Score, p.CreationDate,
         string_agg(DISTINCT at.Tag, ',' ORDER BY at.Tag) AS tags
  FROM Posts p
  LEFT JOIN all_question_tags at ON at.PostId = p.Id
  WHERE p.OwnerUserId = ur.UserId AND p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.ViewCount, p.Score, p.CreationDate
  ORDER BY p.ViewCount DESC NULLS LAST, p.Score DESC NULLS LAST
  LIMIT 1
) tq ON true
LEFT JOIN LATERAL (
  SELECT count(*) AS top_answers_count
  FROM Posts a
  WHERE a.PostTypeId = 2 AND a.OwnerUserId = ur.UserId
    AND a.Score >= (SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 2)
    AND a.CreationDate >= now() - interval '365 days'
) tac ON true
LEFT JOIN LATERAL (
  SELECT COALESCE(sum(ds.dup_count),0) AS total_duplicates
  FROM duplicate_summary ds
  WHERE ds.root IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ur.UserId)
) du ON true
LEFT JOIN LATERAL (
  SELECT exists(
    SELECT 1 FROM PostHistory ph
    WHERE ph.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ur.UserId)
      AND ph.PostHistoryTypeId = 10
  ) AS has_closed
) closed ON true
LEFT JOIN LATERAL (
  SELECT avg(a.Score)::numeric AS avg_user_answer_score
  FROM Posts a
  WHERE a.PostTypeId = 2 AND a.OwnerUserId = ur.UserId
) avg_ans ON true
WHERE (ur.rank_global <= 200 OR ur.UserId IN (SELECT UserId FROM influential_users))
ORDER BY ur.score_val DESC NULLS LAST, ur.rank_global
LIMIT 200;