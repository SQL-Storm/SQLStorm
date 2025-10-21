-- {"query": "14089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 590}
WITH cte AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.Title, 
    p.Body, 
    p.Tags, 
    p.OwnerUserId,
    u.Reputation, 
    u.Location,
    u.AboutMe,
    CASE WHEN EXISTS(
      SELECT 1 
      FROM Badges b
      WHERE b.UserId = p.OwnerUserId
        AND b.Name IN ('Commentator', 'Notable Question', 'Talkative', 'Enthusiast', 'Supporter')
        AND b.Class IN (2, 3)
    ) THEN 1 ELSE 0 END AS HasBadges
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 
    AND p.CreationDate >= DATEADD(year, -2, GETDATE())
    AND p.ClosedDate IS NULL
), ranked_questions AS (
  SELECT 
    Id, 
    PostTypeId, 
    Title, 
    Body, 
    Tags, 
    OwnerUserId, 
    Reputation, 
    Location, 
    AboutMe,
    HasBadges,
    ROW_NUMBER() OVER(PARTITION BY OwnerUserId ORDER BY CreationDate DESC) AS rn
  FROM cte
)
SELECT 
  q.Id, 
  q.Title, 
  q.Body, 
  q.Tags,
  q.Reputation,
  q.Location,
  q.AboutMe,
  q.HasBadges,
  DENSE_RANK() OVER(ORDER BY q.Reputation DESC) AS ReputationRank,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotes,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCount,
  (SELECT COUNT(*) FROM Posts p WHERE p.ParentId = q.Id) AS AnswerCount
FROM ranked_questions q
WHERE q.rn = 1
ORDER BY q.Reputation DESC;
