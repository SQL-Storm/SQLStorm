WITH user_stats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1)          AS gold_badges,
           COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2)          AS silver_badges,
           COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3)          AS bronze_badges,
           SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS total_question_score,
           SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS total_answer_score,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)              AS question_count,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)              AS answer_count,
           COUNT(v.Id)                                            AS vote_count,
           MAX(p.CreationDate)                                    AS last_post_date
    FROM   Users u
    LEFT JOIN Badges b      ON b.UserId = u.Id
    LEFT JOIN Posts p       ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v       ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_activity AS (
    SELECT t.TagName,
           COUNT(p.Id)                                   AS post_cnt,
           AVG(p.Score)                                  AS avg_score,
           SUM(p.ViewCount)                              AS total_views,
           COUNT(DISTINCT ph.UserId)                     AS distinct_editors
    FROM   Tags t
    JOIN   Posts p
           ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN PostHistory ph
           ON ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY t.TagName
),
top_questions AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.ViewCount,
           u.DisplayName                                 AS asker,
           ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM   Posts p
    JOIN   Users u ON u.Id = p.OwnerUserId
    WHERE  p.PostTypeId = 1
      AND  p.ClosedDate IS NULL
),
duplicate_links AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           COUNT(*) AS dup_votes
    FROM   PostLinks pl
    WHERE  pl.LinkTypeId = 3
    GROUP BY pl.PostId, pl.RelatedPostId
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.gold_badges,
       us.silver_badges,
       us.bronze_badges,
       us.question_count,
       us.answer_count,
       us.total_question_score,
       us.total_answer_score,
       us.vote_count,
       us.last_post_date,
       -- aggregate top tags as a JSON array in a standard-compatible way
       CAST('[' ||
       COALESCE(string_agg(
         '{' ||
         '"tag":' || '"' || REPLACE(ta.TagName, '"', '\"') || '",' ||
         '"post_cnt":' || COALESCE(CAST(ta.post_cnt AS VARCHAR), '0') || ',' ||
         '"avg_score":' || COALESCE(CAST(ta.avg_score AS VARCHAR), '0') || ',' ||
         '"total_views":' || COALESCE(CAST(ta.total_views AS VARCHAR), '0') || ',' ||
         '"distinct_editors":' || COALESCE(CAST(ta.distinct_editors AS VARCHAR), '0') ||
         '}'
         , ','
       ), '') || ']'
       AS VARCHAR) AS top_tags,
       CAST('[' ||
       COALESCE(string_agg(
         '{' ||
         '"question_id":' || COALESCE(CAST(tq.Id AS VARCHAR), 'null') || ',' ||
         '"title":' || '"' || REPLACE(tq.Title, '"', '\"') || '",' ||
         '"score":' || COALESCE(CAST(tq.Score AS VARCHAR), '0') || ',' ||
         '"views":' || COALESCE(CAST(tq.ViewCount AS VARCHAR), '0') || ',' ||
         '"asker":' || '"' || REPLACE(tq.asker, '"', '\"') || '"' ||
         '}'
         , ','
       ), '') || ']'
       AS VARCHAR) AS top_questions,
       CAST('[' ||
       COALESCE(string_agg(
         '{' ||
         '"duplicate_of":' || COALESCE(CAST(dl.RelatedPostId AS VARCHAR), 'null') || ',' ||
         '"dup_votes":' || COALESCE(CAST(dl.dup_votes AS VARCHAR), '0') ||
         '}'
         , ','
       ), '') || ']'
       AS VARCHAR) AS top_duplicate_links
FROM   user_stats us
LEFT JOIN LATERAL (
    SELECT ta.TagName, ta.post_cnt, ta.avg_score, ta.total_views, ta.distinct_editors
    FROM   tag_activity ta
    WHERE  ta.TagName = ANY (
               SELECT UNNEST(string_to_array(p.Tags, '><'))
               FROM   Posts p
               WHERE  p.OwnerUserId = us.Id
               LIMIT  10
           )
    ORDER BY ta.post_cnt DESC
    LIMIT 5
) ta ON TRUE
LEFT JOIN LATERAL (
    SELECT tq.Id, tq.Title, tq.Score, tq.ViewCount, tq.asker, tq.rn
    FROM   top_questions tq
    WHERE  tq.asker = us.DisplayName
    ORDER BY tq.rn ASC
    LIMIT 3
) tq ON TRUE
LEFT JOIN LATERAL (
    SELECT dl.PostId, dl.RelatedPostId, dl.dup_votes
    FROM   duplicate_links dl
    WHERE  dl.PostId IN (
               SELECT Id
               FROM   Posts
               WHERE  OwnerUserId = us.Id
           )
    ORDER BY dl.dup_votes DESC
    LIMIT 2
) dl ON TRUE
GROUP BY us.Id, us.DisplayName, us.Reputation,
         us.gold_badges, us.silver_badges, us.bronze_badges,
         us.question_count, us.answer_count,
         us.total_question_score, us.total_answer_score,
         us.vote_count, us.last_post_date
ORDER BY us.Reputation DESC
LIMIT 100;