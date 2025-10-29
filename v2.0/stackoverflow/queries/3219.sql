WITH
UserBase AS (
    SELECT
        u.Id                                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    WHERE u.Reputation > 500
),
QStats AS (
    SELECT
        p.OwnerUserId               AS UserId,
        COUNT(*)                    AS QCount,
        AVG(p.Score)                AS AvgQScore,
        MAX(p.CreationDate)         AS LastQDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score IS NOT NULL
    GROUP BY p.OwnerUserId
),
AStats AS (
    SELECT
        p.OwnerUserId               AS UserId,
        COUNT(*)                    AS ACount,
        AVG(p.Score)                AS AvgAScore,
        MAX(p.CreationDate)         AS LastADate
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.Score IS NOT NULL
    GROUP BY p.OwnerUserId
),
VoteSum AS (
    SELECT
        v.UserId,
        SUM(CASE v.VoteTypeId
                WHEN 2 THEN  1
                WHEN 3 THEN -1
                ELSE 0
            END) AS NetVotesGiven
    FROM Votes v
    GROUP BY v.UserId
),
DupLinks AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DupCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
UserTag AS (
    SELECT
        t.TagName,
        t.Count                      AS TagUseCount,
        LENGTH(p.Body)               AS ExcerptLen,
        LENGTH(p2.Body)              AS WikiLen,
        p.OwnerUserId                AS UserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY t.Count DESC) AS rn
    FROM Tags t
    JOIN Posts p  ON p.Id = t.ExcerptPostId
    LEFT JOIN Posts p2 ON p2.Id = t.WikiPostId
    WHERE t.IsModeratorOnly = FALSE
)
SELECT
    ROW_NUMBER() OVER (ORDER BY ub.Reputation DESC, ub.NetVotes DESC) AS RankByRep,
    ub.UserId,
    ub.DisplayName,
    ub.Reputation,
    ub.NetVotes,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    COALESCE(q.QCount,0)                          AS QuestionsPosted,
    COALESCE(a.ACount,0)                          AS AnswersPosted,
    COALESCE(v.NetVotesGiven,0)                   AS NetVotesGiven,
    COALESCE(dl.DupCount,0)                       AS DuplicateLinksOnLatestPost,
    CASE
        WHEN ub.Reputation >= 20000 THEN 'Legendary'
        WHEN ub.Reputation >= 10000 THEN 'Expert'
        WHEN ub.Reputation >= 5000  THEN 'Seasoned'
        ELSE 'Contributor'
    END                                            AS ReputationTier,
    COALESCE(t.TagName,'<no-tag>') || ' (uses=' ||
    COALESCE(CAST(t.TagUseCount AS text),'0') || ',ex=' ||
    COALESCE(CAST(t.ExcerptLen AS text),'0') || ',wk=' ||
    COALESCE(CAST(t.WikiLen AS text),'0') || ')'        AS TopTagInfo,
    (SELECT COUNT(*)
     FROM Posts p2
     WHERE p2.OwnerUserId = ub.UserId
       AND p2.CreationDate >= DATE_TRUNC('year', DATE '2024-10-01')
       AND p2.Score > 0)                         AS PostsThisYear
FROM UserBase ub
LEFT JOIN QStats q   ON q.UserId = ub.UserId
LEFT JOIN AStats a   ON a.UserId = ub.UserId
LEFT JOIN VoteSum v  ON v.UserId = ub.UserId
LEFT JOIN (
    SELECT OwnerUserId, Id FROM (
      SELECT p.OwnerUserId, p.Id,
             ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
      FROM Posts p
      WHERE p.PostTypeId IN (1,2)
    ) t_lp WHERE rn = 1
) lp ON lp.OwnerUserId = ub.UserId
LEFT JOIN DupLinks dl ON dl.PostId = lp.Id
LEFT JOIN (
    SELECT TagName, TagUseCount, ExcerptLen, WikiLen, UserId
    FROM UserTag
    WHERE rn = 1
) t ON t.UserId = ub.UserId
WHERE ub.Reputation IS NOT NULL
UNION ALL
SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM UserBase WHERE Reputation > 5000)
ORDER BY RankByRep
LIMIT 150;