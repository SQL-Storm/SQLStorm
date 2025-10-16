WITH UserReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
),
-- TagUsage: split tags like <tag1><tag2> into rows in a portable way using recursive CTE
TagUsage AS (
    SELECT tag AS Tag, COUNT(*) AS TagCount
    FROM (
        SELECT p.Id,
               TRIM(BOTH '<>' FROM p.Tags) AS trimmed
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ) base,
    LATERAL (
        WITH RECURSIVE splitter(rest, tag) AS (
            SELECT base.trimmed, NULL
            UNION ALL
            SELECT
                CASE WHEN POSITION('><' IN rest) = 0 THEN '' ELSE SUBSTRING(rest FROM POSITION('><' IN rest)+2) END,
                CASE WHEN POSITION('><' IN rest) = 0 THEN rest ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest)-1) END
            FROM splitter
            WHERE rest <> ''
        )
        SELECT tag FROM splitter WHERE tag IS NOT NULL
    ) s
    GROUP BY tag
),
TopTags AS (
    SELECT Tag
    FROM TagUsage
    ORDER BY TagCount DESC
    LIMIT 10
),
UserActivity AS (
    SELECT
        u.Id,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotesGiven,
        COALESCE(COUNT(c.Id),0) AS CommentsMade
    FROM Users u
    LEFT JOIN Votes v    ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
MainSelection AS (
    SELECT
        ur.Id                                   AS UserId,
        ur.DisplayName,
        ur.Reputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.CommentsMade,
        q.Id                                    AS RecentQuestionId,
        q.Title,
        q.Score,
        q.CreationDate,
        COALESCE(NULLIF(q.Tags,''), '<no tags>') AS Tags,
        CASE
            WHEN (
                SELECT COUNT(1)
                FROM (
                    WITH RECURSIVE splitter(rest, tag) AS (
                        SELECT TRIM(BOTH '<>' FROM q.Tags), NULL
                        UNION ALL
                        SELECT
                            CASE WHEN POSITION('><' IN rest) = 0 THEN '' ELSE SUBSTRING(rest FROM POSITION('><' IN rest)+2) END,
                            CASE WHEN POSITION('><' IN rest) = 0 THEN rest ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest)-1) END
                        FROM splitter
                        WHERE rest <> ''
                    )
                    SELECT tag FROM splitter WHERE tag IS NOT NULL
                ) ttags
            ) > 5 THEN 'Many'
            ELSE 'Few'
        END                                      AS TagDensity,
        EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE pl.PostId = q.Id
              AND pl.LinkTypeId = 3
              AND pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ur.Id)
        )                                        AS HasDuplicateLinkedToOwnPosts,
        ROW_NUMBER() OVER (PARTITION BY ur.Id ORDER BY q.CreationDate DESC) AS QuestionRank
    FROM UserReputation ur
    FULL OUTER JOIN UserActivity ua ON ua.Id = ur.Id
    LEFT JOIN RecentQuestions q ON q.OwnerUserId = ur.Id AND q.rn = 1
    WHERE (ur.Reputation > 10000 OR ua.CommentsMade > 500)
      AND (COALESCE(ur.GoldBadges,0) + COALESCE(ur.SilverBadges,0) + COALESCE(ur.BronzeBadges,0)) > 10
      AND q.Tags IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM TopTags tt
          WHERE tt.Tag = (
              SELECT tag FROM (
                  WITH RECURSIVE splitter(rest, tag, rn) AS (
                      SELECT TRIM(BOTH '<>' FROM q.Tags), NULL, 0
                      UNION ALL
                      SELECT
                          CASE WHEN POSITION('><' IN rest) = 0 THEN '' ELSE SUBSTRING(rest FROM POSITION('><' IN rest)+2) END,
                          CASE WHEN POSITION('><' IN rest) = 0 THEN rest ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest)-1) END,
                          rn+1
                      FROM splitter
                      WHERE rest <> ''
                  )
                  SELECT tag FROM splitter WHERE tag IS NOT NULL LIMIT 1
              ) tags_limit
          )
      )
)
SELECT *
FROM (
    SELECT *
    FROM MainSelection
    ORDER BY Reputation DESC
    LIMIT 100
) t_main

UNION ALL

SELECT
    CAST(NULL AS BIGINT)     AS UserId,
    CAST(NULL AS VARCHAR)    AS DisplayName,
    CAST(NULL AS INTEGER)    AS Reputation,
    CAST(NULL AS INTEGER)    AS GoldBadges,
    CAST(NULL AS INTEGER)    AS SilverBadges,
    CAST(NULL AS INTEGER)    AS BronzeBadges,
    CAST(NULL AS INTEGER)    AS UpVotesGiven,
    CAST(NULL AS INTEGER)    AS DownVotesGiven,
    CAST(NULL AS INTEGER)    AS CommentsMade,
    p.Id                     AS RecentQuestionId,
    p.Title,
    p.Score,
    p.CreationDate,
    p.Tags,
    'NoUser'                 AS TagDensity,
    FALSE                    AS HasDuplicateLinkedToOwnPosts,
    CAST(NULL AS INTEGER)    AS QuestionRank
FROM Posts p
WHERE p.PostTypeId = 1
  AND p.Score < 0
  AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '7' DAY)
  AND p.Tags IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM Users u WHERE u.Id = p.OwnerUserId)
ORDER BY Score DESC
LIMIT 20;