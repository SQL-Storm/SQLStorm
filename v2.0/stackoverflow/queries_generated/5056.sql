-- {"query": "5056.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 667} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC NULLS LAST,
        p.ViewCount DESC NULLS LAST,
        p.LastActivityDate DESC NULLS LAST
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
TopMatches AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    t.Name AS TagName,
    v.VoteTypeId,
    v.UserId AS VoterUserId,
    v.CreationDate AS VoteDate
  FROM RankedPosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1 -- Gold badges
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS t
  ) AS tt ON true
  LEFT JOIN Tags t ON t.TagName = tt.t
  LEFT JOIN Votes v ON v.PostId = rp.Id
  WHERE rp.rn <= 5
)
SELECT
  tr.Id,
  tr.Title,
  CASE
    WHEN tr.PostTypeId = 1 THEN 'Question'
    WHEN tr.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostType,
  tr.CreationDate,
  tr.LastActivityDate,
  tr.Score,
  tr.ViewCount,
  tr.OwnerUserId,
  tr.OwnerDisplayName,
  tr.Reputation,
  tr.OwnerCreationDate,
  tr.Location,
  tr.UpVotes,
  tr.DownVotes,
  tr.Tags,
  tr.AnswerCount,
  tr.CommentCount,
  tr.FavoriteCount,
  tr.ContentLicense,
  COALESCE(tr.BadgeName, 'No Gold Badge') AS GoldBadge,
  tr.BadgeDate,
  tr.TagName,
  COALESCE(tr.VoteDate, NULL) AS LastVoteDate,
  COALESCE(tr.VoteTypeId, NULL) AS LastVoteType
FROM TopMatches tr
ORDER BY tr.CreationDate DESC NULLS LAST, tr.LastActivityDate DESC NULLS LAST
LIMIT 100;