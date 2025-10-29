-- {"query": "6740.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 715} 
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        P.OwnerUserId,
        U.Reputation,
        U.LastAccessDate,
        U.Location,
        U.AboutMe,
        U.WebsiteUrl,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = P.PostTypeId AND Score > P.Score) AS ScoreRank
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId IN (1, 2) AND P.Score > 100
),
BadgeSummary AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS BadgeCount,
        SUM(Case When Class = 1 Then 1 Else 0 End) AS GoldBadgeCount,
        SUM(Case When Class = 2 Then 1 Else 0 End) AS SilverBadgeCount,
        SUM(Case When Class = 3 Then 1 Else 0 End) AS BronzeBadgeCount
    FROM Badges
    GROUP BY UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.OwnerUserId,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    RP.WebsiteUrl,
    RP.Rank,
    RP.ScoreRank,
    B.BadgeCount,
    B.GoldBadgeCount,
    B.SilverBadgeCount,
    B.BronzeBadgeCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId IN (2, 15) THEN V.UserId END) AS PositiveVotes,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId IN (3, 15) THEN V.UserId END) AS NegativeVotes,
    COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateCount,
    MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS CloseReason,
    MAX(CASE WHEN PH.PostHistoryTypeId = 8 THEN PH.Comment END) AS ReopenReason
FROM RankedPosts RP
LEFT JOIN BadgeSummary B ON RP.OwnerUserId = B.UserId
LEFT JOIN Votes V ON RP.Id = V.PostId
LEFT JOIN PostLinks PL ON RP.Id = PL.PostId
LEFT JOIN PostHistory PH ON RP.Id = PH.PostId
GROUP BY 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.OwnerUserId,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    RP.WebsiteUrl,
    RP.Rank,
    RP.ScoreRank,
    B.BadgeCount,
    B.GoldBadgeCount,
    B.SilverBadgeCount,
    B.BronzeBadgeCount
ORDER BY RP.Rank;