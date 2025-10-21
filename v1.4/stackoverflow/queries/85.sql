WITH TopQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.ViewCount,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = p.Id
        AND v.VoteTypeId = 6
        AND v.CreationDate > p.LastActivityDate
    ) AS HadLateActivity
  FROM Posts p
  WHERE p.PostTypeId = 1
),
ComplexStats AS (
  SELECT
    t.Id,
    t.Title,
    t.OwnerName,
    t.OwnerUserId,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = t.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = t.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = t.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT ARRAY_AGG(v.UserId) FROM Votes v WHERE v.PostId = t.Id AND v.VoteTypeId = 2) AS UpVoterIds
  FROM TopQuestions t
  WHERE t.rn <= 5
),
Joined AS (
  SELECT
    cs.Id,
    cs.Title,
    cs.OwnerName,
    cs.OwnerUserId,
    cs.CreationDate,
    cs.Score,
    cs.ViewCount,
    cs.CommentCount,
    cs.UpVotes,
    cs.DownVotes,
    cs.UpVoterIds,
    lt.Name AS LinkTypeName,
    pl.RelatedPostId,
    p2.Title AS RelatedPostTitle,
    p2.CreationDate AS RelatedPostDate
  FROM ComplexStats cs
  LEFT JOIN PostLinks pl ON pl.PostId = cs.Id
  LEFT JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
Windowed AS (
  SELECT
    J.*,
    ROW_NUMBER() OVER (PARTITION BY J.OwnerUserId ORDER BY J.ViewCount DESC, J.Score DESC) AS OwnerRank
  FROM Joined J
)
SELECT
  OwnerName,
  OwnerUserId,
  Id AS PostId,
  Title AS PostTitle,
  CreationDate AS PostCreationDate,
  Score,
  ViewCount,
  CommentCount,
  UpVotes,
  DownVotes,
  RelatedPostId,
  RelatedPostTitle,
  RelatedPostDate,
  LinkTypeName,
  OwnerRank
FROM Windowed
WHERE OwnerRank <= 3
ORDER BY OwnerUserId, OwnerRank, PostCreationDate DESC;