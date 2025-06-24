
WITH UserVoteSummary AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users U
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        TotalVotes,
        UpVotes,
        DownVotes,
        @userRank := @userRank + 1 AS UserRank
    FROM 
        UserVoteSummary, (SELECT @userRank := 0) AS r 
    ORDER BY 
        TotalVotes DESC
),
PostSummary AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.OwnerUserId,
        COUNT(C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    GROUP BY 
        P.Id, P.Title, P.CreationDate, P.OwnerUserId
),
ResultSet AS (
    SELECT 
        Pu.DisplayName AS UserDisplayName,
        Pu.TotalVotes AS UserTotalVotes,
        Ps.Title AS PostTitle,
        Ps.CommentCount,
        Ps.TotalUpVotes,
        Ps.TotalDownVotes,
        Ps.HasAcceptedAnswer,
        @postRank := IF(@prevUserId = Pu.UserId, @postRank + 1, 1) AS PostRank,
        @prevUserId := Pu.UserId
    FROM 
        TopUsers Pu
    JOIN 
        PostSummary Ps ON Pu.UserId = Ps.OwnerUserId, (SELECT @postRank := 0, @prevUserId := NULL) AS r
)
SELECT 
    *
FROM 
    ResultSet
WHERE 
    PostRank = 1
ORDER BY 
    UserTotalVotes DESC, UserDisplayName;
