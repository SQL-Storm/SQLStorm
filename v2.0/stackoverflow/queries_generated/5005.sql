-- {"query": "5005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 646} 
WITH RankedPopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    COALESCE(a.Id, NULL) AS AcceptedAnswerId,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.ViewCount * 0.6 + p.Score * 1.2 + COALESCE(p.FavoriteCount, 0) * 2 DESC,
               p.CreationDate DESC
    ) AS rn_owner
  FROM Posts p
  LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (
      ORDER BY p.LastActivityDate DESC,
               p.ViewCount DESC
    ) AS recent_rank
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagPopularity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
)
SELECT
  rp.PostId,
  rp.Title AS QuestionTitle,
  rp.CreationDate AS QuestionCreationDate,
  rp.OwnerUserId,
  rp.ViewCount,
  rp.Score,
  rp.Tags,
  ra.AcceptedAnswerId,
  ra.rn_owner AS OwnerRank,
  ra.AcceptedAnswerId IS NOT NULL AS HasAcceptedAnswer,
  ra.FavoriteCount,
  ra.LastActivityDate,
  ra.recent_rank AS RecentRank,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Location,
  u.AccountId,
  b.Name AS BadgeName,
  v_vote.Name AS LastVoteTypeName,
  v_type.Name AS VoteTypeName
FROM RankedPopularQuestions rp
LEFT JOIN Posts ra ON ra.PostId = rp.AcceptedAnswerId
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
  SELECT
    PostId,
    MAX(CASE WHEN VoteTypeId = 6 THEN CreationDate END) AS LastCloseVoteDate,
    MAX(CASE WHEN VoteTypeId = 2 THEN CreationDate END) AS LastUpvoteDate,
    MAX(CASE WHEN VoteTypeId = 10 THEN CreationDate END) AS LastDeletionDate
  FROM Votes
  GROUP BY PostId
) v ON v.PostId = rp.PostId
LEFT JOIN VoteTypes v_type ON v_type.Id = 2
LEFT JOIN (VALUES ('UpMod',2), ('DownMod',3), ('Accepted',1)) AS v_vote(Name, Id)
  ON v_vote.Id = 2
ORDER BY rp.rn_owner ASC
LIMIT 100;