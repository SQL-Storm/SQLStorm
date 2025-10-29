-- {"query": "3728.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2169}
WITH TagList AS (
   SELECT p.Id AS PostId,
          UNNEST(string_to_array(
               COALESCE(NULLIF(SUBSTR(p.Tags, 2, LENGTH(p.Tags)-2), ''), ''), 
               '><')) AS Tag
   FROM Posts p
   WHERE p.PostTypeId = 1
),
TagStats AS (
   SELECT t.Tag,
          COUNT(*) AS TagPostCount,
          AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
          MAX(p.CreationDate) AS MostRecentPostDate
   FROM TagList t
   JOIN Posts p ON p.Id = t.PostId
   GROUP BY t.Tag
),
UserActivity AS (
   SELECT u.Id               AS UserId,
          u.DisplayName,
          u.Reputation,
          COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
          COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
          COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
          ROW_NUMBER() OVER (ORDER BY (COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)) DESC) AS ReputationRank
   FROM Users u
   LEFT JOIN Posts p ON p.OwnerUserId = u.Id
   GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
TopUsers AS (
   SELECT *
   FROM UserActivity
   WHERE ReputationRank <= 50
),
PostVotes AS (
   SELECT p.Id AS PostId,
          SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                   WHEN v.VoteTypeId = 3 THEN -1
                   ELSE 0 END)                     AS VoteScore,
          COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteCount
   FROM Posts p
   LEFT JOIN Votes v ON v.PostId = p.Id
   GROUP BY p.Id
),
RecentBadges AS (
   SELECT b.UserId,
          STRING_AGG(b.Name, ', ') AS BadgeList,
          MAX(b.Date) AS LastBadgeDate
   FROM Badges b
   WHERE b.Class = 1
   GROUP BY b.UserId
)
SELECT 
   p.Id                                      AS PostId,
   p.Title,
   p.CreationDate,
   p.Score,
   COALESCE(p.ViewCount,0)                   AS Views,
   pv.VoteScore,
   pv.FavoriteCount,
   u.DisplayName,
   u.Reputation,
   ua.NetVotes,
   ua.QuestionCount,
   ua.AnswerCount,
   ub.BadgeList,
   CASE 
       WHEN p.ClosedDate IS NOT NULL          THEN 'Closed'
       WHEN p.CommunityOwnedDate IS NOT NULL  THEN 'Community'
       ELSE 'Open'
   END                                      AS Status,
   ts.AvgScore                               AS TagAvgScore,
   ts.TagPostCount,
   ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY pv.VoteScore DESC) AS VoteRankWithinPost
FROM Posts p
LEFT JOIN PostVotes        pv  ON pv.PostId = p.Id
LEFT JOIN TopUsers         u   ON u.UserId = p.OwnerUserId
LEFT JOIN UserActivity     ua  ON ua.UserId = p.OwnerUserId
LEFT JOIN RecentBadges     ub  ON ub.UserId = p.OwnerUserId
LEFT JOIN LATERAL (
   SELECT tl.Tag,
          ts.AvgScore,
          ts.TagPostCount
   FROM TagList tl
   JOIN TagStats ts ON ts.Tag = tl.Tag
   WHERE tl.PostId = p.Id
   ORDER BY ts.TagPostCount DESC
   LIMIT 1
) ts ON TRUE
WHERE p.PostTypeId = 1
  AND (p.Score >= 0 OR COALESCE(p.ViewCount,0) > 1000)
  AND (u.Reputation IS NULL OR u.Reputation > 5000)
  AND (pv.VoteScore IS NULL OR pv.VoteScore <> 0)

UNION ALL

SELECT 
   q.Id                                     AS PostId,
   q.Title,
   q.CreationDate,
   q.Score,
   COALESCE(q.ViewCount,0)                  AS Views,
   NULL                                     AS VoteScore,
   NULL                                     AS FavoriteCount,
   NULL                                     AS DisplayName,
   NULL                                     AS Reputation,
   NULL                                     AS NetVotes,
   NULL                                     AS QuestionCount,
   NULL                                     AS AnswerCount,
   NULL                                     AS BadgeList,
   NULL                                     AS Status,
   NULL                                     AS TagAvgScore,
   NULL                                     AS TagPostCount,
   NULL                                     AS VoteRankWithinPost
FROM Posts q
WHERE q.PostTypeId = 1
  AND NOT EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = q.Id AND a.Score > 0)
ORDER BY PostId DESC
LIMIT 100;