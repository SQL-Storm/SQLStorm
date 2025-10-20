-- {"query": "37045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1472} 
WITH user_activity AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_count,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
    COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)),0) AS posts_score,
    COALESCE(SUM(v_up.c),0) AS upvotes_received,
    COALESCE(SUM(v_down.c),0) AS downvotes_received,
    COUNT(DISTINCT b.Id) AS badges_count,
    MAX(p.LastActivityDate) AS last_post_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS c
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) v_up ON v_up.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS c
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) v_down ON v_down.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
tag_influence AS (
  -- compute per-tag aggregated metrics based on questions and their answers
  SELECT
    t.TagName,
    t.Id AS tag_id,
    COUNT(DISTINCT q.Id) AS question_count,
    COUNT(a.Id) FILTER (WHERE a.Score > 0) AS positive_answer_count,
    AVG(q.ViewCount) FILTER (WHERE q.ViewCount IS NOT NULL) AS avg_question_views,
    AVG(g.highest_answer_score) FILTER (WHERE g.highest_answer_score IS NOT NULL) AS avg_top_answer_score,
    SUM(COALESCE(a.Score,0)) AS total_answer_score,
    MAX(q.CreationDate) AS most_recent_question
  FROM Tags t
  LEFT JOIN Posts q ON q.PostTypeId = 1
    AND q.Tags LIKE ('%<' || t.TagName || '>%') -- simple tag containment (Tags stored like <tag1><tag2>)
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN (
    SELECT ParentId, MAX(Score) AS highest_answer_score
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) g ON g.ParentId = q.Id
  GROUP BY t.Id, t.TagName
),
hot_questions AS (
  -- identify hot questions by recent activity, views, answers, and score (windowed to pick top per tag)
  SELECT
    q.Id AS question_id,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.Tags,
    (COALESCE(q.ViewCount,0) * 0.4 + COALESCE(q.Score,0) * 5 + COALESCE(q.AnswerCount,0) * 10) AS raw_hot_score,
    ROW_NUMBER() OVER (PARTITION BY unnest(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><')) ORDER BY (COALESCE(q.ViewCount,0) * 0.4 + COALESCE(q.Score,0) * 5 + COALESCE(q.AnswerCount,0) * 10) DESC) AS rn_per_tag
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= now() - interval '365 days'
),
duplicated_and_linked AS (
  -- compute graph metrics for posts linking and duplicates
  SELECT
    p.Id AS post_id,
    COUNT(pl.Id) FILTER (WHERE lt.Name = 'Linked') AS outbound_links,
    COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS outbound_duplicates,
    COUNT(pl2.Id) FILTER (WHERE lt2.Name = 'Linked') AS inbound_links,
    COUNT(pl2.Id) FILTER (WHERE lt2.Name = 'Duplicate') AS inbound_duplicates
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = p.Id
  LEFT JOIN LinkTypes lt2 ON pl2.LinkTypeId = lt2.Id
  GROUP BY p.Id
),
rich_activity AS (
  -- combine users with their top tags (by question count) and top questions
  SELECT
    ua.*,
    ti.TagName AS top_tag,
    ti.question_count AS top_tag_questions,
    hq.question_id AS exemplar_question_id,
    hq.Title AS exemplar_title,
    hq.raw_hot_score AS exemplar_hot_score
  FROM user_activity ua
  LEFT JOIN LATERAL (
    SELECT t.TagName, t.question_count
    FROM tag_influence t
    JOIN Posts q ON q.PostTypeId = 1 AND q.Tags LIKE ('%<' || t.TagName || '>%')
    JOIN Posts p ON p.OwnerUserId = ua.user_id AND p.PostTypeId = 1 AND p.Tags LIKE ('%<' || t.TagName || '>%')
    ORDER BY t.question_count DESC NULLS LAST
    LIMIT 1
  ) ti ON true
  LEFT JOIN LATERAL (
    SELECT hq.question_id, hq.Title, hq.raw_hot_score
    FROM hot_questions hq
    JOIN Posts pq ON pq.Id = hq.question_id
    WHERE pq.OwnerUserId = ua.user_id
    ORDER BY hq.raw_hot_score DESC
    LIMIT 1
  ) hq ON true
)
SELECT
  ra.user_id,
  ra.DisplayName,
  ra.Reputation,
  ra.CreationDate,
  ra.questions_count,
  ra.answers_count,
  ra.posts_score,
  ra.upvotes_received,
  ra.downvotes_received,
  ra.badges_count,
  ra.last_post_activity,
  ra.top_tag,
  ra.top_tag_questions,
  ti.avg_top_answer_score,
  ti.avg_question_views,
  ra.exemplar_question_id,
  ra.exemplar_title,
  ra.exemplar_hot_score,
  dup.outbound_links,
  dup.outbound_duplicates,
  dup.inbound_links,
  dup.inbound_duplicates
FROM rich_activity ra
LEFT JOIN tag_influence ti ON ti.TagName = ra.top_tag
LEFT JOIN LATERAL (
  SELECT *
  FROM (
    SELECT * FROM duplicated_and_linked WHERE post_id = ra.exemplar_question_id
  ) d
) dup ON true
ORDER BY ra.posts_score DESC NULLS LAST, ra.reputation DESC
LIMIT 250;