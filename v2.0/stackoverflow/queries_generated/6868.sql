-- {"query": "6868.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 937} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS Owner,
        U.Reputation,
        U.Location,
        U.AboutMe,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.UserId ELSE NULL END) AS UpVotesCount,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.UserId ELSE NULL END) AS DownVotesCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId ELSE NULL END) AS DuplicateCount,
        COUNT(DISTINCT CASE WHEN B.Id IS NOT NULL THEN B.Id ELSE NULL END) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN 
        Badges B ON P.OwnerUserId = B.UserId
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 0
    GROUP BY 
        P.Id, P.Title, P.Score, P.ViewCount, P.CreationDate, P.LastActivityDate, U.DisplayName, U.Reputation, U.Location, U.AboutMe, U.Views, U.UpVotes, U.DownVotes
),
RecentActivity AS (
    SELECT 
        P.Id,
        P.Title,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN PH.CreationDate ELSE NULL END) AS LastDeletedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 13 THEN PH.CreationDate ELSE NULL END) AS LastUndeletedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 14 THEN PH.CreationDate ELSE NULL END) AS LastLockedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 15 THEN PH.CreationDate ELSE NULL END) AS LastUnlockedDate,
        MAX(PH.CreationDate) AS LastActivity
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        P.Id, P.Title
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Owner,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    RP.Views,
    RP.UpVotes,
    RP.DownVotes,
    RP.TotalVotes,
    RP.UpVotesCount,
    RP.DownVotesCount,
    RP.DuplicateCount,
    RP.BadgeCount,
    RP.Rank,
    ISNULL(RA.LastClosedDate, 'Never') AS LastClosedDate,
    ISNULL(RA.LastReopenedDate, 'Never') AS LastReopenedDate,
    ISNULL(RA.LastDeletedDate, 'Never') AS LastDeletedDate,
    ISNULL(RA.LastUndeletedDate, 'Never') AS LastUndeletedDate,
    ISNULL(RA.LastLockedDate, 'Never') AS LastLockedDate,
    ISNULL(RA.LastUnlockedDate, 'Never') AS LastUnlockedDate,
    RA.LastActivity
FROM 
    RankedPosts RP
LEFT JOIN 
    RecentActivity RA ON RP.Id = RA.Id
ORDER BY 
    RP.Rank;
