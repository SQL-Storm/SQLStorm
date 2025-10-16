WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC) AS ScoreRank,
        NTILE(4) OVER (ORDER BY P.ViewCount DESC) AS ViewQuartile,
        P.Tags
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND 
        P.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
), 
AggregatedUserStats AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersGiven,
        SUM(P.Score) AS TotalScore,
        AVG(P.ViewCount) AS AvgViewCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY 
        U.Id, U.DisplayName
), 
TopTags AS (
    SELECT 
        TRIM(x) AS Tag,
        COUNT(P.Id) AS TagCount
    FROM 
        Posts P,
        UNNEST(string_to_array(P.Tags, '<')) AS t(x)
    WHERE 
        P.PostTypeId = 1 AND 
        P.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY 
        TRIM(x)
    ORDER BY 
        TagCount DESC
    LIMIT 10
), 
UserBadges AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM 
        Badges B
    WHERE 
        B.Date >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY 
        B.UserId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    AUS.QuestionsAsked,
    AUS.AnswersGiven,
    AUS.TotalScore,
    AUS.AvgViewCount,
    COALESCE(UB.GoldBadges, 0) AS GoldBadges,
    COALESCE(UB.SilverBadges, 0) AS SilverBadges,
    COALESCE(UB.BronzeBadges, 0) AS BronzeBadges,
    TT.Tag,
    TT.TagCount,
    RP.UserPostRank,
    RP.ScoreRank,
    RP.ViewQuartile
FROM 
    RankedPosts RP
JOIN 
    AggregatedUserStats AUS ON RP.OwnerUserId = AUS.Id
LEFT JOIN 
    UserBadges UB ON RP.OwnerUserId = UB.UserId
LEFT JOIN 
    TopTags TT ON RP.Tags LIKE '%' || TT.Tag || '%'
WHERE 
    RP.UserPostRank <= 3
GROUP BY
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    AUS.QuestionsAsked,
    AUS.AnswersGiven,
    AUS.TotalScore,
    AUS.AvgViewCount,
    UB.GoldBadges,
    UB.SilverBadges,
    UB.BronzeBadges,
    TT.Tag,
    TT.TagCount,
    RP.UserPostRank,
    RP.ScoreRank,
    RP.ViewQuartile,
    RP.Tags
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;