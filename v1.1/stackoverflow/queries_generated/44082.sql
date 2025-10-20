-- {"query": "44082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 188108, "output_tokens": 65319} 

WITH cte AS (
  SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeTagBased,
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.CreationDate AS CommentCreationDate,
    l.Id AS LinkId,
    l.LinkTypeId,
    l.CreationDate AS LinkCreationDate,
    v.Id AS VoteId,
    v.VoteTypeId,
    v.CreationDate AS VoteCreationDate,
    v.BountyAmount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN PostLinks l ON p.Id = l.PostId
  LEFT JOIN Votes v ON p.Id = v.PostId
)
SELECT 
  PostId,
  PostTypeId,
  CreationDate,
  Title,
  Tags,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  ClosedDate,
  CommunityOwnedDate,
  UserId,
  Reputation,
  UserCreationDate,
  LastAccessDate,
  Views,
  UpVotes,
  DownVotes,
  BadgeId,
  BadgeName,
  BadgeDate,
  BadgeClass,
  BadgeTagBased,
  CommentId,
  CommentScore,
  CommentCreationDate,
  LinkId,
  LinkTypeId,
  LinkCreationDate,
  VoteId,
  VoteTypeId,
  VoteCreationDate,
  BountyAmount
FROM cte
ORDER BY PostId, BadgeDate DESC, CommentCreationDate, LinkCreationDate, VoteCreationDate;
