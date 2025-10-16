-- {"query": "9065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3684} 

WITH RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '30 days'
),
BadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagLinkStats AS (
    SELECT
        COALESCE(p.Id, pl.PostId)           AS PostId,
        t.TagName,
        COUNT(pl.Id)                        AS LinkCount
    FROM Posts p
    FULL OUTER JOIN PostLinks pl
        ON p.Id = pl.PostId
    LEFT JOIN Tags t
        ON t.ExcerptPostId = COALESCE(p.Id, pl.PostId)
        OR  t.WikiPostId   = COALESCE(p.Id, pl.PostId)
    WHERE (p.CreationDate IS NOT NULL
           AND p.CreationDate > NOW() - INTERVAL '90 days')
       OR (pl.CreationDate IS NOT NULL
           AND pl.CreationDate > NOW() - INTERVAL '90 days')
    GROUP BY COALESCE(p.Id, pl.PostId), t.TagName
),
UserActivity AS (
    SELECT
        u.Id                            AS UserId,
        u.DisplayName,
        COALESCE(bs.GoldBadges,0)       AS GoldBadges,
        COALESCE(bs.SilverBadges,0)     AS SilverBadges,
        COALESCE(bs.BronzeBadges,0)     AS BronzeBadges,
        COUNT(DISTINCT p.Id)            AS TotalPosts,
        SUM(p.Score)                    AS TotalScore,
        CASE
          WHEN u.Reputation > 0
          THEN ROUND((SUM(p.Score)::NUMERIC / u.Reputation) * 100, 2)
          ELSE NULL
        END                              AS ScoreToReputationPct
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
       AND p.CreationDate > NOW() - INTERVAL '1 year'
    LEFT JOIN BadgeStats bs
        ON bs.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation,
             bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
),
TopTagRanks AS (
    SELECT
        p.Id,
        p.Score,
        ROW_NUMBER() OVER (
            PARTITION BY substring(p.Tags FROM '<([^>]+)>')
            ORDER BY p.Score DESC
        ) AS TagRank
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalPosts,
    ua.TotalScore,
    ua.ScoreToReputationPct,
    rq.Id                          AS RecentQuestionId,
    rq.Title,
    rq.Score                       AS RecentScore,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.PostId = rq.Id)       AS RecentCommentCount,
    rc.RecentCommenterCount,
    CASE
      WHEN vc.VoteCount > 0
      THEN ROUND((vc.UpVotes::NUMERIC / vc.VoteCount) * 100, 1)
      ELSE 0
    END                             AS UpVotePct,
    vc.VoteCount,
    UPPER(COALESCE(tls.TagName, '')) AS NormalizedTagName,
    tls.LinkCount,
    ttr.TagRank
FROM UserActivity ua
LEFT JOIN RecentQuestions rq
    ON rq.OwnerUserId = ua.UserId
   AND rq.rn = 1
LEFT JOIN (
    SELECT
        p.Id,
        COUNT(DISTINCT c.UserId) AS RecentCommenterCount
    FROM Posts p
    LEFT JOIN Comments c
        ON c.PostId = p.Id
       AND c.CreationDate > NOW() - INTERVAL '7 days'
    GROUP BY p.Id
) rc
    ON rc.Id = rq.Id
LEFT JOIN (
    SELECT
        p.Id,
        COUNT(*)                                         AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
    FROM Posts p
    LEFT JOIN Votes v
        ON v.PostId = p.Id
       AND v.CreationDate > NOW() - INTERVAL '7 days'
    GROUP BY p.Id
) vc
    ON vc.Id = rq.Id
LEFT JOIN TagLinkStats tls
    ON tls.PostId = rq.Id
LEFT JOIN TopTagRanks ttr
    ON ttr.Id = rq.Id
WHERE ua.TotalPosts >= 10
  AND ua.ScoreToReputationPct IS NOT NULL

UNION

SELECT
    ua2.UserId,
    ua2.DisplayName,
    NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL
FROM UserActivity ua2
WHERE ua2.TotalPosts < 10

EXCEPT

SELECT
    ua3.UserId,
    ua3.DisplayName,
    0,0,0,0,0,0,
    NULL,NULL,NULL,
    NULL,NULL,NULL,
    NULL
FROM UserActivity ua3
WHERE ua3.ScoreToReputationPct < 1

ORDER BY TotalScore DESC NULLS LAST, DisplayName;
