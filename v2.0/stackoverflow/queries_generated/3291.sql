-- {"query": "3291.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2655} 

/*  Benchmark query – combines CTEs, window functions, outer joins, correlated subqueries,
    set operators, complex predicates, string handling and NULL logic                */

WITH top_users AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM   Users u
    WHERE  u.Reputation > 10000
       AND u.CreationDate < CURRENT_TIMESTAMP - INTERVAL '1 year'
),
user_badge_counts AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
           COUNT(*)                                      AS total
    FROM   Badges b
    GROUP BY b.UserId
),
tag_activity AS (
    SELECT t.Id      AS TagId,
           t.TagName,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
           MAX(p.CreationDate)                        AS last_used
    FROM   Tags t
    LEFT JOIN Posts p
           ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.Id, t.TagName
),
recent_questions AS (
    SELECT p.Id,
           p.Title,
           p.OwnerUserId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.FavoriteCount,
           COALESCE(p.Tags,'')               AS TagString,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                              ORDER BY p.CreationDate DESC) AS rn_user
    FROM   Posts p
    WHERE  p.PostTypeId = 1
       AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
       AND p.Score IS NOT NULL
),
question_vote_agg AS (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)               AS upvotes,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)               AS downvotes,
           COUNT(*) FILTER (WHERE vt.Id IN (4,12))                  AS offensive_or_spam,
           MAX(v.CreationDate)                                      AS last_vote
    FROM   Votes v
    JOIN   VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
duplicate_links AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           pl.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY pl.PostId
                              ORDER BY pl.CreationDate ASC) AS rn
    FROM   PostLinks pl
    JOIN   LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE  lt.Name = 'Duplicate'
),
closed_reason AS (
    SELECT ph.PostId,
           CAST(ph.Comment AS INT) AS CloseReasonId,
           MIN(ph.CreationDate)    AS ClosedOn
    FROM   PostHistory ph
    WHERE  ph.PostHistoryTypeId = 10               -- Post Closed
    GROUP BY ph.PostId, ph.Comment
)

/* -------------------------------------------------------------------------- */
SELECT
    tu.Id                                    AS UserId,
    tu.DisplayName,
    tu.Reputation,
    ub.gold,
    ub.silver,
    ub.bronze,
    ub.total                                 AS badge_total,
    rq.Id                                    AS QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.FavoriteCount,
    COALESCE(cr.CloseReasonId,0)             AS CloseReasonId,
    COALESCE(vqa.upvotes,0) - COALESCE(vqa.downvotes,0) AS NetScore,
    CASE
        WHEN ta.question_cnt > 100 THEN 'HotTag'
        WHEN ta.answer_cnt = 0      THEN 'UnansweredTag'
        ELSE                               'NormalTag'
    END                                      AS TagCategory,
    STRING_AGG(DISTINCT t.TagName, ',')
        FILTER (WHERE t.TagName IS NOT NULL) AS TagsUsed,
    dl.RelatedPostId                         AS DuplicateOf,
    ROW_NUMBER() OVER (PARTITION BY tu.Id
                       ORDER BY rq.CreationDate DESC) AS QuestionRank
FROM   top_users tu
LEFT JOIN user_badge_counts ub
       ON ub.UserId = tu.Id
LEFT JOIN recent_questions rq
       ON rq.OwnerUserId = tu.Id
      AND rq.rn_user = 1
LEFT JOIN question_vote_agg vqa
       ON vqa.PostId = rq.Id
LEFT JOIN closed_reason cr
       ON cr.PostId = rq.Id
/* pick the most frequent tag used in the question for tag_activity join */
LEFT JOIN LATERAL (
    SELECT t2.Id
    FROM   Tags t2
    WHERE  POSITION(CONCAT('<',t2.TagName,'>') IN rq.TagString) > 0
    ORDER BY t2.Count DESC
    LIMIT 1
) AS best_tag ON TRUE
LEFT JOIN tag_activity ta
       ON ta.TagId = best_tag.Id
LEFT JOIN Tags t
       ON POSITION(CONCAT('<',t.TagName,'>') IN rq.TagString) > 0
LEFT JOIN duplicate_links dl
       ON dl.PostId = rq.Id
      AND dl.rn = 1
WHERE  tu.rn <= 50
GROUP BY
    tu.Id, tu.DisplayName, tu.Reputation,
    ub.gold, ub.silver, ub.bronze, ub.total,
    rq.Id, rq.Title, rq.CreationDate, rq.Score,
    rq.ViewCount, rq.FavoriteCount,
    cr.CloseReasonId,
    vqa.upvotes, vqa.downvotes,
    ta.question_cnt, ta.answer_cnt,
    dl.RelatedPostId,
    rq.OwnerUserId
ORDER BY tu.Reputation DESC, QuestionRank ASC;
