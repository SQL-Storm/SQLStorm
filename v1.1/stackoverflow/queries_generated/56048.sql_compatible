WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  JOIN 
    Votes v ON p.Id = v.PostId
  WHERE 
    v.VoteTypeId IN (2, 3)
  GROUP BY 
    u.Id, u.DisplayName
  ORDER BY 
    UpVotes DESC
  LIMIT 10
),
QuestionPosts AS (
  SELECT 
    p.Id, 
    p.OwnerUserId,
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
AnswerPosts AS (
  SELECT 
    p.Id, 
    p.ParentId,
    p.Score, 
    p.CommentCount
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 2
),
PostHistoryTypes AS (
  SELECT 
    ph.Id, 
    ph.PostId, 
    ph.PostHistoryTypeId, 
    ph.CreationDate
  FROM 
    PostHistory ph
  WHERE 
    ph.PostHistoryTypeId IN (10, 11)
)
SELECT 
  tu.DisplayName, 
  tu.UpVotes, 
  tu.DownVotes, 
  qp.Title, 
  qp.Score, 
  qp.ViewCount, 
  qp.AnswerCount, 
  qp.CommentCount, 
  ap.Score AS AnswerScore, 
  ap.CommentCount AS AnswerCommentCount, 
  pht.PostHistoryTypeId, 
  pht.CreationDate
FROM 
  TopUsers tu
JOIN 
  QuestionPosts qp ON tu.Id = qp.OwnerUserId
JOIN 
  AnswerPosts ap ON qp.Id = ap.ParentId
JOIN 
  PostHistoryTypes pht ON qp.Id = pht.PostId
GROUP BY
  tu.DisplayName,
  tu.UpVotes,
  tu.DownVotes,
  qp.Title,
  qp.Score,
  qp.ViewCount,
  qp.AnswerCount,
  qp.CommentCount,
  ap.Score,
  ap.CommentCount,
  pht.PostHistoryTypeId,
  pht.CreationDate
ORDER BY 
  tu.UpVotes DESC;