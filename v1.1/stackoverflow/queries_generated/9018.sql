-- {"query": "9018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 2944} 

WITH
-- 1. Find each user’s most recent question in the last 30 days
RecentQ AS (
    SELECT
        p.Id            AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.CreationDate DESC
        ) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '30 days'
),

-- 2. Count badges by class for users who have earned more than 5 badges total
TopBadges AS (
    SELECT
        b.UserId,
        COUNT(*)                               AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Golds,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silvers,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronzes
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(*) > 5
),

-- 3. Aggregate comment‐level statistics per post
CommentsStats AS (
    SELECT
        p.Id                                       AS PostId,
        COUNT(*) FILTER (WHERE c.Score > NULLIF(p.Score,0))          AS HighScoredComments,
        COALESCE(AVG(c.Score), 0)                 AS AvgCommentScore,
        SUM(
            LENGTH(c.Text)
          - LENGTH(REPLACE(c.Text, 'a', ''))
        )                                          AS TotalAsInComments
    FROM Posts p
    LEFT JOIN Comments c
      ON c.PostId = p.Id
    GROUP BY p.Id
),

-- 4. Compute tag‐level statistics across questions
TagStats AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id)                      AS QuestionCount,
        COALESCE(AVG(p.AnswerCount), 0)           AS AvgAnswers,
        COALESCE(MAX(p.Score), 0)                 AS MaxScore
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1
     AND p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
),

-- 5. Assemble per‐user info, bringing in badges, recent question, one of their answer's tags, and comment stats
Filtered AS (
    SELECT
        u.Id                       AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(tb.Golds,   0)    AS GoldBadges,
        COALESCE(tb.Silvers, 0)    AS SilverBadges,
        COALESCE(tb.Bronzes, 0)    AS BronzeBadges,
        rq.Title                   AS MostRecentQuestionTitle,
        rq.CreationDate            AS MostRecentQuestionDate,
        ts.TagName,
        cs.HighScoredComments,
        cs.AvgCommentScore,
        cs.TotalAsInComments
    FROM Users u
    LEFT JOIN TopBadges tb
      ON tb.UserId = u.Id
    LEFT JOIN RecentQ rq
      ON rq.OwnerUserId = u.Id
     AND rq.rn = 1
    LEFT JOIN Posts ans
      ON ans.OwnerUserId = u.Id
     AND ans.PostTypeId = 2
    LEFT JOIN LATERAL (
        -- pick a single tag from the answer’s tag list, if any
        SELECT UNNEST(string_to_array(
                       substring(ans.Tags, 2, length(ans.Tags)-2)
                     , '><'
                   )) AS TagName
    ) ts ON ans.Tags IS NOT NULL
    LEFT JOIN CommentsStats cs
      ON cs.PostId = ans.Id
    WHERE u.Reputation > 1000
),

-- 6. Enrich with tag‐statistics and compute a window for “next tag” by question count
Combined AS (
    SELECT
        f.*,
        ts.QuestionCount,
        ts.AvgAnswers,
        ts.MaxScore,
        LEAD(ts.QuestionCount) OVER (
            ORDER BY ts.QuestionCount DESC
        ) AS NextTagQuestionCount,
        CASE
          WHEN f.GoldBadges > f.SilverBadges THEN 'More gold than silver'
          WHEN f.GoldBadges = f.SilverBadges THEN 'Equal gold/silver'
          ELSE 'More silver than gold'
        END AS BadgeBalance,
        CASE
          WHEN f.MostRecentQuestionDate < NOW() - INTERVAL '7 days' THEN TRUE
          ELSE FALSE
        END AS IsStale,
        NULLIF(f.AvgCommentScore,0) AS NonzeroAvgCommentScore
    FROM Filtered f
    JOIN TagStats ts
      ON ts.TagName = f.TagName
)

-- 7. Final result: pick the top tag‐row per user by highest QuestionCount,
--    filter by above‐average answers, then UNION with a fallback set
SELECT *
FROM (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.UserId
            ORDER BY c.QuestionCount DESC NULLS LAST
        ) AS rn
    FROM Combined c
    WHERE c.AvgAnswers > (
        SELECT AVG(p2.AnswerCount)
        FROM Posts p2
        WHERE p2.PostTypeId = 1
    )
) top_per_user
WHERE rn = 1

UNION

-- Fallback: low‐rep users with no badges
SELECT
    u.Id            AS UserId,
    u.DisplayName,
    u.Reputation,
    0               AS GoldBadges,
    0               AS SilverBadges,
    0               AS BronzeBadges,
    NULL            AS MostRecentQuestionTitle,
    NULL            AS MostRecentQuestionDate,
    NULL            AS TagName,
    NULL            AS HighScoredComments,
    NULL            AS AvgCommentScore,
    NULL            AS TotalAsInComments,
    NULL            AS QuestionCount,
    NULL            AS AvgAnswers,
    NULL            AS MaxScore,
    NULL            AS NextTagQuestionCount,
    'No badges'     AS BadgeBalance,
    NULL            AS IsStale,
    NULL            AS NonzeroAvgCommentScore
FROM Users u
WHERE u.Reputation < 10

ORDER BY UserId, TagName;
