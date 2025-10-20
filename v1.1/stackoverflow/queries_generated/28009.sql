-- {"query": "28009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1415} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS RankInClass
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, b.Class
), PostClosures AS (
    SELECT 
        ph.PostId,
        MAX(CASE WHEN crt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS IsDuplicateClosure,
        COUNT(*) AS ClosureEvents
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
)
SELECT 
    us.UserId,
    us.Reputation,
    us.BadgeCount,
    us.PostCount,
    us.CommentCount,
    us.RankInClass,
    p.Id AS PostId,
    p.Title,
    COALESCE(SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2), 'untagged') AS PrimaryTag,
    (SELECT AVG(AnswerCount) 
     FROM Posts p2 
     WHERE p2.Tags LIKE '%' || COALESCE(SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2), '') || '%'
       AND p2.PostTypeId = 1) AS AvgAnswersForTag,
    v.TotalUpvotes,
    v.TotalDownvotes,
    ph.ClosureEvents,
    CASE 
        WHEN ph.IsDuplicateClosure = 1 THEN 'Duplicate'
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Active'
    END AS PostStatus,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostRank
FROM UserStats us
JOIN Posts p ON us.UserId = p.OwnerUserId
LEFT JOIN PostClosures ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT 
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM Votes
    GROUP BY PostId
) v ON p.Id = v.PostId
WHERE p.CreationDate BETWEEN '2015-01-01' AND '2023-12-31'
  AND p.Score > 10
  AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<performance>%')
  AND EXISTS (
    SELECT 1
    FROM PostHistory ph2
    WHERE ph2.PostId = p.Id
      AND ph2.PostHistoryTypeId IN (5,6)
      AND ph2.CreationDate < p.LastEditDate + INTERVAL '7 days'
  )
  AND p.OwnerUserId NOT IN (
    SELECT UserId 
    FROM Votes 
    WHERE VoteTypeId = 4  -- Offensive votes
    GROUP BY UserId 
    HAVING COUNT(*) > 5
  )
ORDER BY 
    us.RankInClass,
    p.Score DESC,
    ph.ClosureEvents DESC
LIMIT 1000;
