-- {"query": "9025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 4681} 

WITH TopUsers AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
      FROM Users u
     WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users)
),
RecentPosts AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.PostTypeId,
           p.Score,
           p.Title,
           p.Tags,
           TO_CHAR(p.CreationDate, 'YYYY-MM-DD') AS PostDay,
           p.ParentId
      FROM Posts p
     WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30' DAY
),
UserBadgeCounts AS (
    SELECT b.UserId,
           COUNT(*) FILTER(WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER(WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER(WHERE b.Class = 3) AS BronzeBadges
      FROM Badges b
     GROUP BY b.UserId
),
QuestionAnswers AS (
    SELECT q.Id AS QuestionId,
           COUNT(a.Id) AS AnswerCount
      FROM Posts q
      LEFT JOIN Posts a
        ON a.ParentId = q.Id
       AND a.PostTypeId = 2
     WHERE q.PostTypeId = 1
     GROUP BY q.Id
),
AvgScores AS (
    SELECT p2.PostTypeId,
           AVG(p2.Score) AS AvgScore
      FROM Posts p2
     GROUP BY p2.PostTypeId
)
SELECT
    tu.DisplayName,
    tu.Reputation,
    COALESCE(ub.GoldBadges,  0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    rp.PostTypeId,
    CASE
      WHEN rp.PostTypeId = 1 THEN 'Q: ' || SUBSTRING(rp.Title FROM 1 FOR 30)
      WHEN rp.PostTypeId = 2 THEN 'A to Q#' || rp.ParentId
      ELSE 'Other'
    END AS Snippet,
    rp.Score,
    qa.AnswerCount,
    rp.PostDay,
    rp.Tags,
    (SELECT MIN(c.CreationDate)
       FROM Comments c
      WHERE c.PostId = rp.Id) AS FirstCommentDate
  FROM TopUsers tu
  FULL OUTER JOIN RecentPosts rp
    ON rp.OwnerUserId = tu.Id
  INNER JOIN UserBadgeCounts ub
    ON ub.UserId = tu.Id
  LEFT JOIN QuestionAnswers qa
    ON qa.QuestionId = rp.Id
  LEFT JOIN AvgScores av
    ON av.PostTypeId = rp.PostTypeId
 WHERE rp.Score > COALESCE(av.AvgScore, 0)
    OR tu.rn <= 10

UNION ALL

SELECT
    'zz_Synthetic'::varchar,
    0,
    0, 0, 0,
    NULL,
    NULL,
    0,
    0,
    '1970-01-01',
    '',
    NULL

INTERSECT

SELECT
    rp2.OwnerDisplayName,
    rp2.Score,
    0, 0, 0,
    NULL,
    NULL,
    rp2.Score,
    0,
    TO_CHAR(rp2.CreationDate, 'YYYY-MM-DD'),
    COALESCE(rp2.Tags, ''),
    NULL
  FROM Posts rp2
 WHERE rp2.Score > 100

EXCEPT

SELECT
    u.DisplayName,
    u.Reputation,
    0, 0, 0,
    NULL,
    NULL,
    0,
    0,
    '1970-01-01',
    '',
    NULL
  FROM Users u
 WHERE u.Reputation < 0

ORDER BY Reputation DESC,
         PostDay NULLS LAST,
         AnswerCount DESC;
