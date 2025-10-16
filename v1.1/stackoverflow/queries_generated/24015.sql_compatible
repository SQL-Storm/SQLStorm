WITH
UserStats AS (
    SELECT u.Id                AS UserId,
           u.Reputation,
           u.CreationDate,
           COUNT(p.Id)          AS PostCnt,
           SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PosPostCnt,
           AVG(p.Score)         AS AvgScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
PostMeta AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.OwnerUserId,
           COALESCE(v.VCnt,0)  AS VoteCnt,
           COALESCE(c.CCnt,0)  AS CommentCnt
    FROM Posts p
    LEFT JOIN (
          SELECT PostId, COUNT(*) AS VCnt
          FROM Votes
          WHERE VoteTypeId IN (2,3)
          GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN (
          SELECT PostId, COUNT(*) AS CCnt
          FROM Comments
          GROUP BY PostId
    ) c ON c.PostId = p.Id
),
PostStats AS (
    SELECT pm.Id,
           pm.Title,
           pm.Score,
           pm.VoteCnt,
           pm.CommentCnt,
           pm.OwnerUserId,
           (SELECT AVG(LENGTH(c.Text))
            FROM Comments c
            WHERE c.PostId = pm.Id) AS AvgComLen
    FROM PostMeta pm
    WHERE pm.VoteCnt  > 0
      AND pm.Score    > 0
      AND pm.VoteCnt  > pm.CommentCnt
),
TagTop AS (
    SELECT t.TagName,
           t.Count,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
),
DupPosts AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           pl.LinkTypeId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),
Combined AS (
    SELECT ps.Id,
           ps.Title,
           ps.Score,
           ps.VoteCnt,
           ps.CommentCnt,
           ps.AvgComLen,
           us.Reputation,
           tt.TagName AS TopTag
    FROM PostStats ps
    JOIN UserStats us ON us.UserId = ps.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT tt.TagName
        FROM TagTop tt
        WHERE tt.TagName = ANY(string_to_array(ps.Title, ' '))
          AND tt.rn = 1
        LIMIT 1
    ) tt ON TRUE

    UNION ALL

    SELECT d.PostId      AS Id,
           NULL            AS Title,
           NULL            AS Score,
           NULL            AS VoteCnt,
           NULL            AS CommentCnt,
           NULL            AS AvgComLen,
           NULL            AS Reputation,
           NULL            AS TopTag
    FROM DupPosts d
)
SELECT Id,
       Title,
       Score,
       VoteCnt,
       CommentCnt,
       AvgComLen,
       Reputation,
       TopTag
FROM Combined
WHERE COALESCE(Score,0) > 0
ORDER BY Reputation DESC NULLS LAST,
         VoteCnt DESC NULLS LAST
LIMIT 200;