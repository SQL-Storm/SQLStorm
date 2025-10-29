-- {"query": "5809.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 751}
WITH
TopActiveTags AS (
  SELECT
    tg.TagName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    COUNT(*) AS TagPosts
  FROM
    Tags tg
    LEFT JOIN Posts p ON CAST(tg.Id AS text) = CAST(p.Tags AS text)
    LEFT JOIN Votes v ON p.Id = v.PostId
  WHERE
    p.PostTypeId = 1
  GROUP BY
    tg.TagName, tg.Id, p.Tags
),
TaggedPostNetwork AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM
    Posts p
  WHERE
    p.PostTypeId = 1
),
RecentTagWikis AS (
  SELECT
    t.TagName,
    MAX(p.LastActivityDate) AS LastActive
  FROM
    Posts p
    JOIN Tags t ON p.Id = t.WikiPostId
  WHERE
    t.IsModeratorOnly = FALSE
  GROUP BY
    t.TagName
),
UserImpact AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    COALESCE(b.Class, 0) AS GoldBadgeClass
  FROM
    Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate, u.Location, u.WebsiteUrl, b.Class
),
ComplexBenchmark AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.Views,
    up.UpVotes,
    up.DownVotes,
    up.CreationDate,
    up.LastAccessDate,
    up.Location,
    up.WebsiteUrl,
    up.GoldBadgeClass,
    pv.PostId,
    pv.Title,
    pv.Tags,
    pv.CreationDate AS PostDate,
    pv.Score,
    pv.ViewCount,
    pv.CommentCount,
    pv.LastActivityDate,
    pv.Favorites,
    nt.LastActive AS TagLastActive,
    pv.OwnerUserId,
    pv.rn
  FROM
    UserImpact up
    LEFT JOIN (
      SELECT
        rp.PostId,
        rp.Title,
        rp.Tags,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.CommentCount,
        rp.LastActivityDate,
        rp.FavoriteCount AS Favorites,
        rp.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate DESC) AS rn
      FROM
        TaggedPostNetwork rp
    ) pv ON pv.OwnerUserId = up.UserId AND pv.rn <= 5
    LEFT JOIN RecentTagWikis nt ON nt.TagName = SUBSTRING(pv.Tags FROM 2 FOR (CHAR_LENGTH(pv.Tags) - 2))
  GROUP BY
    up.UserId, up.DisplayName, up.Reputation, up.Views, up.UpVotes, up.DownVotes, up.CreationDate, up.LastAccessDate, up.Location, up.WebsiteUrl, up.GoldBadgeClass,
    pv.PostId, pv.Title, pv.Tags, pv.CreationDate, pv.Score, pv.ViewCount, pv.CommentCount, pv.LastActivityDate, pv.Favorites, nt.LastActive, pv.OwnerUserId, pv.rn
)
SELECT
  cb.UserId,
  cb.DisplayName,
  cb.Reputation,
  cb.Views,
  cb.UpVotes,
  cb.DownVotes,
  cb.CreationDate,
  cb.LastAccessDate,
  cb.Location,
  cb.WebsiteUrl,
  cb.GoldBadgeClass,
  cb.PostId,
  cb.Title,
  cb.Tags,
  cb.PostDate,
  cb.Score,
  cb.ViewCount,
  cb.CommentCount,
  cb.LastActivityDate,
  cb.Favorites,
  cb.TagLastActive
FROM
  ComplexBenchmark cb
WHERE
  cb.PostDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
ORDER BY
  cb.Reputation DESC,
  cb.PostDate DESC
OFFSET 0 ROW FETCH NEXT 100 ROWS ONLY;