-- {"query": "2057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 557} 

WITH RecursiveBadgeCount AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        B.Name AS BadgeName,
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Date DESC) AS BadgeRank
    FROM
        Users U
    LEFT JOIN
        Badges B ON U.Id = B.UserId
),
UserReputationCTE AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    WHERE
        U.Reputation > 1000
    GROUP BY
        U.Id
),
TopQuestionsCTE AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.Score,
        RANK() OVER (ORDER BY P.Score DESC) AS ScoreRank,
        P.CreationDate
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1
        AND P.Score > 10
),
CommentLengthCTE AS (
    SELECT
        C.PostId,
        AVG(LENGTH(C.Text)) AS AvgCommentLength
    FROM
        Comments C
    GROUP BY
        C.PostId
)

SELECT
    U.DisplayName,
    UR.Reputation,
    UR.UpVotesReceived,
    UR.DownVotesReceived,
    TQ.Title AS TopQuestionTitle,
    TQ.Score AS TopQuestionScore,
    CL.AvgCommentLength,
    CASE 
        WHEN RB.BadgeRank = 1 THEN RB.BadgeName
        ELSE 'No Recent Badges'
    END AS RecentBadge
FROM
    Users U
LEFT JOIN 
    UserReputationCTE UR ON U.Id = UR.UserId
LEFT JOIN 
    TopQuestionsCTE TQ ON U.Id = (SELECT OwnerUserId FROM Posts WHERE Id = TQ.PostId LIMIT 1)
LEFT JOIN 
    CommentLengthCTE CL ON TQ.PostId = CL.PostId
LEFT JOIN 
    RecursiveBadgeCount RB ON U.Id = RB.UserId
WHERE
    (UR.UpVotesReceived > UR.DownVotesReceived OR UR.DownVotesReceived IS NULL)
    AND (TQ.ScoreRank IS NOT NULL OR CL.AvgCommentLength > 100)
ORDER BY
    UR.Reputation DESC,
    TQ.ScoreRank;
