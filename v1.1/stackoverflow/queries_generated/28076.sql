-- {"query": "28076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1761} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COALESCE(b.BadgeCount, 0) AS BadgeCount,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS RankInClass,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvgScore
    FROM Users u
    LEFT JOIN (
        SELECT UserId, Class, COUNT(*) AS BadgeCount 
        FROM Badges 
        GROUP BY UserId, Class
    ) b ON u.Id = b.UserId
), PostAnalysis AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS ActualCommentCount,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeSnippetCount,
        (SELECT COUNT(DISTINCT ph.UserId) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.AcceptedAnswerId AND ph.PostHistoryTypeId IN (5,8)
        ) AS AcceptedAnswerEdits,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ', '), 'Untagged') AS Tags,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            ELSE 'Standard'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT DISTINCT TagName 
        FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t ON true
    WHERE p.PostTypeId = 1
      AND (p.Score > 50 OR p.FavoriteCount > 10)
      AND EXISTS (
          SELECT 1 
          FROM PostHistory ph 
          WHERE ph.PostId = p.AcceptedAnswerId 
          GROUP BY ph.PostId 
          HAVING COUNT(*) > 3
      )
    GROUP BY p.Id
)
SELECT 
    pa.*,
    us.RankInClass,
    us.MovingAvgScore,
    (us.UpVotes * 1.0 / NULLIF(us.DownVotes, 0)) AS VoteRatio,
    EXTRACT(YEAR FROM AGE(u.CreationDate)) AS AccountAgeYears
FROM PostAnalysis pa
LEFT JOIN UserStats us ON pa.OwnerUserId = us.Id
LEFT JOIN Users u ON pa.OwnerUserId = u.Id
WHERE pa.ActualCommentCount > pa.AnswerCount * 0.5
  AND (us.BadgeCount > 10 OR pa.CodeSnippetCount > 5)
  AND (pa.Tags LIKE '%sql%' OR pa.Tags LIKE '%performance%')
UNION ALL
SELECT 
    pa.*,
    NULL AS RankInClass,
    NULL AS MovingAvgScore,
    NULL AS VoteRatio,
    NULL AS AccountAgeYears
FROM PostAnalysis pa
WHERE NOT EXISTS (
    SELECT 1 
    FROM PostLinks pl 
    WHERE pl.PostId = pa.Id 
      AND pl.LinkTypeId = 3
)
ORDER BY Score DESC, ViewCount DESC;
