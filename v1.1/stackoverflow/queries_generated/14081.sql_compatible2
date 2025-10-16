WITH cte AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount AS SourceCommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    CASE 
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*) 
        FROM Votes v
        WHERE v.PostId = p.Id 
          AND v.VoteTypeId IN (2, 3)
      )
      ELSE NULL
    END AS VoteCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
          AND v.VoteTypeId = 8
      )
      ELSE NULL  
    END AS BountyCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
          AND v.VoteTypeId = 7
      )
      ELSE NULL
    END AS ReopenVoteCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
          AND v.VoteTypeId = 6
      )
      ELSE NULL
    END AS CloseVoteCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id
      )
      ELSE NULL
    END AS ComputedCommentCount,
    COALESCE(
      (SELECT COUNT(*) 
       FROM PostLinks pl 
       WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3),
      0
    ) AS DuplicateCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM PostLinks pl
       WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1),
       0
    ) AS LinkedCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM Badges b
       WHERE b.UserId = p.OwnerUserId
         AND (CASE WHEN b.TagBased IS NOT NULL THEN CAST(b.TagBased AS INTEGER) ELSE 0 END) = 0
         AND b.Class = 1),
      0  
    ) AS GoldBadgesCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM Badges b
       WHERE b.UserId = p.OwnerUserId
         AND (CASE WHEN b.TagBased IS NOT NULL THEN CAST(b.TagBased AS INTEGER) ELSE 0 END) = 0
         AND b.Class = 2),
      0
    ) AS SilverBadgesCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM Badges b
       WHERE b.UserId = p.OwnerUserId
         AND (CASE WHEN b.TagBased IS NOT NULL THEN CAST(b.TagBased AS INTEGER) ELSE 0 END) = 0
         AND b.Class = 3),
      0
    ) AS BronzeBadgesCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM Badges b
       WHERE b.UserId = p.OwnerUserId
         AND (CASE WHEN b.TagBased IS NOT NULL THEN CAST(b.TagBased AS INTEGER) ELSE 0 END) = 1),
      0  
    ) AS TagBadgesCount
  FROM Posts p
)
SELECT 
  PostId,
  PostTypeId,
  CreationDate,
  OwnerUserId,
  AcceptedAnswerId,
  AnswerCount,
  SourceCommentCount,
  FavoriteCount,
  ClosedDate,
  CommunityOwnedDate,
  VoteCount,
  BountyCount,
  ReopenVoteCount,
  CloseVoteCount,
  ComputedCommentCount AS PostCommentCount,
  DuplicateCount,
  LinkedCount,
  GoldBadgesCount,
  SilverBadgesCount,
  BronzeBadgesCount,
  TagBadgesCount,
  CASE
    WHEN ClosedDate IS NOT NULL THEN 'Closed'
    WHEN CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    WHEN AcceptedAnswerId IS NOT NULL THEN 'Answered'
    WHEN AnswerCount > 0 THEN 'Has Answers'
    ELSE 'Open'
  END AS PostStatus
FROM cte
GROUP BY
  PostId,
  PostTypeId,
  CreationDate,
  OwnerUserId,
  AcceptedAnswerId,
  AnswerCount,
  SourceCommentCount,
  FavoriteCount,
  ClosedDate,
  CommunityOwnedDate,
  VoteCount,
  BountyCount,
  ReopenVoteCount,
  CloseVoteCount,
  ComputedCommentCount,
  DuplicateCount,
  LinkedCount,
  GoldBadgesCount,
  SilverBadgesCount,
  BronzeBadgesCount,
  TagBadgesCount
ORDER BY PostId DESC
FETCH FIRST 100 ROWS ONLY;