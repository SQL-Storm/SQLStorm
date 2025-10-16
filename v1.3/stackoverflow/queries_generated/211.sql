-- {"query": "211.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5088} 
WITH parsed_posts AS (
  SELECT p.*,
    COALESCE(NULLIF(p.Tags,''), '') AS raw_tags,
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::varchar[] ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') END AS tag_arr,
    COALESCE(array_length(CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') END,1),0) AS tag_count
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_exploded AS (
  SELECT pp.Id as QuestionId, unnest(pp.tag_arr) AS tag
  FROM parsed_posts pp
),
votes_summary AS (
  SELECT v.PostId,
    COUNT(*) FILTER (WHERE v.VoteTypeId=2) AS upvotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId=3) AS downvotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId=5) AS favorites,
    COUNT(*) AS total_votes,
    SUM(coalesce(v.BountyAmount,0)) AS total_bounty
  FROM Votes v
  GROUP BY v.PostId
),
answers_ranks AS (
  SELECT a.Id, a.ParentId, a.Score, length(coalesce(a.Body,'')) AS body_len,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.Id ASC) AS rnk
  FROM Posts a
  WHERE a.PostTypeId = 2
),
answers_summary AS (
  SELECT ParentId AS QuestionId,
    COUNT(*) FILTER (WHERE Score>0) AS positive_answers,
    COUNT(*) AS answers_count,
    AVG(body_len) AS avg_answer_body_len,
    MAX(Score) AS max_answer_score,
    MAX(Id) FILTER (WHERE rnk = 1) AS top_answer_id
  FROM answers_ranks
  GROUP BY ParentId
),
user_activity AS (
  SELECT u.Id as UserId, u.DisplayName, u.Reputation,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=1) AS questions,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId=2) AS answers,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rep_rank,
    COALESCE(MAX(p.CreationDate), u.CreationDate) AS last_contribution
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
tag_tagcounts AS (
  SELECT t.tag, COUNT(DISTINCT te.QuestionId) AS questions_with_tag
  FROM tag_exploded t
  GROUP BY t.tag
),
tag_join_tags AS (
  SELECT t.tag, tt.TagName IS NULL AS missing_in_tags_table, tt.Id AS tag_id, t.questions_with_tag
  FROM tag_tagcounts t
  LEFT JOIN Tags tt ON tt.TagName = t.tag
),
complex_questions AS (
  SELECT q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.ViewCount, q.Score,
    q.tag_count, array_to_string(q.tag_arr,',') AS tags_csv,
    vs.upvotes, vs.downvotes, vs.favorites, vs.total_votes, vs.total_bounty,
    asu.answers_count, asu.positive_answers, asu.avg_answer_body_len, asu.max_answer_score, asu.top_answer_id,
    ROW_NUMBER() OVER (ORDER BY COALESCE(vs.upvotes,0) - COALESCE(vs.downvotes,0) DESC, q.Score DESC, q.ViewCount DESC) as popularity_rank,
    CASE WHEN q.ClosedDate IS NOT NULL THEN 'closed' ELSE 'open' END AS state,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id AND c.CreationDate >= q.CreationDate - INTERVAL '7 days') AS comments_first_week,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4,5,6) AND ph.CreationDate > q.CreationDate) AS edits_after_creation
  FROM parsed_posts q
  LEFT JOIN votes_summary vs ON vs.PostId = q.Id
  LEFT JOIN answers_summary asu ON asu.QuestionId = q.Id
),
user_badge_rank AS (
  SELECT b.UserId, COUNT(*) AS badges_count,
    SUM(CASE WHEN b.Class=1 THEN 3 WHEN b.Class=2 THEN 2 ELSE 1 END) AS badge_score,
    MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
latest_edits AS (
  SELECT ph.PostId, MAX(ph.CreationDate) AS last_edit_date,
    STRING_AGG(DISTINCT COALESCE(ph.UserDisplayName, (SELECT DisplayName FROM Users uu WHERE uu.Id=ph.UserId)), ' | ') AS editors
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,24,66)
  GROUP BY ph.PostId
),
inter_tag_pairs AS (
  SELECT te1.tag AS tag1, te2.tag AS tag2, COUNT(DISTINCT te1.QuestionId) AS cooccurrence
  FROM tag_exploded te1
  JOIN tag_exploded te2 ON te1.QuestionId = te2.QuestionId AND te1.tag < te2.tag
  GROUP BY te1.tag, te2.tag
  HAVING COUNT(DISTINCT te1.QuestionId) > 5
),
ranked_users AS (
  SELECT ua.*,
    RANK() OVER (ORDER BY ua.questions DESC, ua.answers DESC, ua.Reputation DESC) AS activity_rank
  FROM user_activity ua
),
final_questions AS (
  SELECT cq.*,
    COALESCE(lb.editors,'{unknown}') AS editors,
    COALESCE(ub.badges_count,0) AS owner_badges,
    COALESCE(ub.badge_score,0) AS owner_badge_score,
    u.DisplayName AS owner_name,
    u.Location,
    u.Reputation AS owner_reputation,
    CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = cq.Id AND pl.LinkTypeId = 3) THEN TRUE ELSE FALSE END AS has_duplicates,
    (CASE WHEN cq.top_answer_id IS NOT NULL THEN (SELECT Body FROM Posts p2 WHERE p2.Id = cq.top_answer_id) ELSE NULL END) AS top_answer_body
  FROM complex_questions cq
  LEFT JOIN latest_edits lb ON lb.PostId = cq.Id
  LEFT JOIN user_badge_rank ub ON ub.UserId = cq.OwnerUserId
  LEFT JOIN Users u ON u.Id = cq.OwnerUserId
)
SELECT 'TAG_SUMMARY' AS kind, tj.tag AS key, tj.questions_with_tag AS metric, NULL::text AS extra, NULL::int AS rank FROM tag_join_tags tj
UNION ALL
SELECT 'TAG_PAIR' AS kind, (it.tag1 || '&&' || it.tag2) AS key, it.cooccurrence AS metric, NULL::text, NULL::int FROM inter_tag_pairs it
UNION ALL
SELECT 'QUESTION_TOP' AS kind, ('Q:' || fq.Id::text || ':' || COALESCE(NULLIF(fq.Title,''),'(no title)')) AS key,
  fq.popularity_rank AS metric,
  ('owner='||COALESCE(fq.owner_name,'[anon]')||
   ';tags='||COALESCE(fq.tags_csv,'')||
   ';up='||COALESCE(fq.upvotes,0)::text||
   ';down='||COALESCE(fq.downvotes,0)::text||
   ';votes='||COALESCE(fq.total_votes,0)::text||
   ';answers='||COALESCE(fq.answers_count,0)::text||
   ';edits='||COALESCE(fq.edits_after_creation,0)::text
  ) AS extra,
  fq.owner_badge_score AS rank
FROM final_questions fq
WHERE fq.popularity_rank <= 250
ORDER BY kind, metric DESC
LIMIT 1000;