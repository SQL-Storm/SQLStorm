-- {"query": "3160.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2295} 

WITH
    -- Aggregate vote and badge info per user
    UserReputation AS (
        SELECT
            u.Id                                      AS UserId,
            u.Reputation,
            COALESCE(SUM(CASE v.VoteTypeId
                           WHEN 2 THEN 1               -- UpMod
                           WHEN 3 THEN -1              -- DownMod
                           ELSE 0
                       END), 0)                           AS VoteScore,
            COUNT(b.Id) FILTER (WHERE b.Class = 1)   AS GoldBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 2)   AS SilverBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 3)   AS BronzeBadges
        FROM Users u
        LEFT JOIN Votes   v ON v.UserId = u.Id
        LEFT JOIN Badges  b ON b.UserId = u.Id
        GROUP BY u.Id, u.Reputation
    ),

    -- Explode tags for each question owned by a user
    TagUsage AS (
        SELECT
            p.OwnerUserId                AS UserId,
            UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
            COUNT(*)                    AS PostsWithTag
        FROM Posts p
        WHERE p.PostTypeId = 1               -- only questions
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, Tag
    ),

    -- Latest comment per post (correlated sub‑query pattern via window)
    RecentComment AS (
        SELECT
            c.PostId,
            c.Id       AS CommentId,
            c.Text,
            c.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
        FROM Comments c
    ),

    -- Most recent link (Linked/Duplicate) per post
    LatestPostLink AS (
        SELECT
            pl.PostId,
            pl.RelatedPostId,
            lt.Name    AS LinkType,
            pl.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn
        FROM PostLinks pl
        JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    ),

    -- Combine everything, rank posts per user
    Aggregated AS (
        SELECT
            u.Id                                   AS UserId,
            u.DisplayName,
            ur.Reputation,
            ur.VoteScore,
            ur.GoldBadges,
            ur.SilverBadges,
            ur.BronzeBadges,
            COALESCE(tu.Tag, 'no-tag')             AS Tag,
            tu.PostsWithTag,
            p.Id                                   AS PostId,
            p.Title,
            p.Score,
            p.ViewCount,
            CASE
                WHEN p.ClosedDate IS NOT NULL          THEN 'closed'
                WHEN p.CommunityOwnedDate IS NOT NULL  THEN 'community'
                ELSE 'open'
            END                                    AS Status,
            rc.Text                                 AS LatestCommentText,
            pl.LinkType,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS PostRank
        FROM Users u
        LEFT JOIN UserReputation ur ON ur.UserId = u.Id
        LEFT JOIN TagUsage       tu ON tu.UserId = u.Id
        LEFT JOIN Posts          p  ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        LEFT JOIN RecentComment  rc ON rc.PostId = p.Id AND rc.rn = 1
        LEFT JOIN LatestPostLink pl ON pl.PostId = p.Id AND pl.rn = 1
        WHERE (u.Reputation > 1000 OR ur.VoteScore > 50)                -- complex predicate
          AND (p.Score IS NULL OR p.Score >= 0)                         -- NULL handling
          AND (p.Title IS NOT NULL AND TRIM(p.Title) <> '')
    )

SELECT *
FROM Aggregated
WHERE PostRank <= 5                                            -- top‑5 posts per user
UNION ALL
SELECT
    u.Id,
    u.DisplayName,
    ur.Reputation,
    ur.VoteScore,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    COALESCE(tu.Tag, 'no-tag')          AS Tag,
    tu.PostsWithTag,
    NULL                               AS PostId,
    NULL                               AS Title,
    NULL                               AS Score,
    NULL                               AS ViewCount,
    CASE WHEN u.Id IS NULL THEN 'ghost' ELSE 'active' END AS Status,
    NULL                               AS LatestCommentText,
    NULL                               AS LinkType,
    NULL                               AS PostRank
FROM Users u
LEFT JOIN UserReputation ur ON ur.UserId = u.Id
LEFT JOIN TagUsage       tu ON tu.UserId = u.Id
WHERE u.Id NOT IN (SELECT UserId FROM Aggregated)               -- anti‑join via NOT IN
  AND (ur.GoldBadges > 0 OR ur.SilverBadges > 0)               -- another predicate
ORDER BY Reputation DESC NULLS LAST, PostRank ASC NULLS LAST
LIMIT 100;
