-- {"query": "32060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 384} 

SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    p.Id AS PostId,
    p.CreationDate AS PostCreationDate,
    p.Title AS QuestionTitle,
    p.Score AS PostScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 1) AS QuestionCount
FROM 
    Users u
INNER JOIN 
    Posts p ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1
    AND u.Reputation > 1000
    AND p.CreationDate > '2022-01-01'
    AND (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id) > 10
ORDER BY 
    p.Score DESC, u.Reputation DESC
LIMIT 100;
