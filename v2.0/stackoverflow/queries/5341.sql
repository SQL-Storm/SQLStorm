-- {"query": "5341.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 761}
WITH
RecentPopularPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
TagMentions AS (
  WITH RECURSIVE tag_split(post_id, tagstr, tag, rest) AS (
    SELECT
      p.Id,
      REPLACE(REPLACE(p.Tags, '>', ','), '<', ',') AS tagstr,
      NULL AS tag,
      REPLACE(REPLACE(p.Tags, '>', ','), '<', ',') AS rest
    FROM Posts p
    UNION ALL
    SELECT
      post_id,
      tagstr,
      TRIM(SUBSTRING(rest FROM 1 FOR (CASE WHEN POSITION(',' IN rest)=0 THEN CHAR_LENGTH(rest) ELSE POSITION(',' IN rest)-1 END))) AS tag,
      CASE WHEN POSITION(',' IN rest)=0 THEN '' ELSE SUBSTRING(rest FROM POSITION(',' IN rest)+1) END AS rest
    FROM tag_split
    WHERE rest <> ''
  )
  SELECT
    tag AS TagName,
    COUNT(*) AS MentionCount
  FROM tag_split
  WHERE tag IS NOT NULL AND tag <> ''
  GROUP BY tag
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.DownVotes ASC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
    AND u.Reputation >= 100
),
ComplexStats AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.ViewCount,
    rp.Score,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.PostTypeId,
    ta.MentionCount,
    ta2.AnswerCount,
    c.ClosedCount,
    lv.Churn,
    rp.rn
  FROM RecentPopularPosts rp
  LEFT JOIN (
    SELECT
      p.ParentId,
      COUNT(*) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
  ) ta2 ON rp.PostId = ta2.ParentId
  LEFT JOIN (
    SELECT
      p.Id,
      COUNT(*) AS ClosedCount
    FROM Posts p
    WHERE p.ClosedDate IS NOT NULL
    GROUP BY p.Id
  ) c ON rp.PostId = c.Id
  LEFT JOIN (
    SELECT
      p.Id,
      CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END AS Churn
    FROM Posts p
  ) lv ON rp.PostId = lv.Id
  LEFT JOIN (
    SELECT
      tm.TagName,
      tm.MentionCount
    FROM TagMentions tm
  ) ta ON TRUE
  WHERE rp.rn <= 5
)
SELECT
  cp.PostId,
  cp.Title,
  cp.ViewCount,
  cp.Score,
  cp.CreationDate,
  cp.OwnerUserId,
  cp.PostTypeId,
  cp.MentionCount,
  cp.AnswerCount,
  cp.ClosedCount,
  cp.Churn
FROM ComplexStats cp
LEFT JOIN TopAuthors ta ON cp.OwnerUserId = ta.UserId
LEFT JOIN (SELECT UserId, COUNT(*) AS TotalVotes FROM Votes GROUP BY UserId) v ON ta.UserId = v.UserId
LEFT JOIN (SELECT Id, Name FROM PostHistoryTypes) pt ON 1 = 1
WHERE cp.rn <= 50
ORDER BY cp.ViewCount DESC, cp.Score DESC, cp.CreationDate DESC
FETCH FIRST 100 ROWS ONLY;