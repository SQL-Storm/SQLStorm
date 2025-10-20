WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
TopUsers AS (
    SELECT 
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName
    HAVING 
        COUNT(DISTINCT B.Id) > 0
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT PH.Id) AS TotalPostHistory
    FROM 
        Users U
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    LEFT JOIN 
        PostHistory PH ON U.Id = PH.UserId
    GROUP BY 
        U.Id,
        U.DisplayName
),
PostTags AS (
    -- portable tag splitting using a recursive CTE for portability
    SELECT P.Id, TRIM(BOTH '<>' FROM tag) AS TagName
    FROM Posts P
    CROSS JOIN (
        SELECT 
            CASE
                WHEN P.Tags IS NULL THEN ''
                WHEN SUBSTR(P.Tags,1,1) = '<' AND SUBSTR(P.Tags, -1, 1) = '>' THEN REPLACE(SUBSTR(P.Tags, 2, LENGTH(P.Tags) - 2), '><', '|')
                ELSE REPLACE(P.Tags, '><', '|')
            END AS tags_norm
    ) norm
    JOIN (
        -- recursive split of tags_norm by '|' into rows
        WITH RECURSIVE split(tag, rest) AS (
            SELECT 
                CASE WHEN INSTR(norm.tags_norm, '|') = 0 THEN norm.tags_norm ELSE SUBSTR(norm.tags_norm, 1, INSTR(norm.tags_norm, '|')-1) END,
                CASE WHEN INSTR(norm.tags_norm, '|') = 0 THEN NULL ELSE SUBSTR(norm.tags_norm, INSTR(norm.tags_norm, '|')+1) END
            FROM (SELECT norm.tags_norm) x
            WHERE norm.tags_norm IS NOT NULL AND norm.tags_norm <> ''
            UNION ALL
            SELECT
                CASE WHEN INSTR(rest, '|') = 0 THEN rest ELSE SUBSTR(rest, 1, INSTR(rest, '|')-1) END,
                CASE WHEN INSTR(rest, '|') = 0 THEN NULL ELSE SUBSTR(rest, INSTR(rest, '|')+1) END
            FROM split
            WHERE rest IS NOT NULL AND rest <> ''
        )
        SELECT tag FROM split
    ) s ON 1=1
    WHERE P.PostTypeId = 1
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS QuestionCount,
        AVG(P.Score) AS AvgScore,
        SUM(P.ViewCount) AS TotalViews
    FROM 
        Tags T
    JOIN 
        PostTags PT ON T.TagName = PT.TagName
    JOIN 
        Posts P ON PT.Id = P.Id
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
)
SELECT 
    TU.Id,
    TU.DisplayName,
    TU.Reputation,
    TU.TotalBadges,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    UA.TotalComments,
    UA.TotalVotes,
    UA.TotalPostHistory,
    TS.TagName,
    TS.QuestionCount,
    TS.AvgScore,
    TS.TotalViews,
    RP.Id AS TopPostId,
    RP.Score AS TopPostScore,
    RP.ViewCount AS TopPostViews,
    RP.LastActivityDate AS TopPostLastActivity
FROM 
    TopUsers TU
JOIN 
    UserActivity UA ON TU.Id = UA.Id
JOIN 
    RankedPosts RP ON TU.Id = RP.OwnerUserId AND RP.UserPostRank = 1
JOIN 
    PostTags PT ON RP.Id = PT.Id
JOIN 
    TagStats TS ON PT.TagName = TS.TagName
ORDER BY 
    TU.Reputation DESC, 
    RP.Score DESC, 
    TS.TotalViews DESC;