-- {"query": "370.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20509} 
WITH
  questions AS (
    SELECT * FROM Posts WHERE PostTypeId = 1
  ),
  answers AS (
    SELECT * FROM Posts WHERE PostTypeId = 2
  ),
  vote_summ AS (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
      SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
      SUM(CASE WHEN VoteTypeId IN (8,9) THEN COALESCE(BountyAmount,0) ELSE 0 END) AS bounty_total,
      COUNT(*) AS votes_total
    FROM Votes
    GROUP BY PostId
  ),
  comment_summ AS (
    SELECT
      PostId,
      COUNT(*) AS comment_count,
      COUNT(DISTINCT UserId) AS distinct_commenters,
      MAX(CreationDate) AS last_comment_date
    FROM Comments
    GROUP BY PostId
  ),
  answer_stats AS (
    SELECT
      ParentId AS QuestionId,
      COUNT(*) AS answer_count,
      AVG(Score) AS avg_answer_score,
      MAX(Score) AS max_answer_score,
      MIN(Score) AS min_answer_score,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY Score) AS median_answer_score
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ),
  history_counts AS (
    SELECT
      PostId,
      SUM(CASE WHEN PostHistoryTypeId IN (4,5,24) THEN 1 ELSE 0 END) AS edit_events,
      SUM(CASE WHEN PostHistoryTypeId IN (10,11,12,13) THEN 1 ELSE 0 END) AS close_delete_events,
      SUM(CASE WHEN PostHistoryTypeId = 50 THEN 1 ELSE 0 END) AS community_bumps
    FROM PostHistory
    GROUP BY PostId
  ),
  link_counts AS (
    SELECT
      PostId,
      SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS linked_count,
      SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicate_count,
      COUNT(*) AS total_links,
      array_agg(DISTINCT RelatedPostId) FILTER (WHERE LinkTypeId = 3) AS duplicates_array
    FROM PostLinks
    GROUP BY PostId
  ),
  question_tags AS (
    SELECT
      q.Id AS QuestionId,
      lower(trim(t.tag)) AS tag,
      row_number() OVER (PARTITION BY q.Id ORDER BY lower(trim(t.tag))) AS tag_rank
    FROM questions q
    LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(substring(q.Tags, 2, GREATEST(length(q.Tags) - 2, 0)), '><')) AS tag
    ) t ON q.Tags IS NOT NULL AND length(q.Tags) > 2
    WHERE t.tag IS NOT NULL
  ),
  tag_agg AS (
    SELECT
      QuestionId,
      count(*) AS tag_count,
      string_agg(tag, ',' ORDER BY tag) AS tag_list
    FROM question_tags
    GROUP BY QuestionId
  ),
  owner_questions AS (
    SELECT OwnerUserId AS UserId, COUNT(*) AS questions_by_owner
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ),
  owner_answers AS (
    SELECT OwnerUserId AS UserId, COUNT(*) AS answers_by_owner
    FROM Posts
    WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ),
  owner_metrics AS (
    SELECT
      COALESCE(q.UserId, a.UserId) AS UserId,
      COALESCE(q.questions_by_owner, 0) AS questions_by_owner,
      COALESCE(a.answers_by_owner, 0) AS answers_by_owner
    FROM owner_questions q
    FULL JOIN owner_answers a ON q.UserId = a.UserId
  ),
  accepted_delays AS (
    SELECT
      q.Id AS QuestionId,
      CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0 ELSE NULL END AS accepted_age_hours
    FROM questions q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
  ),
  candidate_questions AS (
    SELECT
      q.*,
      COALESCE(vs.upvotes,0) AS upvotes,
      COALESCE(vs.downvotes,0) AS downvotes,
      COALESCE(vs.favorites,0) AS favorites,
      COALESCE(cs.comment_count,0) AS comment_count,
      COALESCE(ans.answer_count,0) AS computed_answer_count,
      COALESCE(hc.edit_events,0) AS edit_events,
      COALESCE(lc.linked_count,0) AS linked_count,
      COALESCE(ta.tag_count,0) AS tag_count,
      COALESCE(ta.tag_list,'') AS tag_list
    FROM questions q
    LEFT JOIN vote_summ vs ON vs.PostId = q.Id
    LEFT JOIN comment_summ cs ON cs.PostId = q.Id
    LEFT JOIN answer_stats ans ON ans.QuestionId = q.Id
    LEFT JOIN history_counts hc ON hc.PostId = q.Id
    LEFT JOIN link_counts lc ON lc.PostId = q.Id
    LEFT JOIN tag_agg ta ON ta.QuestionId = q.Id
  ),
  scored_questions AS (
    SELECT
      cq.*,
      COALESCE(ans.avg_answer_score,0) AS avg_answer_score,
      COALESCE(ans.median_answer_score,0) AS median_answer_score,
      COALESCE(owner.questions_by_owner,0) AS owner_total_questions,
      COALESCE(owner.answers_by_owner,0) AS owner_total_answers,
      ad.accepted_age_hours,
      EXTRACT(EPOCH FROM (current_timestamp - cq.CreationDate))/3600.0 AS age_hours,
      EXTRACT(EPOCH FROM (current_timestamp - COALESCE(cq.LastActivityDate, cq.CreationDate)))/3600.0 AS last_activity_age_hours,
      char_length(regexp_replace(COALESCE(cq.Body,''), '<[^>]+>', ' ', 'g')) AS plain_body_length,
      ((char_length(COALESCE(cq.Body,'')) - char_length(replace(COALESCE(cq.Body,''), '<code>',''))) / 6)::int AS code_tag_count,
      (
        LEAST(15, LN(COALESCE(cq.ViewCount,0) + 1)) * 1.25
        + COALESCE(cq.Score,0) * 2.2
        + COALESCE(cq.upvotes,0) * 1.6
        - COALESCE(cq.downvotes,0) * 1.2
        + COALESCE(ans.answer_count,0) * 2.9
        + COALESCE(cq.favorites,0) * 3.1
        + COALESCE(ans.median_answer_score,0) * 0.8
        + CASE WHEN cq.AcceptedAnswerId IS NOT NULL THEN 9 ELSE 0 END
        - LEAST(336, EXTRACT(EPOCH FROM (current_timestamp - COALESCE(cq.LastActivityDate, cq.CreationDate)))/3600.0) * 0.03
        + COALESCE(ta.tag_count, 0) * 0.4
        - COALESCE(lc.duplicate_count,0) * 1.7
      ) AS hotness_score
    FROM candidate_questions cq
    LEFT JOIN answer_stats ans ON ans.QuestionId = cq.Id
    LEFT JOIN owner_metrics owner ON owner.UserId = cq.OwnerUserId
    LEFT JOIN accepted_delays ad ON ad.QuestionId = cq.Id
    LEFT JOIN link_counts lc ON lc.PostId = cq.Id
    LEFT JOIN tag_agg ta ON ta.QuestionId = cq.Id
  ),
  top_views AS (
    SELECT Id FROM questions ORDER BY ViewCount DESC NULLS LAST LIMIT 200
  ),
  top_answers_by_count AS (
    SELECT QuestionId AS Id FROM answer_stats ORDER BY answer_count DESC NULLS LAST LIMIT 200
  ),
  popular_and_answered AS (
    SELECT Id FROM top_views
    INTERSECT
    SELECT Id FROM top_answers_by_count
  ),
  final_candidates AS (
    SELECT sq.* FROM scored_questions sq
    WHERE sq.Id IN (SELECT Id FROM popular_and_answered)
       OR sq.hotness_score >= (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY hotness_score) FROM scored_questions)
       OR sq.tag_list ILIKE '%sql%'
  ),
  question_output AS (
    SELECT
      sq.Id::text AS id_text,
      'question' AS kind,
      COALESCE(sq.Title, '(no title)') AS title,
      COALESCE(u.DisplayName, sq.OwnerDisplayName, 'community') AS owner_name,
      u.Reputation AS owner_reputation,
      COALESCE(sq.Score,0) AS score,
      COALESCE(sq.ViewCount,0) AS views,
      COALESCE(sq.upvotes,0) AS upvotes,
      COALESCE(sq.downvotes,0) AS downvotes,
      COALESCE(sq.AnswerCount,0) AS declared_answer_count,
      COALESCE(sq.computed_answer_count,0) AS computed_answer_count,
      COALESCE(sq.comment_count,0) AS comment_count,
      sq.avg_answer_score,
      sq.median_answer_score,
      sq.accepted_age_hours,
      sq.tag_count,
      sq.tag_list,
      sq.hotness_score,
      DENSE_RANK() OVER (ORDER BY sq.hotness_score DESC) AS hot_rank,
      sq.owner_total_questions,
      sq.owner_total_answers,
      COALESCE(le.DisplayName, sq.LastEditorDisplayName, u.DisplayName) AS last_editor,
      sq.code_tag_count,
      sq.plain_body_length,
      left(regexp_replace(COALESCE(sq.Body,''), '<[^>]+>', ' ', 'g'), 240) AS snippet,
      (SELECT c.UserId FROM Comments c WHERE c.PostId = sq.Id GROUP BY c.UserId ORDER BY COUNT(*) DESC LIMIT 1) AS top_commenter,
      (SELECT string_agg(CAST(RelatedPostId AS text), ',' ORDER BY RelatedPostId) FROM PostLinks pl WHERE pl.PostId = sq.Id AND pl.LinkTypeId = 3) AS duplicates_list,
      concat('{score:', COALESCE(sq.Score::text,'0'), ',views:', COALESCE(sq.ViewCount::text,'0'), ',up:', COALESCE(sq.upvotes::text,'0'), '}') AS quick_snapshot
    FROM final_candidates sq
    LEFT JOIN Users u ON u.Id = sq.OwnerUserId
    LEFT JOIN Users le ON le.Id = sq.LastEditorUserId
  ),
  tag_output AS (
    SELECT
      ('tag-' || t.Id)::text AS id_text,
      'tag' AS kind,
      t.TagName AS title,
      NULL::text AS owner_name,
      NULL::int AS owner_reputation,
      t.Count AS score,
      NULL::bigint AS views,
      NULL::int AS upvotes,
      NULL::int AS downvotes,
      NULL::int AS declared_answer_count,
      NULL::int AS computed_answer_count,
      NULL::int AS comment_count,
      NULL::numeric AS avg_answer_score,
      NULL::numeric AS median_answer_score,
      NULL::numeric AS accepted_age_hours,
      NULL::int AS tag_count,
      t.TagName AS tag_list,
      t.Count * 0.5 AS hotness_score,
      ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS hot_rank,
      NULL::int AS owner_total_questions,
      NULL::int AS owner_total_answers,
      NULL::text AS last_editor,
      NULL::int AS code_tag_count,
      NULL::int AS plain_body_length,
      left(coalesce((SELECT regexp_replace(p.Body,'<[^>]+>',' ','g') FROM Posts p WHERE p.Id = t.ExcerptPostId LIMIT 1), t.TagName), 240) AS snippet,
      NULL::int AS top_commenter,
      NULL::text AS duplicates_list,
      concat('{tag_count:', t.Count::text, ',excerpt_post:', COALESCE(t.ExcerptPostId::text,'null'), '}') AS quick_snapshot
    FROM Tags t
    WHERE t.Count > 10
    ORDER BY t.Count DESC
    LIMIT 50
  ),
  negative_trending AS (
    SELECT Id FROM scored_questions WHERE Score < 0 AND (upvotes - downvotes) < 2
    EXCEPT
    SELECT Id FROM scored_questions WHERE EXTRACT(EPOCH FROM (current_timestamp - COALESCE(LastActivityDate, CreationDate)))/3600.0 < 72
  )
SELECT * FROM question_output
UNION ALL
SELECT * FROM tag_output
ORDER BY hotness_score DESC NULLS LAST, kind, hot_rank
LIMIT 200;