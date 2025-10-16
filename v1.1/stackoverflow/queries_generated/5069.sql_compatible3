WITH
top_users AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
    WHERE u.CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
latest_edits AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (
        SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Edit%'
    )
    GROUP BY ph.PostId
),
badges_per_user AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS AllBadges
    FROM Badges b
    GROUP BY b.UserId
),
user_activity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS Posts,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT v.Id) AS Votes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
tagged_posts AS (
    SELECT
        pp.OwnerUserId,
        s.tag AS TagName,
        COUNT(*) AS TagCount
    FROM (
        SELECT
            p.OwnerUserId,
            CASE
                WHEN p.Tags LIKE '<%>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2)
                ELSE p.Tags
            END AS tags_str
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) pp
    JOIN LATERAL (
        WITH RECURSIVE splitter(remain, tag) AS (
            SELECT
                pp.tags_str AS remain,
                CAST(NULL AS text) AS tag
            UNION ALL
            SELECT
                CASE
                    WHEN POSITION('><' IN remain) > 0 THEN SUBSTRING(remain FROM POSITION('><' IN remain) + 2)
                    ELSE ''
                END,
                CASE
                    WHEN POSITION('><' IN remain) > 0 THEN SUBSTRING(remain FROM 1 FOR POSITION('><' IN remain) - 1)
                    ELSE remain
                END
            FROM splitter
            WHERE remain <> ''
        )
        SELECT tag FROM splitter WHERE tag IS NOT NULL
    ) s ON TRUE
    GROUP BY pp.OwnerUserId, s.tag
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostsCount,
    tu.TotalViews,
    bpu.GoldBadges,
    bpu.SilverBadges,
    bpu.BronzeBadges,
    ua.Posts AS TotalPosts,
    ua.Comments AS TotalComments,
    ua.Votes AS TotalVotes,
    COALESCE((
        SELECT tp.TagName
        FROM tagged_posts tp
        WHERE tp.OwnerUserId = tu.UserId
        ORDER BY tp.TagCount DESC, tp.TagName
        LIMIT 1
    ), 'N/A') AS MostUsedTag,
    (
        SELECT COUNT(*)
        FROM Posts p 
        WHERE p.OwnerUserId = tu.UserId
          AND p.PostTypeId = 1
          AND p.ClosedDate IS NOT NULL
          AND p.Score < 0
    ) AS NegScoreClosedQuestions,
    (
        SELECT AVG(CAST(p.ViewCount AS numeric))
        FROM Posts p
        WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 2
    ) AS AvgViewsOnAnswers,
    (
        SELECT MAX(ph.CreationDate)
        FROM PostHistory ph
        JOIN Posts p ON p.Id = ph.PostId
        WHERE p.OwnerUserId = tu.UserId
          AND ph.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE '%Edit%')
    ) AS LastPostEdit,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        JOIN Posts p ON p.Id = pl.PostId
        WHERE p.OwnerUserId = tu.UserId
          AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE LOWER(Name) = 'duplicate')
    ) AS DuplicateLinksMade,
    (
        SELECT COUNT(*)
        FROM Posts a
        JOIN Posts q ON q.AcceptedAnswerId = a.Id
        WHERE a.OwnerUserId = tu.UserId
    ) AS AcceptedAnswersAuthored
FROM
    top_users tu
LEFT JOIN badges_per_user bpu ON bpu.UserId = tu.UserId
LEFT JOIN user_activity ua ON ua.UserId = tu.UserId
WHERE tu.rn <= 100
GROUP BY
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostsCount,
    tu.TotalViews,
    bpu.GoldBadges,
    bpu.SilverBadges,
    bpu.BronzeBadges,
    ua.Posts,
    ua.Comments,
    ua.Votes,
    tu.rn
ORDER BY tu.Reputation DESC, tu.TotalViews DESC;