-- {"query": "9048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3057} 

WITH recent_questions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
answer_stats AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        SUM(
          CASE 
            WHEN a.Score >= (
                 SELECT AVG(x.Score) 
                 FROM Posts x 
                 WHERE x.ParentId = a.ParentId
               ) 
            THEN 1 
            ELSE 0 
          END
        ) AS AboveAvgAnswers,
        MAX(a.Score) AS BestAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
badge_counts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
tag_usage AS (
    SELECT 
        t.tag,
        COUNT(*) AS TagCount
    FROM (
        SELECT 
            unnest(
              string_to_array(
                substring(Tags, 2, length(Tags)-2),
                '><'
              )
            ) AS tag
        FROM Posts
        WHERE PostTypeId = 1
    ) AS t
    GROUP BY t.tag
),
top_linked_questions AS (
    SELECT 
        q.Id,
        q.Title,
        COUNT(pl.Id) AS LinkCount
    FROM Posts q
    LEFT JOIN PostLinks pl
      ON pl.PostId = q.Id
     AND pl.LinkTypeId = 1
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title
    HAVING COUNT(pl.Id) > 5
)
SELECT
    rq.Id                  AS QuestionId,
    rq.Title,
    u.DisplayName,
    COALESCE(bs.TotalAnswers, 0)      AS TotalAnswers,
    COALESCE(bs.AboveAvgAnswers, 0)   AS AboveAvgAnswers,
    COALESCE(bs.BestAnswerScore, 0)   AS BestAnswerScore,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    tu.TagCount,
    tlq.LinkCount,
    CASE
      WHEN rq.ViewCount > 1000 THEN 'HighTraffic'
      ELSE 'Normal'
    END                           AS TrafficCategory,
    ROUND(
      (rq.Score::decimal / NULLIF(rq.ViewCount, 0)) * 100,
      2
    )                             AS ScorePerView,
    (
      SELECT COUNT(*) 
      FROM Comments c 
      WHERE c.PostId = rq.Id 
        AND c.Score > 0
    )                             AS PositiveComments,
    (
      SELECT AVG(length(Text)) 
      FROM Comments c 
      WHERE c.PostId = rq.Id
    )                             AS AvgCommentLength
FROM recent_questions rq
JOIN Users u 
  ON u.Id = rq.OwnerUserId
LEFT JOIN answer_stats bs 
  ON bs.QuestionId = rq.Id
LEFT JOIN badge_counts bc 
  ON bc.UserId = u.Id
LEFT JOIN (
    SELECT 
        p.Id,
        COUNT(*) AS TagCount
    FROM Posts p
    CROSS JOIN LATERAL 
      unnest(
        string_to_array(
          substring(p.Tags, 2, length(p.Tags)-2),
          '><'
        )
      ) AS t(tag)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
) tu 
  ON tu.Id = rq.Id
LEFT JOIN top_linked_questions tlq 
  ON tlq.Id = rq.Id
WHERE rq.rn = 1
  AND rq.Score + COALESCE(bs.BestAnswerScore, 0) > (
        SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score)
        FROM Posts
        WHERE PostTypeId = 1
      )
  AND EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = rq.Id
        AND v.VoteTypeId = 2
        AND v.CreationDate >= rq.CreationDate
  )

UNION

SELECT
    q.Id,
    q.Title,
    u.DisplayName,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM top_linked_questions q
JOIN Users u 
  ON u.Id = (
      SELECT OwnerUserId
      FROM Posts
      WHERE Id = q.Id
    )

INTERSECT

SELECT DISTINCT
    p.Id,
    p.Title,
    u.DisplayName,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM tag_usage t
JOIN Posts p 
  ON p.PostTypeId = 1
JOIN Users u 
  ON u.Id = p.OwnerUserId
WHERE t.TagCount > 50

EXCEPT

SELECT
    v.PostId,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM Votes v
WHERE v.VoteTypeId = 3
;
