-- {"query": "12076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 1043} 
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year'
),
TopUsers AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS PostCount,
        SUM(Score) AS TotalScore,
        MAX(ViewCount) AS MaxViewCount
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1 AND SUM(Score) > 100
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore,
        MAX(P.ViewCount) AS MaxViewCount
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) AS HistoryCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS CloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS ReopenDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
UserBadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
UserActivity AS (
    SELECT 
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        U.LastAccessDate,
        U.Location,
        U.AboutMe,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        UBC.GoldBadges,
        UBC.SilverBadges,
        UBC.BronzeBadges,
        RP.UserPostRank,
        PHS.HistoryCount,
        PHS.LastEditDate,
        PHS.CloseDate,
        PHS.ReopenDate
    FROM 
        Users U
    LEFT JOIN 
        UserBadgeCounts UBC ON U.Id = UBC.UserId
    LEFT JOIN 
        RankedPosts RP ON U.Id = RP.OwnerUserId
    LEFT JOIN 
        PostHistorySummary PHS ON U.Id = PHS.PostId
    WHERE 
        U.Reputation > 1000
),
FinalResults AS (
    SELECT 
        UA.Id AS UserId,
        UA.DisplayName,
        UA.Reputation,
        UA.CreationDate,
        UA.LastAccessDate,
        UA.Location,
        UA.AboutMe,
        UA.Views,
        UA.UpVotes,
        UA.DownVotes,
        UA.GoldBadges,
        UA.SilverBadges,
        UA.BronzeBadges,
        TU.PostCount,
        TU.TotalScore,
        TU.MaxViewCount,
        TS.TagName,
        TS.PostCount AS TagPostCount,
        TS.AvgScore AS TagAvgScore,
        TS.MaxViewCount AS TagMaxViewCount,
        PHS.HistoryCount,
        PHS.LastEditDate,
        PHS.CloseDate,
        PHS.ReopenDate
    FROM 
        UserActivity UA
    JOIN 
        TopUsers TU ON UA.Id = TU.OwnerUserId
    LEFT JOIN 
        TagStats TS ON UA.Id = TS.PostCount
    LEFT JOIN 
        PostHistorySummary PHS ON UA.Id = PHS.PostId
)
SELECT 
    *
FROM 
    FinalResults
ORDER BY 
    Reputation DESC, 
    TotalScore DESC, 
    TagPostCount DESC
LIMIT 100;