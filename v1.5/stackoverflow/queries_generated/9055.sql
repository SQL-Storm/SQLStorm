-- {"query": "9055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3106} 

WITH
-- for each post, when its latest comment was made
recent_comments AS (
    SELECT
        p.Id         AS PostId,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    GROUP BY p.Id
),
-- aggregated badge counts and average badge class per user
badge_stats AS (
    SELECT
        b.UserId,
        COUNT(*)    AS BadgeCnt,
        AVG(b.Class) AS AvgBadgeClass
    FROM Badges b
    GROUP BY b.UserId
),
-- explode question‐tags into one row per (QuestionId, Tag)
tag_list AS (
    SELECT
        p.Id AS PostId,
        unnest(
          string_to_array(
            substring(p.Tags, 2, length(p.Tags) - 2)
          , '><')
        ) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags       IS NOT NULL
),
-- count how many questions each tag has
tag_popularity AS (
    SELECT
        Tag,
        COUNT(DISTINCT PostId) AS QuestionCount
    FROM tag_list
    GROUP BY Tag
),
-- rank tags by popularity
ranked_tags AS (
    SELECT
        Tag,
        QuestionCount,
        RANK() OVER (ORDER BY QuestionCount DESC) AS TagRank
    FROM tag_popularity
),
-- find top‐reputation owner for each of the top tags
-- using a lateral subquery for correlated ordering
top_user_per_tag AS (
    SELECT
        rt.Tag,
        u.Id          AS UserId,
        u.DisplayName AS TopUserName
    FROM ranked_tags rt
    LEFT JOIN LATERAL (
        SELECT
            u2.Id,
            u2.DisplayName
        FROM Users u2
        JOIN Posts p2
          ON u2.Id = p2.OwnerUserId
        JOIN tag_list tl2
          ON p2.Id = tl2.PostId
         AND tl2.Tag = rt.Tag
        ORDER BY u2.Reputation DESC
        LIMIT 1
    ) u ON TRUE
    WHERE rt.TagRank <= 5
),
-- best (highest‐scoring) answer per question
best_answers AS (
    SELECT
        a.ParentId    AS QuestionId,
        a.Id          AS AnswerId,
        a.Score,
        ROW_NUMBER() OVER (
            PARTITION BY a.ParentId
            ORDER BY a.Score DESC, a.CreationDate
        ) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
-- insights on that top answer: comment/vote breakdown
answer_insights AS (
    SELECT
        ba.QuestionId,
        ba.AnswerId,
        ba.Score            AS TopAnswerScore,
        (SELECT COUNT(*) FROM Comments c
         WHERE c.PostId = ba.AnswerId
           AND c.Score  > 0) AS PositiveComments,
        (SELECT COUNT(*) FROM Votes v
         WHERE v.PostId    = ba.AnswerId
           AND v.VoteTypeId = 2) AS UpvoteCount
    FROM best_answers ba
    WHERE ba.AnswerRank = 1
),
-- assemble the core info for the top 5 tags
main AS (
    SELECT
        rt.Tag,
        rt.QuestionCount,
        COALESCE(bs.BadgeCnt, 0)       AS BadgeCnt,
        COALESCE(bs.AvgBadgeClass, 0)  AS AvgBadgeClass,
        rc.LastCommentDate,
        ai.AnswerId,
        ai.TopAnswerScore,
        ai.PositiveComments,
        ai.UpvoteCount
    FROM ranked_tags rt
    LEFT JOIN top_user_per_tag tpu
      ON rt.Tag = tpu.Tag
    LEFT JOIN badge_stats bs
      ON tpu.UserId = bs.UserId
    LEFT JOIN LATERAL (
        SELECT LastCommentDate
        FROM recent_comments rc2
        JOIN Posts p3
          ON rc2.PostId = p3.Id
        WHERE p3.OwnerUserId = tpu.UserId
        ORDER BY LastCommentDate DESC
        LIMIT 1
    ) rc ON TRUE
    LEFT JOIN LATERAL (
        SELECT *
        FROM answer_insights ai2
        JOIN tag_list tl3
          ON ai2.QuestionId = tl3.PostId
         AND tl3.Tag = rt.Tag
    ) ai ON TRUE
    WHERE rt.TagRank <= 5
),
-- roll up the “other” tags beyond rank 5
others AS (
    SELECT
        'Others'    AS Tag,
        SUM(QuestionCount) AS QuestionCount
    FROM ranked_tags
    WHERE TagRank > 5
)
-- final union of top‐5‐tags detail + “Others”
SELECT * FROM main
UNION ALL
SELECT
    Tag,
    QuestionCount,
    NULL       AS BadgeCnt,
    NULL       AS AvgBadgeClass,
    NULL::timestamp AS LastCommentDate,
    NULL       AS AnswerId,
    NULL       AS TopAnswerScore,
    NULL       AS PositiveComments,
    NULL       AS UpvoteCount
FROM others
ORDER BY
  CASE WHEN Tag = 'Others' THEN 2 ELSE 1 END,
  QuestionCount DESC
LIMIT 10;
