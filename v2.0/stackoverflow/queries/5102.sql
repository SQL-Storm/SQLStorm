WITH
RecentQuestions AS (
  SELECT p.Id,
         p.Title,
         p.CreationDate,
         p.OwnerUserId,
         p.ViewCount,
         p.Score,
         p.Tags,
         ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
TopUsers AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         u.CreationDate AS UserCreationDate,
         u.LastAccessDate
  FROM Users u
  WHERE u.Reputation > 10000
),
Q_Votes AS (
  SELECT r.Id AS PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0 END) AS UpVoteRate
  FROM Posts r
  LEFT JOIN Votes v ON v.PostId = r.Id
  WHERE r.PostTypeId = 1
  GROUP BY r.Id
),
TagInfo AS (
  SELECT t.Id,
         t.TagName,
         t.Count,
         t.ExcerptPostId
  FROM Tags t
)
SELECT
  rq.Id AS QuestionId,
  rq.Title,
  rq.CreationDate AS QuestionCreated,
  rq.OwnerUserId,
  rq.ViewCount,
  rq.Score,
  rq.Tags,
  COALESCE(ti.TagName, 'untagged') AS PrimaryTag,
  ti.Count AS TagCount,
  vu.DisplayName AS OwnerDisplayName,
  vu.Reputation AS OwnerReputation,
  qv.UpVotes,
  qv.DownVotes,
  ROUND(COALESCE(qv.UpVotes,0) * 1.0 / NULLIF(COALESCE(qv.UpVotes,0) + COALESCE(qv.DownVotes,0), 0), 4) AS UpVoteRate
FROM RecentQuestions rq
LEFT JOIN TopUsers vu ON rq.OwnerUserId = vu.Id
LEFT JOIN Q_Votes qv ON rq.Id = qv.PostId
LEFT JOIN TagInfo ti ON ti.TagName = (
  CASE
    WHEN rq.Tags IS NOT NULL THEN
      TRIM(SPLIT_PART(rq.Tags, ',', 1))
    ELSE NULL
  END)
WHERE rq.rn <= 200
GROUP BY
  rq.Id,
  rq.Title,
  rq.CreationDate,
  rq.OwnerUserId,
  rq.ViewCount,
  rq.Score,
  rq.Tags,
  ti.TagName,
  ti.Count,
  vu.DisplayName,
  vu.Reputation,
  qv.UpVotes,
  qv.DownVotes,
  rq.rn
ORDER BY rq.CreationDate DESC, rq.Score DESC;