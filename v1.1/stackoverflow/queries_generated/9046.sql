-- {"query": "9046.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 4138} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RowNum,
        COUNT(*)        OVER(PARTITION BY p.OwnerUserId)      AS UserPostCount
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
UserBadgeAgg AS (
    SELECT 
        u.Id                         AS UserId,
        COUNT(b.Id)                  AS BadgeCount,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGold,
        STUFF(
          (SELECT ',' + b2.Name
           FROM Badges b2
           WHERE b2.UserId = u.Id
           ORDER BY b2.Date DESC
           FOR XML PATH('')), 
          1, 1, ''
        )                          AS BadgesList
    FROM Users u
    LEFT JOIN Badges b 
      ON b.UserId = u.Id
    GROUP BY u.Id
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        ROW_NUMBER() OVER(ORDER BY COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) DESC) AS HotTagRank
    FROM Tags t
    LEFT JOIN Posts p 
      ON CHARINDEX('<' + t.TagName + '>', p.Tags) > 0
    GROUP BY t.TagName
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastChange,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13) THEN 1 ELSE 0 END) AS CloseOrReopenCount
    FROM PostHistory ph
    GROUP BY ph.PostId
),
LowViewPosts AS (
    SELECT 
        p2.Id     AS PostId,
        p2.ViewCount
    FROM Posts p2
    WHERE p2.ViewCount < (
        SELECT AVG(ViewCount) 
        FROM Posts 
        WHERE PostTypeId = 1
    )
)
SELECT
    rp.Id                       AS PostId,
    rp.PostTypeId,
    rp.RowNum,
    COALESCE(rp.UserPostCount,0) AS TotalUserPosts,
    uba.BadgeCount,
    uba.HasGold,
    uba.BadgesList,
    ra.LastChange,
    ra.CloseOrReopenCount,
    CASE 
      WHEN rp.Score < 0 THEN 'Negative'
      WHEN rp.Score = 0 THEN 'Zero'
      ELSE 'Positive'
    END                         AS ScoreCategory,
    LEN(p.Title) 
      - LEN(REPLACE(p.Title,' ',''))
      + 1                       AS WordCount,
    COALESCE(ans.AvgScore,0)     AS AvgAnswerScore,
    ans.AnswerCount,
    CONCAT(
      ISNULL(NULLIF(u.DisplayName,''),'[Anon]'),
      ' @',
      ISNULL(u.Location,'Unknown')
    )                           AS UserLabel,
    voter.VoteBalance
FROM RankedPosts rp
INNER JOIN Posts p 
  ON p.Id = rp.Id
LEFT JOIN Users u 
  ON u.Id = p.OwnerUserId
LEFT JOIN UserBadgeAgg uba 
  ON uba.UserId = u.Id
LEFT JOIN RecentActivity ra 
  ON ra.PostId = rp.Id
OUTER APPLY (
    SELECT 
        AVG(a.Score) AS AvgScore, 
        COUNT(*)    AS AnswerCount
    FROM Posts a
    WHERE a.ParentId = rp.Id
) ans
LEFT JOIN (
    SELECT 
        v.PostId,
        SUM(
          CASE 
            WHEN vt.Name LIKE 'Up%'   THEN  1 
            WHEN vt.Name LIKE 'Down%' THEN -1 
            ELSE 0 
          END
        ) AS VoteBalance
    FROM Votes v
    JOIN VoteTypes vt 
      ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
) voter 
  ON voter.PostId = rp.Id
WHERE rp.RowNum <= 200
  AND EXISTS (
      SELECT 1
      FROM TagStats ts
      WHERE ts.TagName = LEFT(
          SUBSTRING(p.Tags,2,LEN(p.Tags)-2),
          CHARINDEX('>',SUBSTRING(p.Tags,2,LEN(p.Tags)-2))-1
        )
        AND ts.QuestionCount > 10000
  )

UNION

SELECT TOP 10
    p3.Id, 
    p3.PostTypeId,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM Posts p3
WHERE p3.ViewCount > 50000
ORDER BY p3.ViewCount DESC

EXCEPT

SELECT
    lp.PostId,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM LowViewPosts lp;
