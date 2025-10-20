WITH
q AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.AcceptedAnswerId,
    p.FavoriteCount,
    p.CommentCount,
    (CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL ELSE regexp_split_to_array(trim(both '<>' FROM p.Tags), '><') END) AS tag_arr
  FROM Posts p
  WHERE p.PostTypeId = 1
),
votes_agg AS (
  SELECT
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
    count(*) as votes_cnt,
    min(v.CreationDate) as first_vote,
    max(v.CreationDate) as last_vote
  FROM Votes v
  GROUP BY v.PostId
),
comments_top AS (
  SELECT c.PostId, c.Id as CommentId, c.Text as CommentText, c.Score, c.CreationDate
  FROM (
    SELECT c.*,
           row_number() OVER (PARTITION BY c.PostId ORDER BY coalesce(c.Score,0) DESC, c.CreationDate ASC) rn
    FROM Comments c
  ) c
  WHERE c.rn = 1
),
answers AS (
  SELECT p.*
  FROM Posts p
  WHERE p.PostTypeId = 2
),
answers_ranked AS (
  SELECT a.*,
         row_number() OVER (PARTITION BY a.ParentId ORDER BY coalesce(a.Score,0) DESC, a.CreationDate ASC) as rn,
         count(*) OVER (PARTITION BY a.ParentId) as answers_total
  FROM answers a
),
answers_top AS (
  SELECT ar.ParentId as QuestionId, ar.Id as TopAnswerId, ar.Score as TopAnswerScore, ar.OwnerUserId as TopAnswerOwner
  FROM answers_ranked ar
  WHERE ar.rn = 1
),
answers_agg AS (
  SELECT
    a.ParentId as QuestionId,
    count(*) as answers_count,
    avg(a.Score) as answers_avg_score,
    max(a.Score) as answers_max_score,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY a.Score) as answers_median_score,
    sum(case when a.Id = (SELECT p.AcceptedAnswerId FROM Posts p WHERE p.Id = a.ParentId) then 1 else 0 end) as accepted_present
  FROM answers a
  GROUP BY a.ParentId
),
user_posts AS (
  SELECT OwnerUserId as UserId, count(*) as posts_count, avg(Score) as avg_post_score, max(Score) as max_post_score
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
user_badges AS (
  SELECT b.UserId, count(*) as badges_total, sum(case when b.Class = 1 then 1 else 0 end) as gold, sum(case when b.Class = 2 then 1 else 0 end) as silver, sum(case when b.Class = 3 then 1 else 0 end) as bronze
  FROM Badges b
  GROUP BY b.UserId
),
user_stats AS (
  SELECT u.Id as UserId, u.Reputation, u.CreationDate, u.DisplayName,
         coalesce(up.posts_count,0) as posts_count, up.avg_post_score, up.max_post_score,
         coalesce(ub.badges_total,0) as badges_total, coalesce(ub.gold,0) as gold, coalesce(ub.silver,0) as silver, coalesce(ub.bronze,0) as bronze
  FROM Users u
  LEFT JOIN user_posts up ON u.Id = up.UserId
  LEFT JOIN user_badges ub ON u.Id = ub.UserId
),
tags_exploded AS (
  SELECT p.Id as PostId, unnest(regexp_split_to_array(trim(both '<>' FROM coalesce(p.Tags,'')), '><')) as tag
  FROM Posts p
  WHERE p.Tags IS NOT NULL AND p.Tags <> ''
),
tag_counts AS (
  SELECT tag, count(distinct PostId) as tag_post_count
  FROM tags_exploded
  GROUP BY tag
),
question_tags AS (
  SELECT q.Id as QuestionId, unnest(q.tag_arr) as tag
  FROM q
  WHERE q.tag_arr IS NOT NULL
),
question_tag_pop AS (
  SELECT qt.QuestionId, qt.tag, coalesce(tc.tag_post_count,0) as tag_post_count
  FROM question_tags qt
  LEFT JOIN tag_counts tc ON qt.tag = tc.tag
),
dominant_tag AS (
  SELECT QuestionId, tag as dominant_tag, tag_post_count
  FROM (
    SELECT qtp.*,
           row_number() OVER (PARTITION BY qtp.QuestionId ORDER BY qtp.tag_post_count DESC, qtp.tag ASC) rn
    FROM question_tag_pop qtp
  ) x
  WHERE x.rn = 1
),
last_history AS (
  SELECT ph.PostId, ph.Comment as last_history_comment, ph.PostHistoryTypeId as last_history_type, ph.CreationDate as last_history_date
  FROM (
    SELECT ph.*,
           row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) rn
    FROM PostHistory ph
  ) ph
  WHERE ph.rn = 1
),
history_agg AS (
  SELECT ph.PostId,
         count(*) as history_count,
         sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as post_closed_events,
         sum(case when ph.PostHistoryTypeId = 12 then 1 else 0 end) as post_deleted_events,
         sum(case when ph.PostHistoryTypeId in (10,12,13,14,15) then 1 else 0 end) as moderation_events
  FROM PostHistory ph
  GROUP BY ph.PostId
),
main_join AS (
  SELECT
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    q.FavoriteCount,
    q.CommentCount as QCommentCount,
    coalesce((SELECT count(*) FROM PostLinks pl WHERE pl.PostId = q.Id),0) as outgoing_links,
    coalesce((SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = q.Id),0) as incoming_links,
    coalesce(v.upvotes,0) as upvotes,
    coalesce(v.downvotes,0) as downvotes,
    coalesce(v.favorites,0) as favorite_votes,
    coalesce(v.votes_cnt,0) as votes_cnt,
    coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
    coalesce(a.answers_count,0) as answers_count,
    a.answers_avg_score,
    a.answers_max_score,
    a.answers_median_score,
    at.TopAnswerId,
    at.TopAnswerScore,
    us.Reputation as OwnerReputation,
    us.DisplayName as OwnerDisplayName,
    us.posts_count as OwnerPostCount,
    us.badges_total as OwnerBadgeCount,
    dt.dominant_tag,
    lh.last_history_comment as LastHistoryComment,
    ha.history_count as HistoryCount,
    coalesce(ha.post_closed_events,0) as post_closed_events,
    coalesce(ha.post_deleted_events,0) as post_deleted_events,
    coalesce(ha.moderation_events,0) as moderation_events,
    ct.CommentId as TopCommentId,
    ct.CommentText as TopCommentText,
    -- computed metrics (standard SQL casts)
    (CASE
       WHEN q.ViewCount IS NULL OR q.ViewCount = 0 THEN NULL
       ELSE round(CAST(coalesce(q.Score,0) / NULLIF(q.ViewCount,0) AS numeric), 6)
     END) as score_per_view,
    (CASE
       WHEN q.AnswerCount IS NULL OR q.AnswerCount = 0 THEN NULL
       ELSE round(CAST(coalesce(a.answers_avg_score,0) / NULLIF(q.AnswerCount,0) AS numeric), 6)
     END) as avg_answer_score_per_answer,
    -- correlated heavy: average seconds to first answer (correlated)
    (SELECT avg(EXTRACT(epoch FROM (ap.CreationDate - q.CreationDate))) FROM Posts ap WHERE ap.ParentId = q.Id AND ap.PostTypeId = 2 AND ap.CreationDate IS NOT NULL) as avg_seconds_to_answer,
    -- distinct answerers (correlated)
    (SELECT count(distinct ap.OwnerUserId) FROM Posts ap WHERE ap.ParentId = q.Id AND ap.PostTypeId = 2 AND ap.OwnerUserId IS NOT NULL) as distinct_answerers,
    -- boolean: answered by a high rep user
    (SELECT bool_or(coalesce(u2.Reputation,0) > 10000) FROM Posts ap JOIN Users u2 ON ap.OwnerUserId = u2.Id WHERE ap.ParentId = q.Id AND ap.PostTypeId = 2) as has_highrep_answerer,
    -- excerpt of body (correlated)
    (SELECT substring(p2.Body from 1 for 200) FROM Posts p2 WHERE p2.Id = q.Id) as body_excerpt,
    -- canonical tag string
    (SELECT coalesce(string_agg(tag, ' | ' ORDER BY tag), '') FROM question_tags qt2 WHERE qt2.QuestionId = q.Id) as tags_flat
  FROM q
  LEFT JOIN votes_agg v ON v.PostId = q.Id
  LEFT JOIN answers_agg a ON a.QuestionId = q.Id
  LEFT JOIN answers_top at ON at.QuestionId = q.Id
  LEFT JOIN user_stats us ON us.UserId = q.OwnerUserId
  LEFT JOIN dominant_tag dt ON dt.QuestionId = q.Id
  LEFT JOIN last_history lh ON lh.PostId = q.Id
  LEFT JOIN history_agg ha ON ha.PostId = q.Id
  LEFT JOIN comments_top ct ON ct.PostId = q.Id
),
combined AS (
  SELECT mj.QuestionId,
         mj.Title,
         mj.OwnerUserId,
         mj.CreationDate,
         mj.QuestionScore,
         mj.ViewCount,
         mj.AnswerCount,
         mj.AcceptedAnswerId,
         mj.FavoriteCount,
         mj.QCommentCount,
         mj.outgoing_links,
         mj.incoming_links,
         mj.upvotes,
         mj.downvotes,
         mj.favorite_votes,
         mj.votes_cnt,
         mj.net_votes,
         mj.answers_count,
         mj.answers_avg_score,
         mj.answers_max_score,
         mj.answers_median_score,
         mj.TopAnswerId,
         mj.TopAnswerScore,
         mj.OwnerReputation,
         mj.OwnerDisplayName,
         mj.OwnerPostCount,
         mj.OwnerBadgeCount,
         mj.dominant_tag,
         mj.LastHistoryComment,
         mj.HistoryCount,
         mj.post_closed_events,
         mj.post_deleted_events,
         mj.moderation_events,
         mj.TopCommentId,
         mj.TopCommentText,
         mj.score_per_view,
         mj.avg_answer_score_per_answer,
         mj.avg_seconds_to_answer,
         mj.distinct_answerers,
         mj.has_highrep_answerer,
         mj.body_excerpt,
         mj.tags_flat,
         'high_engagement' as cohort,
         rank() OVER (ORDER BY ((COALESCE(mj.ViewCount,0) * GREATEST(COALESCE(mj.answers_count,0),1)) + COALESCE(mj.votes_cnt,0)*10 + COALESCE(mj.upvotes,0)*5 + COALESCE(mj.OwnerReputation,0)/100) DESC) as engagement_rank
  FROM main_join mj
  WHERE (COALESCE(mj.ViewCount,0) > 10000 AND COALESCE(mj.net_votes,0) >= 10)
     OR (COALESCE(mj.answers_count,0) >= 5 AND COALESCE(mj.votes_cnt,0) >= 20)
     OR (COALESCE(mj.OwnerReputation,0) >= 20000 AND COALESCE(mj.votes_cnt,0) >= 5)
  UNION ALL
  SELECT mj.QuestionId,
         mj.Title,
         mj.OwnerUserId,
         mj.CreationDate,
         mj.QuestionScore,
         mj.ViewCount,
         mj.AnswerCount,
         mj.AcceptedAnswerId,
         mj.FavoriteCount,
         mj.QCommentCount,
         mj.outgoing_links,
         mj.incoming_links,
         mj.upvotes,
         mj.downvotes,
         mj.favorite_votes,
         mj.votes_cnt,
         mj.net_votes,
         mj.answers_count,
         mj.answers_avg_score,
         mj.answers_max_score,
         mj.answers_median_score,
         mj.TopAnswerId,
         mj.TopAnswerScore,
         mj.OwnerReputation,
         mj.OwnerDisplayName,
         mj.OwnerPostCount,
         mj.OwnerBadgeCount,
         mj.dominant_tag,
         mj.LastHistoryComment,
         mj.HistoryCount,
         mj.post_closed_events,
         mj.post_deleted_events,
         mj.moderation_events,
         mj.TopCommentId,
         mj.TopCommentText,
         mj.score_per_view,
         mj.avg_answer_score_per_answer,
         mj.avg_seconds_to_answer,
         mj.distinct_answerers,
         mj.has_highrep_answerer,
         mj.body_excerpt,
         mj.tags_flat,
         'community_gem' as cohort,
         rank() OVER (ORDER BY ((GREATEST(100000 - COALESCE(mj.ViewCount,0),0) + COALESCE(mj.OwnerBadgeCount,0)*100 - COALESCE(mj.downvotes,0)*5)) DESC) as engagement_rank
  FROM main_join mj
  WHERE (COALESCE(mj.ViewCount,0) < 500 AND COALESCE(mj.OwnerReputation,0) > 5000)
     OR (COALESCE(mj.OwnerBadgeCount,0) >= 10 AND COALESCE(mj.net_votes,0) > 0)
  EXCEPT
  SELECT mj2.QuestionId,
         mj2.Title,
         mj2.OwnerUserId,
         mj2.CreationDate,
         mj2.QuestionScore,
         mj2.ViewCount,
         mj2.AnswerCount,
         mj2.AcceptedAnswerId,
         mj2.FavoriteCount,
         mj2.QCommentCount,
         mj2.outgoing_links,
         mj2.incoming_links,
         mj2.upvotes,
         mj2.downvotes,
         mj2.favorite_votes,
         mj2.votes_cnt,
         mj2.net_votes,
         mj2.answers_count,
         mj2.answers_avg_score,
         mj2.answers_max_score,
         mj2.answers_median_score,
         mj2.TopAnswerId,
         mj2.TopAnswerScore,
         mj2.OwnerReputation,
         mj2.OwnerDisplayName,
         mj2.OwnerPostCount,
         mj2.OwnerBadgeCount,
         mj2.dominant_tag,
         mj2.LastHistoryComment,
         mj2.HistoryCount,
         mj2.post_closed_events,
         mj2.post_deleted_events,
         mj2.moderation_events,
         mj2.TopCommentId,
         mj2.TopCommentText,
         mj2.score_per_view,
         mj2.avg_answer_score_per_answer,
         mj2.avg_seconds_to_answer,
         mj2.distinct_answerers,
         mj2.has_highrep_answerer,
         mj2.body_excerpt,
         mj2.tags_flat,
         'excluded_closed' as cohort,
         0 as engagement_rank
  FROM main_join mj2
  WHERE COALESCE(mj2.post_closed_events,0) > 0
)
SELECT *
FROM combined
WHERE QuestionScore IS NOT NULL
  AND (COALESCE(avg_seconds_to_answer, 9999999) < 60*60*24*30 OR COALESCE(answers_count,0) >= 3)
ORDER BY cohort, engagement_rank, net_votes DESC, QuestionId
LIMIT 200;