-- {"query": "9061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3356} 

WITH RecentActive AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        COUNT(*)       OVER (PARTITION BY p.OwnerUserId)            AS total_posts
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
UserStats AS (
    SELECT
        u.Id                   AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views                AS ProfileViews,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyGiven,
        AVG(EXTRACT(EPOCH FROM NOW() - u.LastAccessDate)) AS AvgSecondsSinceAccess
    FROM Users u
    LEFT JOIN Votes v
      ON v.UserId = u.Id
     AND v.VoteTypeId = 8      /* BountyStart */
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopTags AS (
    SELECT
        unnest(
          string_to_array(
            substring(p.Tags, 2, length(p.Tags) - 2),
            '><'
          )
        ) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1      /* questions only */
),
TagCounts AS (
    SELECT
        Tag,
        COUNT(*) AS QuestionCount
    FROM TopTags
    GROUP BY Tag
    HAVING COUNT(*) > 100
),
PostCommentStats AS (
    SELECT
        p.Id      AS PostId,
        COUNT(c.Id) AS CommentCount
    FROM Posts p
    FULL OUTER JOIN Comments c
      ON c.PostId = p.Id
    GROUP BY p.Id
),
Combined AS (
    SELECT
        r.*,
        us.DisplayName,
        us.Reputation,
        us.TotalBountyGiven,
        pcs.CommentCount
    FROM RecentActive r
    LEFT JOIN UserStats us
      ON us.UserId = r.OwnerUserId
    LEFT JOIN PostCommentStats pcs
      ON pcs.PostId = r.Id
),
Windowed AS (
    SELECT
        *,
        RANK() OVER (
          PARTITION BY PostTypeId
          ORDER BY Score DESC, ViewCount DESC
        ) AS ScoreRank,
        CASE WHEN total_posts <> 0
             THEN Score::DECIMAL / total_posts
             ELSE NULL
        END AS AvgScorePerPost
    FROM Combined
),
Errors AS (
    SELECT p.Id AS PostId
    FROM Posts p
    WHERE LOWER(p.Title) LIKE '%error%'
),
Excluded AS (
    SELECT Id FROM Posts
    EXCEPT
    SELECT PostId FROM Errors
)
SELECT
    w.PostTypeId,
    w.Id                AS PostId,
    COALESCE(w.DisplayName, '[deleted]') AS Owner,
    w.Score,
    w.ViewCount,
    w.ScoreRank,
    w.AvgScorePerPost,
    tc.QuestionCount,
    w.CommentCount,
    EXISTS (
      SELECT 1
      FROM Votes v2
      WHERE v2.PostId = w.Id
        AND v2.VoteTypeId = 2               /* UpMod */
        AND v2.CreationDate >= NOW() - INTERVAL '7 days'
    ) AS RecentUpvote,
    CASE
      WHEN w.Tags IS NOT NULL
      THEN substring(w.Tags FROM '<([^>]+)>')
      ELSE NULL
    END AS FirstTag,
    (w.CommentCount IS NULL OR
     substring(w.Tags FROM '<([^>]+)>') IS NULL) AS HasNullLogic
FROM Windowed w
LEFT JOIN TagCounts tc
  ON tc.Tag = (
       SELECT substring(w.Tags FROM '<([^>]+)>')
     )
WHERE w.rn = 1
  AND (w.Score > 5 OR w.ViewCount > 1000)
  AND w.Id IN (SELECT Id FROM Excluded)
ORDER BY w.ScoreRank

UNION ALL

SELECT
    0,
    0,
    'Summary',
    SUM(w.Score),
    SUM(w.ViewCount),
    NULL,
    NULL,
    NULL,
    NULL,
    FALSE,
    NULL,
    FALSE
FROM Windowed w
WHERE w.PostTypeId = 1;
