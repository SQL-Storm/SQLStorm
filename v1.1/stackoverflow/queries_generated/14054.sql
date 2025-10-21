-- {"query": "14054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 938}
WITH cte AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.OwnerUserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views AS UserViews,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Open'
    END AS PostStatus,
    CASE
      WHEN p.AnswerCount > 0 THEN 'Has Answers'
      ELSE 'No Answers'
    END AS AnswerStatus,
    CASE
      WHEN p.FavoriteCount > 0 THEN 'Favorited'
      ELSE 'Not Favorited'
    END AS FavoriteStatus,
    COALESCE(ph.Name, 'Unknown') AS PostHistoryType,
    COALESCE(ct.Name, 'Unknown') AS CloseReason,
    COALESCE(lt.Name, 'Unknown') AS LinkType,
    COALESCE(vt.Name, 'Unknown') AS VoteType
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes ct ON CAST(ph.Comment AS INT) = ct.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  LEFT JOIN Votes v ON p.Id = v.PostId
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId = 1 -- Questions only
),
top_posts AS (
  SELECT
    Id,
    PostTypeId,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    ClosedDate,
    CommunityOwnedDate,
    OwnerUserId,
    Reputation,
    UserCreationDate,
    LastAccessDate,
    UserViews,
    UserUpVotes,
    UserDownVotes,
    PostStatus,
    AnswerStatus,
    FavoriteStatus,
    PostHistoryType,
    CloseReason,
    LinkType,
    VoteType,
    ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, ViewCount DESC) AS rn
  FROM cte
)
SELECT
  Id,
  PostTypeId,
  CreationDate,
  Score,
  ViewCount,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  ClosedDate,
  CommunityOwnedDate,
  OwnerUserId,
  Reputation,
  UserCreationDate,
  LastAccessDate,
  UserViews,
  UserUpVotes,
  UserDownVotes,
  PostStatus,
  AnswerStatus,
  FavoriteStatus,
  PostHistoryType,
  CloseReason,
  LinkType,
  VoteType
FROM top_posts
WHERE rn <= 10
ORDER BY Score DESC, ViewCount DESC;
