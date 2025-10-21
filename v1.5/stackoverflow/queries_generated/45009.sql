-- {"query": "45009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 20646, "output_tokens": 3865} 
WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount,
        u.Reputation,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC, p.ViewCount DESC) AS tag_rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    JOIN 
        Tags t ON EXISTS (
            SELECT 1 
            FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag 
            WHERE tag = t.TagName
        )
    WHERE 
        p.PostTypeId = 1 
        AND p.Score > 10 
        AND u.Reputation > 1000
), 
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    rp.TagName,
    rp.tag_rank,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    ua.DisplayName,
    ua.QuestionCount,
    ua.VoteCount,
    ua.BadgeCount
FROM 
    RankedPosts rp
JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.UserId
WHERE 
    rp.tag_rank <= 5
ORDER BY 
    rp.TagName, 
    rp.tag_rank
LIMIT 100;