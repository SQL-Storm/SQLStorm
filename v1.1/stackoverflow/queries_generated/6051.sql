-- {"query": "6051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 872} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location AS OwnerLocation,
    u.AccountId AS OwnerAccountId,
    COALESCE(p.Views, 0) AS ViewsOrZero,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate ASC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
  WHERE p.PostTypeId IN (1,2)
    AND p.ClosedDate IS NULL
),
correlated_comments AS (
  SELECT
    r.PostId,
    COUNT(c.Id) AS CommentCount
  FROM ranked_posts r
  LEFT JOIN Comments c ON c.PostId = r.PostId
  GROUP BY r.PostId
),
tag_coverage AS (
  SELECT
    rp.PostId,
    STRING_AGG(t.TagName, ',') AS TagsList
  FROM ranked_posts rp
  LEFT JOIN UNNEST(string_to_array(rp.Tags, '><')) AS t(TagName)
    ON true
  GROUP BY rp.PostId
),
recent_edits AS (
  SELECT
    rp.PostId,
    MAX(ph.CreationDate) AS LastEditDate
  FROM ranked_posts rp
  LEFT JOIN PostHistory ph
    ON ph.PostId = rp.PostId
  WHERE ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,12,14,15,16,24)
  GROUP BY rp.PostId
),
top_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId IN (2) THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId IN (3) THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId IN (1,7,8,9,10,11,12,14,15,16) THEN 1 ELSE 0 END) AS MiscVotes
  FROM Votes v
  GROUP BY v.PostId
)
SELECT
  rp.PostId,
  rp.Title,
  rp.Body,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.Tags,
  rp.OwnerDisplayName,
  rp.OwnerLocation,
  rp.OwnerReputation,
  rp.LastActivityDate,
  cr.CommentCount,
  tt.TagsList,
  re.LastEditDate,
  tv.UpVotes,
  tv.DownVotes,
  (tv.UpVotes - tv.DownVotes) AS NetVotes,
  CASE
    WHEN rp.OwnerReputation > 10000 THEN 'A+'
    WHEN rp.OwnerReputation BETWEEN 1000 AND 10000 THEN 'A'
    WHEN rp.OwnerReputation BETWEEN 100 AND 999 THEN 'B'
    ELSE 'C'
  END AS ReputationBucket,
  CASE
    WHEN rp.PostTypeId = 1 THEN 'Question'
    WHEN rp.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind
FROM ranked_posts rp
LEFT JOIN correlated_comments cr ON cr.PostId = rp.PostId
LEFT JOIN tag_coverage tt ON tt.PostId = rp.PostId
LEFT JOIN recent_edits re ON re.PostId = rp.PostId
LEFT JOIN top_votes tv ON tv.PostId = rp.PostId
LEFT JOIN PostLinks pl ON pl.PostId = rp.PostId
ORDER BY
  NetVotes DESC,
  rp.ViewCount DESC,
  rp.CreationDate ASC
LIMIT 200;