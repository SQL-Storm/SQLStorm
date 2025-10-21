-- {"query": "14081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1124}
WITH cte AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount,
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
    END AS CommentCount,
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
       AND b.TagBased = 0
       AND b.Class = 1),
      0  
    ) AS GoldBadgesCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM Badges b
       WHERE b.UserId = p.OwnerUserId
       AND b.TagBased = 0
       AND b.Class = 2),
      0
    ) AS SilverBadgesCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM Badges b
       WHERE b.UserId = p.OwnerUserId
       AND b.TagBased = 0
       AND b.Class = 3),
      0
    ) AS BronzeBadgesCount,
    COALESCE(
      (SELECT COUNT(*)
       FROM Badges b
       WHERE b.UserId = p.OwnerUserId
       AND b.TagBased = 1),
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
  CommentCount,
  FavoriteCount,
  ClosedDate,
  CommunityOwnedDate,
  VoteCount,
  BountyCount,
  ReopenVoteCount,
  CloseVoteCount,
  CommentCount AS PostCommentCount,
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
ORDER BY PostId DESC
LIMIT 100;
