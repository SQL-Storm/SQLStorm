-- {"query": "32025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 333} 
SELECT 
    u.DisplayName,
    u.Reputation,
    p.Title AS QuestionTitle,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS AnswerCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT ARRAY_AGG(t.TagName) FROM Tags t WHERE POSITION(t.TagName IN p.Tags) > 0) AS TagList,
    COALESCE((SELECT CreationDate FROM PostHistory ph WHERE ph.PostId = p.Id ORDER BY ph.CreationDate DESC LIMIT 1), p.CreationDate) AS LastEditDate,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1
    AND u.Reputation > 1000
ORDER BY 
    p.CreationDate DESC
LIMIT 100;