-- {"query": "5938.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1004} 
WITH
RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Body,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    u.Location AS OwnerLocation,
    u.Views AS OwnerViews,
    u.UpVotes AS OwnerUpVotes,
    u.DownVotes AS OwnerDownVotes,
    u.AccountId,
    isnull(b.Name, 'NoBadge') AS TopBadgeName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.ViewCount DESC,
        p.Score DESC,
        p.LastActivityDate DESC
    ) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      b.UserId,
      b.Name
    FROM Badges b
    WHERE b.Class = 1
  ) b ON p.OwnerUserId = b.UserId
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
Aggs AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.Tags,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.LastActivityDate,
    rp.LastEditDate,
    rp.ContentLicense,
    rp.TopBadgeName,
    rp.rn_owner,
    v_up.LastUpModDate,
    COUNT(*) OVER () AS TotalPosts,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER () AS TotalUpvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER () AS TotalDownvotes
  FROM RankedPosts rp
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  LEFT JOIN (
    SELECT p.Id, MAX(v.CreationDate) AS LastUpModDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
    GROUP BY p.Id
  ) v_up ON v_up.Id = rp.PostId
),
Windowed AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (ORDER BY a.LastActivityDate DESC, a.Reputation DESC) AS rn_global,
    PERCENT_RANK() OVER (ORDER BY a.LastActivityDate DESC) AS pr
  FROM Aggs a
)
SELECT
  w.PostId,
  w.Title,
  w.Tags,
  w.OwnerDisplayName,
  w.Reputation,
  w.ViewCount,
  w.Score,
  w.LastActivityDate,
  w.TotalPosts,
  w.TotalUpvotes,
  w.TotalDownvotes,
  w.TopBadgeName,
  w.rn_owner,
  w.rn_global,
  w.pr,
  CASE
    WHEN w.LastEditDate IS NULL THEN NULL
    ELSE DATE_PART('hour', AGE(w.LastActivityDate, w.LastEditDate))
  END AS HoursSinceLastEdit,
  CASE
    WHEN w.OwnerLocation IS NULL THEN 'Unknown' ELSE w.OwnerLocation
  END AS OwnerLocation,
  STRING_AGG(DISTINCT t.name, ',') FILTER (WHERE t.name IS NOT NULL) AS TagNames
FROM Windowed w
LEFT JOIN (
  SELECT DISTINCT UnnestTag AS tag
  FROM (
    SELECT UNNEST(string_to_array(REPLACE(REPLACE(w.Tags, '><', ','), '<', ''), ',')) AS UnnestTag
    FROM Posts p
    JOIN Windowed w ON w.PostId = p.Id
  ) s
) t ON TRUE
LEFT JOIN Tags t ON t.TagName = w.Tags -- approximate tag extraction for benchmarking
GROUP BY
  w.PostId, w.Title, w.Tags, w.OwnerDisplayName, w.Reputation, w.ViewCount, w.Score,
  w.LastActivityDate, w.TotalPosts, w.TotalUpvotes, w.TotalDownvotes, w.TopBadgeName,
  w.rn_owner, w.rn_global, w.pr, w.LastEditDate, w.OwnerLocation
ORDER BY w.LastActivityDate DESC
LIMIT 100;