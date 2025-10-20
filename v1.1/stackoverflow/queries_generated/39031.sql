-- {"query": "39031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2611} 

WITH
-- Rank users by badge counts
UserBadgeStats AS (
    SELECT
        u.Id               AS UserId,
        u.DisplayName,
        COUNT(b.Id)        AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b
      ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

-- Top 10 most-used tags in questions
TopTags AS (
    SELECT
        t.Id       AS TagId,
        t.TagName,
        COUNT(p.Id) AS QuestionCount
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1
     AND '<' || t.TagName || '>' = ANY(
            string_to_array(
              substring(p.Tags, 2, length(p.Tags) - 2),
              '><'
            )
         )
    GROUP BY t.Id, t.TagName
    ORDER BY COUNT(p.Id) DESC
    LIMIT 10
)

SELECT
    tt.TagName,
    tt.QuestionCount,
    qb.QuestionId,
    qb.Title                 AS QuestionTitle,
    stats.AnswerCount,
    ROUND(stats.AvgAnswerSec, 2) AS AvgAnswerSeconds,
    stats.MaxAnswerScore,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ph.TypeName             AS LastHistoryType,
    lt.Name                 AS LastLinkType,
    vt.Name                 AS TopVoteType
FROM TopTags tt

-- For each top tag, grab the top 5 highest-scoring questions
JOIN LATERAL (
    SELECT
        p2.Id           AS QuestionId,
        p2.OwnerUserId,
        p2.Title,
        p2.CreationDate
    FROM Posts p2
    WHERE p2.PostTypeId = 1
      AND '<' || tt.TagName || '>' = ANY(
             string_to_array(
               substring(p2.Tags, 2, length(p2.Tags) - 2),
               '><'
             )
         )
    ORDER BY p2.Score DESC
    LIMIT 5
) qb ON TRUE

-- Compute answer statistics for each picked question
JOIN LATERAL (
    SELECT
        COUNT(ans.Id)                                                        AS AnswerCount,
        AVG(EXTRACT(EPOCH FROM (ans.CreationDate - qb.CreationDate)))         AS AvgAnswerSec,
        MAX(COALESCE(vp.Score, 0))                                            AS MaxAnswerScore
    FROM Posts ans
    LEFT JOIN Votes vp
      ON vp.PostId = ans.Id
     AND vp.VoteTypeId = 2  -- upvotes on answers
    WHERE ans.ParentId = qb.QuestionId
) stats ON TRUE

-- Bring in badge stats for the question owner
JOIN UserBadgeStats ub
  ON ub.UserId = qb.OwnerUserId

-- Last post-history action on the question
LEFT JOIN LATERAL (
    SELECT pht.Name AS TypeName
    FROM PostHistory ph
    JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostId = qb.QuestionId
    ORDER BY ph.CreationDate DESC
    LIMIT 1
) ph ON TRUE

-- Last link type added to the question
LEFT JOIN LATERAL (
    SELECT lt.Name
    FROM PostLinks pl
    JOIN LinkTypes lt
      ON pl.LinkTypeId = lt.Id
    WHERE pl.PostId = qb.QuestionId
    ORDER BY pl.CreationDate DESC
    LIMIT 1
) lt ON TRUE

-- Most frequent vote type on the question
LEFT JOIN LATERAL (
    SELECT vt.Name
    FROM Votes v
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE v.PostId = qb.QuestionId
    GROUP BY vt.Name
    ORDER BY COUNT(*) DESC
    LIMIT 1
) vt ON TRUE

ORDER BY tt.QuestionCount DESC,
         stats.AvgAnswerSec DESC,
         ub.BadgeRank
LIMIT 100;
