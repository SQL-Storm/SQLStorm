-- {"query": "9071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3680} 

WITH recent_questions AS (
    SELECT
        p.Id         AS qid,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        substring(p.Body, 1, 100) AS Snippet
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE pt.Name = 'Question'
      AND p.CreationDate >= now() - interval '30 days'
),
answer_stats AS (
    SELECT
        ParentId AS qid,
        COUNT(*)                                          AS AnswerCount,
        SUM(Score) FILTER (WHERE Score > 0)               AS PosAnswerScore,
        SUM(Score) FILTER (WHERE Score <= 0)              AS NonPosAnswerScore
    FROM Posts
    WHERE PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
    GROUP BY ParentId
),
comment_stats AS (
    SELECT
        PostId,
        COUNT(*) AS CommentCount,
        MAX(Score) AS MaxCommentScore
    FROM Comments
    GROUP BY PostId
),
user_metrics AS (
    SELECT
        u.Id                        AS uid,
        u.Reputation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        COUNT(b.*)                  AS RecentBadges
    FROM Users u
    LEFT JOIN Badges b
        ON b.UserId = u.Id
       AND b.Date >= now() - interval '1 year'
    GROUP BY u.Id, u.Reputation
),
tag_exploded AS (
    SELECT
        p.Id                            AS qid,
        unnest(string_to_array(
            substring(p.Tags, 2, length(p.Tags)-2),
            '><'
        ))                              AS tag
    FROM Posts p
    WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
),
top5_tags AS (
    SELECT tag
    FROM (
        SELECT
            tag,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
        FROM tag_exploded
        GROUP BY tag
    ) t
    WHERE rn <= 5
),
ranked_answers AS (
    SELECT
        a.ParentId AS qid,
        a.Id       AS aid,
        a.Score,
        ROW_NUMBER() OVER (
            PARTITION BY a.ParentId
            ORDER BY a.Score DESC, a.Id
        )          AS rn
    FROM Posts a
    WHERE a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
),
top_answer_per_q AS (
    SELECT
        qid,
        aid,
        Score AS TopAnswerScore
    FROM ranked_answers
    WHERE rn = 1
)
SELECT
    rq.qid,
    rq.Title,
    COALESCE(a.AnswerCount, 0)           AS AnswerCount,
    COALESCE(a.PosAnswerScore, 0)        AS PositiveAnswerScoreSum,
    COALESCE(cs.CommentCount, 0)         AS Comments,
    COALESCE(cs.MaxCommentScore, 0)      AS HighestCommentScore,
    um.Reputation,
    um.RepRank,
    CASE
      WHEN um.Reputation >= 10000 THEN 'EliteUser'
      WHEN um.Reputation >= 1000  THEN 'PowerUser'
      ELSE 'Newbie'
    END                                   AS UserTier,
    um.RecentBadges                       AS BadgesLastYear,
    COALESCE(ta.TopAnswerScore, 0)        AS TopAnswerScore,
    (
      SELECT COUNT(*)
      FROM Votes v
      WHERE v.PostId = rq.qid
        AND v.VoteTypeId = (
            SELECT Id FROM VoteTypes WHERE Name = 'Favorite'
        )
        AND v.CreationDate >= rq.CreationDate
    )                                     AS FavCountSinceQ,
    (array_agg(DISTINCT te.tag ORDER BY te.tag))[1:3] AS Top3Tags,
    now() - rq.CreationDate              AS Age,
    CASE
      WHEN rq.ViewCount = 0 THEN NULL
      ELSE ROUND(a.AnswerCount::numeric / rq.ViewCount, 4)
    END                                   AS AnswersPerView,
    encoded.MetaKey,
    nb.PopularTagCount,
    v2.Id                                AS DownvoteSampleId
FROM recent_questions rq
LEFT JOIN answer_stats a       ON a.qid = rq.qid
LEFT JOIN comment_stats cs     ON cs.PostId = rq.qid
LEFT JOIN user_metrics um      ON um.uid = rq.OwnerUserId
LEFT JOIN top_answer_per_q ta  ON ta.qid = rq.qid
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS PopularTagCount
    FROM tag_exploded te2
    WHERE te2.qid = rq.qid
      AND te2.tag IN (SELECT tag FROM top5_tags)
) AS nb ON true
LEFT JOIN LATERAL (
    SELECT
        CASE
          WHEN rq.Title IS NULL THEN md5(rq.qid::text)
          ELSE md5(rq.Title)
        END AS MetaKey
) AS encoded ON true
LEFT JOIN tag_exploded te       ON te.qid = rq.qid
LEFT JOIN top5_tags tt          ON te.tag = tt.tag
FULL JOIN Votes v2
    ON v2.PostId = rq.qid
   AND v2.VoteTypeId = (
       SELECT Id FROM VoteTypes WHERE Name = 'DownMod'
   )
WHERE rq.Title ~* '(performance|benchmark|test)'
  AND tt.tag IS NOT NULL

UNION ALL

SELECT
    NULL,
    'SUMMARY'                       AS Title,
    COUNT(*) FILTER (WHERE a.AnswerCount > 0),
    SUM(a.PosAnswerScore),
    SUM(cs.CommentCount),
    MAX(cs.MaxCommentScore),
    MAX(um.Reputation),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM recent_questions rq
LEFT JOIN answer_stats a   ON a.qid = rq.qid
LEFT JOIN comment_stats cs ON cs.PostId = rq.qid
LEFT JOIN user_metrics um  ON um.uid = rq.OwnerUserId
;
