-- {"query": "42047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 807} 
WITH RECURSIVE UserPostCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC) AS Rank
    FROM 
        Users U
    JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        U.Id, U.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalScore
    FROM 
        UserPostCounts
    WHERE 
        Rank <= 100
),
UserBadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.Id IN (SELECT UserId FROM TopUsers)
    GROUP BY 
        U.Id
),
PostTagCounts AS (
    SELECT 
        P.Id AS PostId,
        COUNT(DISTINCT T.TagName) AS TagCount
    FROM 
        Posts P
    JOIN 
        Tags T ON P.Tags LIKE '%' || T.TagName || '%'
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id
),
PostHistoryCounts AS (
    SELECT 
        P.Id AS PostId,
        COUNT(PH.Id) AS HistoryCount
    FROM 
        Posts P
    JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id
),
PostVoteCounts AS (
    SELECT 
        P.Id AS PostId,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.Id END) AS DownVotes
    FROM 
        Posts P
    JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id
)
SELECT 
    TU.UserId,
    TU.DisplayName,
    TU.TotalPosts,
    TU.TotalQuestions,
    TU.TotalAnswers,
    TU.TotalScore,
    UBC.GoldBadges,
    UBC.SilverBadges,
    UBC.BronzeBadges,
    PTC.TagCount,
    PHC.HistoryCount,
    PVC.UpVotes,
    PVC.DownVotes
FROM 
    TopUsers TU
JOIN 
    UserBadgeCounts UBC ON TU.UserId = UBC.UserId
JOIN 
    PostTagCounts PTC ON TU.UserId = PTC.PostId
JOIN 
    PostHistoryCounts PHC ON TU.UserId = PHC.PostId
JOIN 
    PostVoteCounts PVC ON TU.UserId = PVC.PostId
ORDER BY 
    TU.TotalScore DESC;