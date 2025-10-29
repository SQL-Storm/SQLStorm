WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.LastActivityDate DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
        AND P.Score > 0
        AND P.ViewCount > 100
), FilteredBadges AS (
    SELECT 
        B.UserId,
        B.Name,
        B.Date,
        CASE 
            WHEN B.Class = 1 THEN 'Gold'
            WHEN B.Class = 2 THEN 'Silver'
            ELSE 'Bronze'
        END AS BadgeClass
    FROM 
        Badges B
    WHERE 
        B.TagBased = FALSE
        AND B.Date >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
), MergedData AS (
    SELECT 
        RP.Id AS PostId,
        RP.Title,
        RP.Score,
        RP.ViewCount,
        RP.CreationDate,
        RP.LastActivityDate,
        RP.Rank,
        RP.DisplayName,
        RP.Reputation,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT LB.Id) AS LinkedPosts,
        COUNT(DISTINCT FB.UserId) AS BadgesCount,
        FB.BadgeClass,
        STRING_AGG(DISTINCT T.TagName, ', ' ORDER BY T.TagName) AS TagList
    FROM 
        RankedPosts RP
    LEFT JOIN 
        Votes V ON RP.Id = V.PostId
    LEFT JOIN 
        PostLinks LB ON RP.Id = LB.PostId
    LEFT JOIN 
        Tags T ON RP.Id = T.ExcerptPostId
    LEFT JOIN 
        FilteredBadges FB ON RP.DisplayName = CAST(FB.UserId AS VARCHAR)
    GROUP BY 
        RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, RP.DisplayName, RP.Reputation, FB.BadgeClass
)
SELECT 
    MD.PostId,
    MD.Title,
    MD.Score,
    MD.ViewCount,
    MD.CreationDate,
    MD.LastActivityDate,
    MD.Rank,
    MD.DisplayName,
    MD.Reputation,
    MD.TotalVotes,
    MD.UpVotes,
    MD.DownVotes,
    MD.LinkedPosts,
    MD.BadgesCount,
    MD.BadgeClass,
    MD.TagList,
    CASE 
        WHEN MD.Score > 100 THEN 'High'
        WHEN MD.ViewCount > 1000 THEN 'Popular'
        ELSE 'Normal'
    END AS PostStatus
FROM 
    MergedData MD
ORDER BY 
    MD.Rank ASC, MD.Score DESC;