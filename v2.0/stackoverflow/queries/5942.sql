-- {"query": "5942.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 957}
WITH
RecentUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn_tag
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
SamplePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.FavoriteCount,
    p.AnswerCount,
    p.CommentCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR)
),
CorrelatedHistory AS (
  SELECT
    ph.Id AS HistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate AS HistoryDate,
    ph.Text,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 16, 1, 25)
),
ActivityWindow AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.LastActivityDate,
    V.VoteTypeId,
    V.CreationDate AS VoteDate,
    V.BountyAmount,
    L.LinkTypeId
  FROM Posts p
  LEFT JOIN Votes V ON V.PostId = p.Id
  LEFT JOIN PostLinks L ON L.PostId = p.Id
  WHERE p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6' MONTH)
),
Joined AS (
  SELECT
    sp.Id AS PostId,
    sp.Title,
    sp.PostTypeId,
    sp.CreationDate,
    sp.LastActivityDate,
    sp.Score,
    sp.ViewCount,
    sp.OwnerUserId,
    sp.Tags,
    sp.FavoriteCount,
    sp.AnswerCount,
    sp.CommentCount,
    cu.DisplayName AS OwnerDisplayName,
    u.Reputation,
    (SELECT pht.Name
     FROM PostHistory ph2
     JOIN PostHistoryTypes pht ON ph2.PostHistoryTypeId = pht.Id
     WHERE ph2.PostId = sp.Id
     ORDER BY ph2.CreationDate DESC
     LIMIT 1) AS LastEditType,
    (SELECT MAX(v2.CreationDate) FROM Votes v2 WHERE v2.PostId = sp.Id) AS LastVoteDate,
    ac.VoteDate AS LastVoteDateAlt,
    ac.VoteDate
  FROM SamplePosts sp
  LEFT JOIN Users cu ON cu.Id = sp.OwnerUserId
  LEFT JOIN Users u ON u.Id = sp.OwnerUserId
  LEFT JOIN CorrelatedHistory ch ON ch.PostId = sp.Id
  LEFT JOIN ActivityWindow ac ON ac.PostId = sp.Id
)
SELECT
  j.PostId,
  j.Title,
  j.PostTypeId,
  j.CreationDate,
  j.LastActivityDate,
  j.Score,
  j.ViewCount,
  j.OwnerUserId,
  j.OwnerDisplayName,
  j.Reputation,
  j.Tags,
  j.FavoriteCount,
  j.AnswerCount,
  j.CommentCount,
  j.LastEditType,
  j.LastVoteDate,
  CASE
    WHEN j.PostTypeId = 1 THEN 'Question'
    WHEN j.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  ROW_NUMBER() OVER (PARTITION BY (CASE
    WHEN j.PostTypeId = 1 THEN 'Q'
    WHEN j.PostTypeId = 2 THEN 'A'
    ELSE 'O'
  END) ORDER BY j.LastActivityDate DESC) AS RankWithinType,
  (SELECT STRING_AGG(t.TagName, ',')
   FROM (
     SELECT TRIM(BOTH '<>' FROM regexp_split_to_table(j.Tags, '><')) AS TagName
   ) AS t
  ) AS TagList
FROM Joined j
GROUP BY
  j.PostId,
  j.Title,
  j.PostTypeId,
  j.CreationDate,
  j.LastActivityDate,
  j.Score,
  j.ViewCount,
  j.OwnerUserId,
  j.OwnerDisplayName,
  j.Reputation,
  j.Tags,
  j.FavoriteCount,
  j.AnswerCount,
  j.CommentCount,
  j.LastEditType,
  j.LastVoteDate,
  j.VoteDate,
  j.LastVoteDateAlt
ORDER BY j.LastActivityDate DESC, j.Score DESC
OFFSET 0 LIMIT 100;