-- {"query": "5228.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 906}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn_by_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR
),
TagsExpanded AS (
  -- Split tags like '<tag1><tag2>' into rows using a lateral string-splitting subquery compatible with many dialects
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    TRIM(s.tag) AS TagName,
    ROW_NUMBER() OVER (
      PARTITION BY rp.PostId
      ORDER BY TRIM(s.tag)
    ) AS rn_tag
  FROM RankedPosts rp
  CROSS JOIN LATERAL (
    -- produce rows by splitting the normalized tag string on '><'
    SELECT value AS tag FROM (
      SELECT
        -- normalize by removing leading/trailing '<' or '>'
        CASE
          WHEN rp.Tags IS NULL OR rp.Tags = '' THEN NULL
          ELSE regexp_replace(rp.Tags, '^<|>$', '', 'g')
        END AS norm_tags
    ) norm
    CROSS JOIN LATERAL (
      -- split norm_tags on the delimiter. Use regexp_split_to_array then unnest to be explicit (Postgres).
      SELECT unnest(regexp_split_to_array(norm.norm_tags, '><')) AS value
    ) split
  ) s
  WHERE rp.Tags IS NOT NULL AND rp.Tags <> ''
),
ActivityWindow AS (
  SELECT
    te.PostId,
    te.Title,
    te.CreationDate,
    te.Score,
    te.ViewCount,
    te.OwnerUserId,
    te.LastActivityDate,
    te.TagName,
    te.ContentLicense,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesInWindow,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesInWindow,
    COUNT(DISTINCT c.Id) AS CommentCountInWindow
  FROM TagsExpanded te
  LEFT JOIN Votes v ON v.PostId = te.PostId
  LEFT JOIN Comments c ON c.PostId = te.PostId
  WHERE te.rn_tag = 1
    AND te.LastActivityDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY
  GROUP BY
    te.PostId, te.Title, te.CreationDate, te.Score, te.ViewCount,
    te.OwnerUserId, te.LastActivityDate, te.TagName, te.ContentLicense
),
CrossJoined AS (
  SELECT
    aw.PostId,
    aw.Title,
    aw.CreationDate,
    aw.Score,
    aw.ViewCount,
    aw.OwnerUserId,
    aw.LastActivityDate,
    aw.TagName,
    aw.ContentLicense,
    aw.UpVotesInWindow,
    aw.DownVotesInWindow,
    aw.CommentCountInWindow,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    u.Location,
    EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = aw.OwnerUserId AND b.Class = 1) AS HasGoldBadge,
    EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = aw.OwnerUserId AND b.Class = 2) AS HasSilverBadge
  FROM ActivityWindow aw
  LEFT JOIN Users u ON aw.OwnerUserId = u.Id
)
SELECT
  PostId,
  Title,
  CreationDate,
  ViewCount,
  Score,
  LastActivityDate,
  TagName,
  ContentLicense,
  UpVotesInWindow,
  DownVotesInWindow,
  CommentCountInWindow,
  Reputation,
  DisplayName,
  Location,
  HasGoldBadge,
  HasSilverBadge,
  100.0 * (UpVotesInWindow - DownVotesInWindow) / NULLIF((UpVotesInWindow + DownVotesInWindow), 0) AS NetVoteRatio,
  (SELECT AVG(CAST(reputation AS NUMERIC)) FROM Users) AS GlobalAverageUserReputation
FROM CrossJoined
ORDER BY LastActivityDate DESC, Score DESC, ViewCount DESC
LIMIT 100;