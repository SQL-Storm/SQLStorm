-- {"query": "1008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 448} 
WITH UserReputation AS (
    SELECT U.Id AS UserId, U.DisplayName, U.Reputation,
           ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
    WHERE U.Reputation IS NOT NULL
),
PostDetail AS (
    SELECT P.Id AS PostId, P.Title, P.CreationDate, P.Score, 
           P.OwnerUserId, U.DisplayName AS OwnerDisplayName, P.ViewCount, 
           COUNT(CASE WHEN C.Id IS NOT NULL THEN 1 END) AS CommentCount,
           SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           COALESCE(MAX(B.Name), 'No Badge') AS TopBadge
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY P.Id, P.Title, P.CreationDate, P.Score, 
             P.OwnerUserId, U.DisplayName, P.ViewCount
),
RecentPosts AS (
    SELECT PD.*, UR.DisplayName AS TopUser, UR.ReputationRank
    FROM PostDetail PD
    JOIN UserReputation UR ON PD.OwnerUserId = UR.UserId
    WHERE PD.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
)
SELECT RP.PostId, RP.Title, RP.ViewCount, RP.Score, RP.CommentCount, 
       RP.TopUser, RP.ReputationRank, 
       CASE 
           WHEN RP.Score > 10 THEN 'High Scorer'
           WHEN RP.Score BETWEEN 1 AND 10 THEN 'Moderate Scorer'
           ELSE 'Low Scorer' 
       END AS ScoreCategory, 
       CASE 
           WHEN RP.TopBadge = 'No Badge' THEN 'No Badges Awarded'
           ELSE RP.TopBadge 
       END AS BadgeStatus
FROM RecentPosts RP
ORDER BY RP.ReputationRank, RP.ViewCount DESC
LIMIT 100;