-- {"query": "15052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 123755, "output_tokens": 36571} 
WITH UserBadgeActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS PostActivityRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE 
        b.TagBased = 0 
        AND p.PostTypeId IN (1, 2)
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, b.Name, b.Class
),
PostLinkMetrics AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType,
        COUNT(*) AS LinkCount,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvotes
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Votes v ON pl.PostId = v.PostId
    GROUP BY pl.PostId, pl.RelatedPostId, lt.Name
)
SELECT 
    uba.UserId,
    uba.DisplayName,
    uba.BadgeName,
    uba.Class,
    uba.PostCount,
    uba.AvgPostScore,
    plm.LinkType,
    plm.LinkCount,
    COALESCE(plm.HasUpvotes, 0) AS HasUpvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = uba.UserId) AS CommentCount,
    DENSE_RANK() OVER (ORDER BY uba.AvgPostScore DESC) AS ScoreRank
FROM UserBadgeActivity uba
FULL OUTER JOIN PostLinkMetrics plm ON uba.UserId = plm.PostId
WHERE 
    uba.PostActivityRank <= 10
    AND (uba.AvgPostScore > 5 OR plm.LinkCount > 3)
ORDER BY 
    uba.AvgPostScore DESC, 
    plm.LinkCount DESC
LIMIT 100;