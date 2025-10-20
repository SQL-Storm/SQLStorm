WITH tag_expansion AS (
  SELECT p.Id AS PostId, p.OwnerUserId, TRIM(t) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
top_site_tags AS (
  (SELECT TagName AS tag FROM Tags WHERE Count > 50)
  UNION
  (SELECT tag FROM tag_expansion GROUP BY tag HAVING COUNT(*) > 50)
  EXCEPT
  (SELECT CAST('obsolete' AS varchar))
),
user_tag_stats AS (
  SELECT te.OwnerUserId AS UserId,
    COUNT(*) AS total_tag_uses,
    COUNT(DISTINCT te.tag) AS distinct_tags,
    STRING_AGG(te.tag, ', ' ORDER BY tag_count DESC) FILTER (WHERE te.tag IS NOT NULL) AS tags_by_freq,
    MAX(CASE WHEN te.tag IN (SELECT tag FROM top_site_tags) THEN te.tag ELSE NULL END) AS top_known_tag
  FROM (
    SELECT OwnerUserId, tag, COUNT(*) AS tag_count
    FROM tag_expansion
    GROUP BY OwnerUserId, tag
  ) te
  GROUP BY te.OwnerUserId
),
posts_summary AS (
  SELECT p.OwnerUserId AS UserId,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions_count,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
    COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1), 0) AS avg_score_questions,
    COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2), 0) AS avg_score_answers,
    COUNT(DISTINCT p.Id) AS total_posts,
    MAX(p.CreationDate) AS last_post_date,
    MIN(p.CreationDate) AS first_post_date
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
badges_summary AS (
  SELECT b.UserId,
    COUNT(*) AS total_badges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
    SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS tag_based_badges,
    MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
votes_summary AS (
  SELECT u.Id AS UserId,
    COALESCE(v_up.upvotes_on_my_posts, 0) AS upvotes_received,
    COALESCE(v_down.downvotes_on_my_posts, 0) AS downvotes_received,
    COUNT(v_cast.Id) AS votes_cast
  FROM Users u
  LEFT JOIN (
    SELECT p.OwnerUserId uid, COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes_on_my_posts
    FROM Posts p JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
  ) v_up ON v_up.uid = u.Id
  LEFT JOIN (
    SELECT p.OwnerUserId uid, COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes_on_my_posts
    FROM Posts p JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
  ) v_down ON v_down.uid = u.Id
  LEFT JOIN Votes v_cast ON v_cast.UserId = u.Id
  GROUP BY u.Id, v_up.upvotes_on_my_posts, v_down.downvotes_on_my_posts
),
top_commenters AS (
  SELECT AuthorId, CommenterId, cnt,
    ROW_NUMBER() OVER (PARTITION BY AuthorId ORDER BY cnt DESC) AS rn
  FROM (
    SELECT p.OwnerUserId AS AuthorId, c.UserId AS CommenterId, COUNT(*) AS cnt
    FROM Posts p
    JOIN Comments c ON c.PostId = p.Id AND c.UserId IS NOT NULL
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, c.UserId
  ) sub
),
top_commenters_agg AS (
  SELECT AuthorId AS UserId,
    STRING_AGG(CAST(CommenterId AS varchar) || ':' || CAST(cnt AS varchar), ',') AS top_commenters_list
  FROM top_commenters
  WHERE rn <= 3
  GROUP BY AuthorId
),
user_ranking AS (
  SELECT u.Id, u.Reputation,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS reputation_rank,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) AS reputation_percentile
  FROM Users u
),
answer_acceptance AS (
  SELECT u.Id AS UserId,
    (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = a.Id)) AS accepted_answers,
    (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) AS answers_count_check
  FROM Users u
),
answer_median AS (
  SELECT u.Id AS UserId,
    (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY a.Score) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) AS median_answer_score
  FROM Users u
),
latest_post_title AS (
  SELECT u.Id AS UserId,
    (SELECT p2.Title FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Title IS NOT NULL ORDER BY p2.CreationDate DESC LIMIT 1) AS latest_title
  FROM Users u
),
posts_extended AS (
  SELECT p.*,
    COALESCE(p.Score, 0) * (CASE WHEN p.PostTypeId = 1 THEN 1.0 WHEN p.PostTypeId = 2 THEN 0.8 ELSE 0.5 END) +
    CAST(COALESCE(p.ViewCount, 0) AS double precision) / NULLIF(COALESCE(p.Score, 0) + 1, 0) AS engagement_index
  FROM Posts p
),
union_example AS (
  SELECT CAST(Id AS varchar) AS key, DisplayName AS val FROM Users WHERE Reputation > 10000
  UNION
  SELECT 'post_' || CAST(Id AS varchar) AS key, Title AS val FROM Posts WHERE Score > 100
),
final AS (
  SELECT u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    COALESCE(us.total_posts, 0) AS total_posts,
    COALESCE(us.questions_count, 0) AS questions_count,
    COALESCE(us.answers_count, 0) AS answers_count,
    COALESCE(us.avg_score_questions, 0) AS avg_score_questions,
    COALESCE(us.avg_score_answers, 0) AS avg_score_answers,
    COALESCE(bd.total_badges, 0) AS total_badges,
    COALESCE(bd.gold_badges, 0) AS gold_badges,
    COALESCE(vs.upvotes_received, 0) AS upvotes_received,
    COALESCE(vs.downvotes_received, 0) AS downvotes_received,
    COALESCE(aa.accepted_answers, 0) AS accepted_answers,
    CASE WHEN aa.answers_count_check > 0 THEN ROUND(CAST(aa.accepted_answers AS numeric) / NULLIF(CAST(aa.answers_count_check AS numeric), 0), 4) ELSE 0 END AS acceptance_rate,
    COALESCE(am.median_answer_score, 0) AS median_answer_score,
    COALESCE(ut.distinct_tags, 0) AS distinct_tags_on_questions,
    COALESCE(tc.top_commenters_list, '') AS top_commenters,
    ur.reputation_rank,
    ur.reputation_percentile,
    COALESCE(lp.latest_title, '') AS latest_title,
    COALESCE(ut.tags_by_freq, '') AS tags_by_freq
  FROM Users u
  LEFT JOIN posts_summary us ON us.UserId = u.Id
  LEFT JOIN badges_summary bd ON bd.UserId = u.Id
  LEFT JOIN votes_summary vs ON vs.UserId = u.Id
  LEFT JOIN answer_acceptance aa ON aa.UserId = u.Id
  LEFT JOIN answer_median am ON am.UserId = u.Id
  LEFT JOIN user_tag_stats ut ON ut.UserId = u.Id
  LEFT JOIN top_commenters_agg tc ON tc.UserId = u.Id
  LEFT JOIN user_ranking ur ON ur.Id = u.Id
  LEFT JOIN latest_post_title lp ON lp.UserId = u.Id
)
SELECT f.*,
  (SELECT COUNT(DISTINCT a.OwnerUserId)
   FROM Posts q
   JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
   WHERE q.OwnerUserId = f.user_id AND q.PostTypeId = 1) AS distinct_answerers_on_my_questions,
  (SELECT peq.engagement_index FROM posts_extended peq WHERE peq.OwnerUserId = f.user_id AND peq.PostTypeId = 1 ORDER BY peq.CreationDate DESC LIMIT 1) AS latest_question_engagement,
  (SELECT pea.engagement_index FROM posts_extended pea WHERE pea.OwnerUserId = f.user_id AND pea.PostTypeId = 2 ORDER BY pea.CreationDate DESC LIMIT 1) AS latest_answer_engagement,
  ((COALESCE(f.Reputation, 0) * 0.6) + (COALESCE(f.total_badges, 0) * 50) + (COALESCE(f.upvotes_received, 0) - COALESCE(f.downvotes_received, 0)) * 2 + (COALESCE(f.median_answer_score, 0) * 10)) AS composite_influence,
  (SELECT array_agg(key) FROM (SELECT key FROM union_example WHERE val IS NOT NULL LIMIT 5) x) AS sample_union_keys,
  (COALESCE(f.DisplayName, '[anon]') || ' | rep:' || COALESCE(CAST(f.Reputation AS varchar), '0') ||
   ' | posts:' || COALESCE(CAST(f.total_posts AS varchar), '0') ||
   ' | badges:' || COALESCE(CAST(f.total_badges AS varchar), '0') ||
   CASE WHEN f.acceptance_rate > 0 THEN ' | acc:' || CAST(f.acceptance_rate * 100 AS text) || '%' ELSE '' END) AS profile_summary
FROM final f
ORDER BY composite_influence DESC
LIMIT 200;