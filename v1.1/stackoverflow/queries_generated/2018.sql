-- {"query": "2018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 643} 

WITH RecentEditors AS (
    SELECT 
        ph.PostId, 
        u.DisplayName AS EditorName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM 
        PostHistory ph
    JOIN 
        Users u ON ph.UserId = u.Id
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 6)  -- Edit Title, Edit Body, Edit Tags
),
BadgeWinners AS (
    SELECT 
        b.UserId, 
        COUNT(b.Id) AS BadgeCount,
        MAX(b.Date) AS LastBadgeDate
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
ViewedPosts AS (
    SELECT
        p.Id, 
        p.OwnerUserId, 
        p.ViewCount,
        COALESCE(SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END), 0) OVER (PARTITION BY p.OwnerUserId) AS PositiveScores
    FROM 
        Posts p
),
TopPostsByScore AS (
    SELECT 
        v.PostId, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS ScoreSum
    FROM 
        Votes v
    GROUP BY 
        v.PostId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(SUBSTRING(u.AboutMe, 1, 100), 'No Description') AS ShortDescription,
    bws.BadgeCount,
    CASE 
        WHEN vps.PositiveScores > 50 THEN 'High Contributor' 
        ELSE 'Regular Contributor' 
    END AS ContributionLevel,
    COUNT(distinct c.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadges,
    COALESCE(re.EditorName, 'No Recent Edits') AS MostRecentEditor
FROM 
    Users u
LEFT JOIN 
    BadgeWinners bw ON u.Id = bw.UserId
LEFT JOIN 
    ViewedPosts vps ON u.Id = vps.OwnerUserId
LEFT JOIN 
    Comments c ON c.UserId = u.Id
LEFT JOIN 
    RecentEditors re ON re.PostId = c.PostId AND re.rn = 1
LEFT JOIN 
    TopPostsByScore tps ON tps.PostId = (SELECT TOP 1 Id FROM Posts WHERE OwnerUserId = u.Id ORDER BY Score DESC)
GROUP BY 
    u.Id, u.DisplayName, u.AboutMe, bws.BadgeCount, vps.PositiveScores, re.EditorName
ORDER BY 
    bw.BadgeCount DESC, vps.PositiveScores DESC, CommentCount DESC;
