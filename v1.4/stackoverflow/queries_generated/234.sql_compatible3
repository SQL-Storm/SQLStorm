WITH
Questions AS (
  SELECT
    p.Id AS PostId,
    1 AS Type,
    p.Title AS Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COALESCE(u.DisplayName, 'Unknown') AS OwnerName,
    COALESCE(u.Reputation, 0) AS OwnerRep,
    (SELECT COUNT(*) FROM Posts ap WHERE ap.ParentId = p.Id AND ap.PostTypeId = 2) AS Extra1, -- AnswerCount
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS Extra2, -- CommentCount
    COALESCE(
      (
        SELECT STRING_AGG(b.Name, ',')
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId
      ),
      ''
    ) AS Extra3, -- OwnerBadges
    (p.Score * 1.5) + ((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) * 0.75) AS Extra4, -- Impact
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
Answers AS (
  SELECT
    a.Id AS PostId,
    2 AS Type,
    a.Title AS Title,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    COALESCE(uu.DisplayName, 'Unknown') AS OwnerName,
    COALESCE(uu.Reputation, 0) AS OwnerRep,
    NULL AS Extra1, -- keep alignment with Questions
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS Extra2, -- CommentCount
    (SELECT Title FROM Posts qp WHERE qp.Id = a.ParentId) AS Extra3, -- ParentQuestionTitle
    (a.Score * 1.5) + ((SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) * 0.5) AS Extra4, -- Impact
    ROW_NUMBER() OVER (ORDER BY a.Score DESC, a.ViewCount DESC, a.CreationDate DESC) AS rn
  FROM Posts a
  LEFT JOIN Users uu ON a.OwnerUserId = uu.Id
  WHERE a.PostTypeId = 2
)
SELECT *
FROM (
  SELECT * FROM Questions
  UNION ALL
  SELECT * FROM Answers
) AS combined
ORDER BY Type, rn
LIMIT 1000;