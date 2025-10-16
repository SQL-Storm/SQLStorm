WITH
recent_activity AS (
    SELECT
        u.Id                                         AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id)                         AS PostsLast30Days,
        COUNT(DISTINCT c.Id)                         AS CommentsLast30Days,
        MAX(u.Reputation)                            AS CurrentReputation,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
        AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    LEFT JOIN Comments c
        ON c.UserId = u.Id
        AND c.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_stats AS (
    SELECT
        b.UserId,
        COUNT(*)                          AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        CASE
            WHEN COUNT(CASE WHEN b.Class = 1 THEN 1 END) > 5 THEN 'Elite'
            WHEN COUNT(*) > 10 THEN 'Veteran'
            ELSE 'Contributor'
        END AS BadgeTier
    FROM Badges b
    GROUP BY b.UserId
),
tag_list AS (
    SELECT
        p.Id            AS PostId,
        u.Id            AS OwnerUserId,
        TRIM(tag)       AS Tag
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(
            -- remove leading and trailing angle brackets if present
            CASE
                WHEN p.Tags LIKE '<%>' THEN substring(p.Tags FROM 2 FOR (length(p.Tags) - 2))
                ELSE p.Tags
            END,
            '><'
        ) AS tag
    ) s
    WHERE p.Tags IS NOT NULL
),
top_tags AS (
    SELECT
        tl.Tag,
        COUNT(*)                      AS QuestionCount,
        AVG(p.Score)                  AS AvgScore,
        RANK() OVER (ORDER BY AVG(p.Score) DESC) AS TagRank
    FROM tag_list tl
    JOIN Posts p ON p.Id = tl.PostId AND p.PostTypeId = 1
    GROUP BY tl.Tag
    HAVING COUNT(*) > 50
),
link_summary AS (
    SELECT
        pl.RelatedPostId AS QuestionId,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateCount,
        SUM(CASE WHEN lt.Name = 'Linked'    THEN 1 ELSE 0 END) AS LinkedCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.RelatedPostId
),
user_snapshot AS (
    SELECT
        ra.UserId,
        ra.DisplayName,
        ra.PostsLast30Days,
        ra.CommentsLast30Days,
        ra.CurrentReputation,
        ra.ActivityRank,
        COALESCE(bs.TotalBadges,0)   AS TotalBadges,
        COALESCE(bs.GoldBadges,0)    AS GoldBadges,
        COALESCE(bs.SilverBadges,0)  AS SilverBadges,
        COALESCE(bs.BronzeBadges,0)  AS BronzeBadges,
        bs.BadgeTier
    FROM recent_activity ra
    LEFT JOIN badge_stats bs ON bs.UserId = ra.UserId
)
SELECT
    us.UserId,
    us.DisplayName,
    us.PostsLast30Days,
    us.CommentsLast30Days,
    us.CurrentReputation,
    us.ActivityRank,
    us.TotalBadges,
    us.BadgeTier,
    tt.Tag           AS TopTag,
    tt.QuestionCount,
    tt.AvgScore,
    tt.TagRank,
    ls.DuplicateCount,
    ls.LinkedCount,
    (
        SELECT MAX(a.Score)
        FROM Posts a
        WHERE a.OwnerUserId = us.UserId
          AND a.PostTypeId = 2
          AND EXISTS (
              SELECT 1
              FROM tag_list t2
              WHERE t2.PostId = a.ParentId
                AND t2.Tag = tt.Tag
          )
    ) AS BestAnswerScoreInTag,
    COALESCE(
      NULLIF(us.DisplayName, '') || ' (' || COALESCE(us.BadgeTier, '') || ')',
      'Anonymous'
    ) AS DisplayBadgeLabel
FROM user_snapshot us
JOIN top_tags tt
  ON tt.TagRank <= 10
LEFT JOIN link_summary ls
  ON ls.QuestionId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = us.UserId
          AND p.PostTypeId = 1
        ORDER BY p.Score DESC
        LIMIT 1
     )
WHERE us.PostsLast30Days > (
    SELECT FLOOR(AVG(PostsLast30Days)) FROM recent_activity
)
INTERSECT
SELECT
    us2.UserId,
    us2.DisplayName,
    us2.PostsLast30Days,
    us2.CommentsLast30Days,
    us2.CurrentReputation,
    us2.ActivityRank,
    us2.TotalBadges,
    us2.BadgeTier,
    tt2.Tag,
    tt2.QuestionCount,
    tt2.AvgScore,
    tt2.TagRank,
    ls2.DuplicateCount,
    ls2.LinkedCount,
    NULL AS BestAnswerScoreInTag,
    NULL AS DisplayBadgeLabel
FROM user_snapshot us2
JOIN top_tags tt2 ON tt2.TagRank <= 5
LEFT JOIN link_summary ls2 ON ls2.QuestionId = (
    SELECT p2.Id
    FROM Posts p2
    WHERE p2.OwnerUserId = us2.UserId
      AND p2.PostTypeId = 1
    ORDER BY p2.Score DESC
    LIMIT 1
)
ORDER BY UserId, TagRank;