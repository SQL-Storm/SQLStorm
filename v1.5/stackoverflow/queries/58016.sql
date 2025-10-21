-- {"query": "58016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 2968} 
SELECT 
    U.Id,
    U.DisplayName,
    U.Reputation,
    (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = U.Id) AS PostCount,
    (SELECT AVG(P.Score) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.Score > 0) AS AvgPostScore,
    (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadges,
    (SELECT COUNT(*) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (5, 6)) AS Edits,
    RANK() OVER (ORDER BY (SELECT SUM(B.Class) FROM Badges B WHERE B.UserId = U.Id) DESC NULLS LAST) AS BadgeWeightRank
FROM 
    Users U
WHERE 
    U.Reputation > 5000
    AND EXISTS (SELECT 1 FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL)
    AND (SELECT COUNT(DISTINCT P.Tags) FROM Posts P WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 1) >= 5
    AND (SELECT MAX(CreationDate) FROM Posts P WHERE P.OwnerUserId = U.Id) > cast('2024-10-01' as date) - INTERVAL '1 year'
ORDER BY 
    (SELECT MAX(P.Score) FROM Posts P WHERE P.OwnerUserId = U.Id) DESC NULLS LAST,
    U.Reputation DESC
LIMIT 100;