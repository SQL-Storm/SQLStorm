WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  WHERE 
    p.PostTypeId = 2 AND v.VoteTypeId IN (2, 3)
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 100
),
TopPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.Score > 10
),
QuestionHistory AS (
  SELECT 
    ph.PostId, 
    ph.PostHistoryTypeId, 
    ph.CreationDate, 
    ph.UserId, 
    ph.UserDisplayName
  FROM 
    PostHistory ph
  WHERE 
    ph.PostHistoryTypeId IN (10, 11)
),
CloseReasons AS (
  SELECT 
    crt.Id, 
    crt.Name
  FROM 
    CloseReasonTypes crt
)
SELECT 
  u.Id, 
  u.DisplayName, 
  tu.UpVotes, 
  tu.DownVotes, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.CommentCount, 
  cr.Name AS CloseReason,
  STRING_AGG(DISTINCT qh.UserDisplayName, ', ') AS UsersWhoClosed
FROM 
  Users u
LEFT JOIN 
  TopUsers tu ON u.Id = tu.Id
LEFT JOIN 
  Posts p ON u.Id = p.OwnerUserId AND p.Id IN (SELECT Id FROM TopPosts)
LEFT JOIN 
  PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
  CloseReasons cr ON (CASE WHEN ph.Comment ~ '^\s*[0-9]+\s*$' THEN CAST(TRIM(ph.Comment) AS INTEGER) ELSE NULL END) = cr.Id
LEFT JOIN 
  QuestionHistory qh ON p.Id = qh.PostId
GROUP BY 
  u.Id, u.DisplayName, tu.UpVotes, tu.DownVotes, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, cr.Name
ORDER BY 
  tu.UpVotes DESC;