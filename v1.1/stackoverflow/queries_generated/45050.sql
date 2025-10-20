-- {"query": "45050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 114700, "output_tokens": 20690} 
WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Tags, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) ORDER BY p.Score DESC, p.ViewCount DESC) AS TagRank,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
        AND p.Tags IS NOT NULL 
        AND p.CreationDate > '2015-01-01'
),
UserBadgeStats AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.Reputation
)
SELECT 
    r.Id,
    r.Title,
    r.Tags,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.TagRank,
    r.UpVotes,
    r.DownVotes,
    ubs.Reputation,
    ubs.BadgeCount,
    ubs.GoldBadges
FROM 
    RankedPosts r
JOIN 
    Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = r.Id)
JOIN 
    UserBadgeStats ubs ON ubs.UserId = u.Id
WHERE 
    r.TagRank <= 10
    AND ubs.Reputation > 1000
    AND r.UpVotes > r.DownVotes
ORDER BY 
    r.Score DESC, r.ViewCount DESC
LIMIT 100;