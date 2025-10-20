-- {"query": "32043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 479} 
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.Views,
    U.UpVotes,
    U.DownVotes,
    (
        SELECT COUNT(*)
        FROM Posts P
        WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 1
    ) AS TotalQuestions,
    (
        SELECT COUNT(*)
        FROM Posts P
        WHERE P.OwnerUserId = U.Id AND P.PostTypeId = 2
    ) AS TotalAnswers,
    (
        SELECT COUNT(*)
        FROM Badges B
        WHERE B.UserId = U.Id AND B.Class = 1
    ) AS GoldBadges,
    (
        SELECT COUNT(*)
        FROM Badges B
        WHERE B.UserId = U.Id AND B.Class = 2
    ) AS SilverBadges,
    (
        SELECT COUNT(*)
        FROM Badges B
        WHERE B.UserId = U.Id AND B.Class = 3
    ) AS BronzeBadges,
    (
        SELECT COUNT(*)
        FROM Votes V
        WHERE V.UserId = U.Id AND V.VoteTypeId = 2
    ) AS TotalUpVotesGiven,
    (
        SELECT COUNT(*)
        FROM Votes V
        WHERE V.UserId = U.Id AND V.VoteTypeId = 3
    ) AS TotalDownVotesGiven,
    (
        SELECT COUNT(DISTINCT PH.PostId)
        FROM PostHistory PH
        WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4,5,6)
    ) AS TotalEditsMade
FROM 
    Users U
LEFT JOIN 
    Posts P ON P.OwnerUserId = U.Id
LEFT JOIN 
    Badges B ON B.UserId = U.Id
LEFT JOIN 
    Votes V ON V.UserId = U.Id
LEFT JOIN 
    PostHistory PH ON PH.UserId = U.Id
WHERE 
    U.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
ORDER BY 
    U.Reputation DESC, U.CreationDate DESC
LIMIT 100;