-- {"query": "286.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5572} 
WITH recent_posts AS (
  SELECT p.*,
    CASE WHEN p.Tags IS NULL THEN 0
         ELSE array_length(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><'),1)
    END AS tag_count
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '365 days'
),
question_stats AS (
  SELECT p.OwnerUserId AS UserId,
    count(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
    avg(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_q_score,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.PostTypeId = 1) AS median_q_score,
    sum(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS total_q_views,
    sum(case when p.ClosedDate IS NOT NULL then 1 else 0 end) FILTER (WHERE p.PostTypeId = 1) AS closed_q
  FROM Posts p
  GROUP BY p.OwnerUserId
),
answer_stats AS (
  SELECT p.OwnerUserId AS UserId,
    count(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
    sum((SELECT count(*) FROM Posts q WHERE q.AcceptedAnswerId = p.Id)) AS accepted_answers,
    avg(p.Score) FILTER (WHERE p.PostTypeId = 2) AS avg_a_score,
    max(p.Score) FILTER (WHERE p.PostTypeId = 2) AS max_a_score
  FROM Posts p
  GROUP BY p.OwnerUserId
),
votes_received AS (
  SELECT p.OwnerUserId AS UserId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) AS upvotes_received,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) AS downvotes_received,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) AS favorites_received
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.OwnerUserId
),
badge_counts AS (
  SELECT b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) AS gold,
    sum(case when b.Class = 2 then 1 else 0 end) AS silver,
    sum(case when b.Class = 3 then 1 else 0 end) AS bronze,
    sum(case when b.TagBased = 1 then 1 else 0 end) AS tag_badges
  FROM Badges b
  GROUP BY b.UserId
),
comment_stats AS (
  SELECT u.Id AS UserId,
    count(c.Id) AS comments_made,
    count(c2.Id) AS comments_on_my_posts
  FROM Users u
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c2 ON c2.PostId = p.Id
  GROUP BY u.Id
),
tag_popularity AS (
  SELECT tag, count(*) AS tag_question_count, avg(score)::numeric(10,2) AS avg_score
  FROM (
    SELECT unnest(string_to_array(substring(t.Tags,2,length(t.Tags)-2),'><')) AS tag, t.Score
    FROM Posts t
    WHERE t.PostTypeId = 1 AND t.Tags IS NOT NULL
  ) s
  GROUP BY tag
  ORDER BY tag_question_count DESC
  LIMIT 100
),
duplicate_relations AS (
  SELECT l.PostId AS DuplicateOf, l.RelatedPostId AS Original, count(*) AS duplicate_links
  FROM PostLinks l
  WHERE l.LinkTypeId = 3
  GROUP BY l.PostId, l.RelatedPostId
),
recent_contribs AS (
  SELECT OwnerUserId AS UserId, 'post' AS kind, Id AS item_id, CreationDate FROM Posts WHERE CreationDate >= now() - interval '30 days' AND OwnerUserId IS NOT NULL
  UNION ALL
  SELECT UserId, 'comment', Id, CreationDate FROM Comments WHERE CreationDate >= now() - interval '30 days' AND UserId IS NOT NULL
),
high_rep_no_gold AS (
  SELECT Id AS UserId FROM Users WHERE Reputation >= 10000
  EXCEPT
  SELECT UserId FROM Badges WHERE Class = 1
),
user_rankings AS (
  SELECT u.Id AS UserId,
    COALESCE(q.questions,0) AS questions,
    COALESCE(a.answers,0) AS answers,
    COALESCE(v.upvotes_received,0) AS upvotes_received,
    COALESCE(v.downvotes_received,0) AS downvotes_received,
    COALESCE(b.gold,0) AS gold,
    COALESCE(b.silver,0) AS silver,
    COALESCE(b.bronze,0) AS bronze,
    COALESCE(c.comments_made,0) AS comments_made,
    COALESCE(c.comments_on_my_posts,0) AS comments_on_my_posts,
    CASE WHEN COALESCE(a.answers,0) > 0 THEN COALESCE(a.accepted_answers,0)::float/NULLIF(a.answers,0) ELSE 0 END AS accepted_rate,
    (COALESCE(q.avg_q_score,0)*0.6 + COALESCE(a.avg_a_score,0)*0.4) AS weighted_avg_score,
    ROW_NUMBER() OVER (ORDER BY (COALESCE(v.upvotes_received,0) - COALESCE(v.downvotes_received,0)) DESC, COALESCE(a.answers,0) DESC) AS influence_rank
  FROM Users u
  LEFT JOIN question_stats q ON q.UserId = u.Id
  LEFT JOIN answer_stats a ON a.UserId = u.Id
  LEFT JOIN votes_received v ON v.UserId = u.Id
  LEFT JOIN badge_counts b ON b.UserId = u.Id
  LEFT JOIN comment_stats c ON c.UserId = u.Id
)
SELECT
  u.Id,
  concat(coalesce(u.DisplayName,'<unknown>'), ' (', u.Id::text, ')') AS user_label,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  ur.questions,
  ur.answers,
  ur.upvotes_received,
  ur.downvotes_received,
  ur.gold, ur.silver, ur.bronze,
  ur.comments_made,
  ur.comments_on_my_posts,
  round(ur.accepted_rate::numeric,4) AS accepted_rate,
  round(ur.weighted_avg_score::numeric,4) AS weighted_avg_score,
  ur.influence_rank,
  (COALESCE(nullif(log(NULLIF(u.Reputation,0)), 'NaN'::numeric),0) * 2.5
    + COALESCE(nullif(log(NULLIF(ur.upvotes_received,0)), 'NaN'::numeric),0) * 1.8
    + COALESCE(ur.answers,0) * 0.3
    + (ur.gold * 3 + ur.silver * 1.5 + ur.bronze * 0.5)
  )::numeric(12,4) AS influence_score,
  recent.activity_count_30d,
  recent.last_activity,
  (SELECT string_agg(tag, ', ' ORDER BY cnt DESC)
    FROM (
      SELECT tag, count(*) AS cnt
      FROM (
        SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag
        FROM Posts p
        WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.CreationDate >= now() - interval '365 days'
      ) x
      GROUP BY tag
      ORDER BY cnt DESC
      LIMIT 3
    ) t
  ) AS top_recent_tags,
  replace(substring(coalesce(u.AboutMe,''),1,200), chr(10), ' ') AS about_snippet,
  CASE WHEN h.UserId IS NOT NULL THEN true ELSE false END AS high_rep_no_gold,
  (SELECT concat('A#', a.Id::text, ': ', left(coalesce(p.Title,substring(coalesce(a.Body,''),1,60)), 60))
   FROM Posts a
   LEFT JOIN Posts p ON a.ParentId = p.Id
   WHERE a.PostTypeId = 2 AND a.OwnerUserId = u.Id
     AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = a.Id)
   ORDER BY a.LastActivityDate DESC NULLS LAST
   LIMIT 1
  ) AS latest_accepted_answer_summary,
  COALESCE((
    SELECT count(*) FROM PostLinks pl
    WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND pl.LinkTypeId = 3
  ),0) AS times_my_posts_marked_duplicate,
  COALESCE((
    SELECT pl.RelatedPostId FROM PostLinks pl
    WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND pl.LinkTypeId = 3
    GROUP BY pl.RelatedPostId
    ORDER BY count(*) DESC LIMIT 1
  ), NULL) AS most_frequent_original_duplicate,
  (CASE WHEN COALESCE(ur.questions,0) >= 1 AND COALESCE(ur.answers,0) >= 5 AND (ur.accepted_rate > 0.1 OR ur.gold >= 1) THEN 'established'
        WHEN COALESCE(ur.questions,0) = 0 AND COALESCE(ur.answers,0) >= 1 THEN 'answerer'
        ELSE 'casual' END) AS user_tier
FROM Users u
LEFT JOIN user_rankings ur ON ur.UserId = u.Id
LEFT JOIN LATERAL (
  SELECT count(*) AS activity_count_30d, max(CreationDate) AS last_activity
  FROM recent_contribs rc WHERE rc.UserId = u.Id
) recent ON true
LEFT JOIN high_rep_no_gold h ON h.UserId = u.Id
WHERE u.Reputation >= 100
ORDER BY influence_score DESC NULLS LAST, ur.influence_rank
LIMIT 200;