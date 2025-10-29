WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS total_badges,
        SUM(B.Class) AS badge_points
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
VotesSummary AS (
    SELECT
        V.PostId,
        COUNT(*) AS total_votes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS total_upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS total_downvotes
    FROM
        Votes V
    GROUP BY
        V.PostId
),
LatestRevision AS (
    SELECT
        PH.PostId,
        MAX(PH.RevisionGUID) AS latest_revision_guid
    FROM
        PostHistory PH
    WHERE
        PH.PostHistoryTypeId = 2
    GROUP BY
        PH.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    B.total_badges,
    B.badge_points,
    COALESCE(VS.total_votes, 0) AS total_votes,
    COALESCE(VS.total_upvotes, 0) AS total_upvotes,
    COALESCE(VS.total_downvotes, 0) AS total_downvotes,
    COALESCE(LR.latest_revision_guid, 'No Revisions') AS latest_revision
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    VotesSummary VS ON RP.Id = VS.PostId
LEFT JOIN 
    LatestRevision LR ON RP.Id = LR.PostId
WHERE 
    RP.rank <= 10
    AND (RP.Score > 100 OR RP.ViewCount > 100)
ORDER BY 
    total_upvotes DESC, 
    total_votes DESC;