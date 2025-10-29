WITH
RecentHot AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.LastActivityDate,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY CAST(p.CreationDate AS DATE)
                           ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn_day
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly
    FROM Tags t
    WHERE COALESCE(CASE WHEN t.IsModeratorOnly IS NULL THEN 0 WHEN t.IsModeratorOnly = TRUE THEN 1 ELSE 0 END, 0) = 0
),
UserPerf AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        (
          COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)
        ) * 2
        + COALESCE((
            SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id
              AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY)
        ), 0) AS ActivityScore
    FROM Users u
),
CrossLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name IN ('Linked','Duplicate')
),
Flagged AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount
    FROM Votes v
    WHERE v.VoteTypeId IN (14,16)
),
Agg AS (
    SELECT
        r.PostId,
        r.Title,
        r.CreationDate,
        r.LastActivityDate,
        r.Score,
        r.ViewCount,
        r.OwnerUserId,
        r.Tags,
        r.CommentCount,
        r.FavoriteCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId) AS LinkCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId) AS CommentNum
    FROM RecentHot r
    WHERE r.rn_day = 1
)
SELECT
    a.PostId,
    a.Title,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.Tags,
    a.CommentNum,
    a.FavoriteCount,
    ul.DisplayName AS OwnerDisplayName,
    u.Reputation,
    (
      SELECT STRING_AGG(ct.Name, ',') FROM (
        SELECT DISTINCT v2.VoteTypeId FROM Votes v2 WHERE v2.PostId = a.PostId
      ) vb
      JOIN VoteTypes ct ON vb.VoteTypeId = ct.Id
    ) AS VoteTypesOnPost,
    COALESCE(a.LinkCount,0) AS LinkCount,
    COALESCE(cn.CommentNum,0) AS CommentCount
FROM Agg a
LEFT JOIN Users ul ON a.OwnerUserId = ul.Id
LEFT JOIN Users u ON ul.Id = u.Id
LEFT JOIN (
    SELECT DISTINCT p.Id, p.OwnerUserId
    FROM Posts p
) x ON a.PostId = x.Id
LEFT JOIN CrossLinks cl ON cl.PostId = a.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentNum
    FROM Comments
    GROUP BY PostId
) cn ON a.PostId = cn.PostId
GROUP BY
    a.PostId,
    a.Title,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.Tags,
    a.CommentNum,
    a.FavoriteCount,
    ul.DisplayName,
    u.Reputation,
    a.LinkCount,
    cn.CommentNum
ORDER BY a.LastActivityDate DESC
LIMIT 100;