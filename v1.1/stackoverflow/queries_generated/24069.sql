-- {"query": "24069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1573} 
WITH TaggedPosts AS (
    SELECT p.Id                      AS PostId,
           p.Title,
           p.Tags,
           p.CreationDate,
           p.Score,
           COALESCE(vCnt.CriticalVotes, 0)  AS CriticalVotes,
           COALESCE(bCnt.BadgeCount, 0)     AS BadgeCount,
           COALESCE(dCnt.DuplicateParents, 0) AS DuplicateParents
    FROM Posts p
    LEFT JOIN (
        SELECT ph.PostId,
               COUNT(*) AS CriticalVotes
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
          AND ph.Comment IN ('101','102','103','104','105')
        GROUP BY ph.PostId
    ) vCnt  ON vCnt.PostId = p.Id
    LEFT JOIN (
        SELECT b.UserId,
               COUNT(*) AS BadgeCount
        FROM Badges b
        GROUP BY b.UserId
    ) bCnt  ON bCnt.UserId = p.OwnerUserId
    LEFT JOIN (
        SELECT p1.PostId,
               COUNT(*) AS DuplicateParents
        FROM PostLinks p1
        WHERE p1.LinkTypeId = 3   -- duplicate
          AND EXISTS (
               SELECT 1
               FROM PostLinks p2
               WHERE p2.RelatedPostId = p1.PostId
                 AND p2.LinkTypeId = 3
          )
        GROUP BY p1.PostId
    ) dCnt  ON dCnt.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%<c%'>%
),
Ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (PARTITION BY DATEPART(year, CreationDate)
                              ORDER BY (Score + CriticalVotes*5) DESC,
                                       Views DESC) AS RN
    FROM TaggedPosts t
    WHERE (Score + CriticalVotes*5) > 0
),
UserMetrics AS (
    SELECT u.Id        AS UserId,
           u.Reputation,
           COALESCE(qCnt.Ques,0)   AS QuestionCount,
           COALESCE(aCnt.Ans,0)    AS AnswerCount,
           STRING_AGG(DISTINCT 
               TRIM(both '><' FROM s.TagName), ', '
           )                  AS PopularTagList
    FROM Users u
    LEFT JOIN (
        SELECT p.OwnerUserId,
               COUNT(*) AS Ques
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ) qCnt  ON qCnt.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT a.ParentId,
               COUNT(*) AS Ans
        FROM Posts a
        WHERE a.PostTypeId = 2
        GROUP BY a.ParentId
    ) aCnt  ON aCnt.ParentId = u.Id
    LEFT JOIN LATERAL (
        SELECT TRIM(both '><') AS TagName
        FROM STRING_TO_ARRAY(COALESCE(p.Tags, ''), '><') s(TagName)
        WHERE p.OwnerUserId = u.Id
    ) s ON TRUE
    GROUP BY u.Id, u.Reputation, qCnt.Ques, aCnt.Ans
)
SELECT r.PostId,
       r.Title,
       r.Tags,
       r.CreationDate,
       r.Score,
       r.CriticalVotes,
       r.BadgeCount,
       r.DuplicateParents,
       u.Reputation,
       u.QuestionCount,
       u.AnswerCount,
       u.PopularTagList
FROM Ranked r
JOIN UserMetrics u
      ON u.UserId = r.OwnerUserId
WHERE r.RN <= 10
  AND r.DuplicateParents < 5
ORDER BY r.Score DESC,
         r.CreationDate DESC;