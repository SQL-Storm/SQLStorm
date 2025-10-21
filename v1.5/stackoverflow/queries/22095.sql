WITH QuestionTags AS (
    SELECT 
        P.Id AS PostId,
        P.OwnerUserId AS UserId,
        TRIM(CAST(tag AS VARCHAR)) AS Tag
    FROM Posts P
    CROSS JOIN LATERAL UNNEST(string_to_array(replace(replace(P.Tags, '<', ''), '>', ''), ' ')) AS tag
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(TRIM(P.Tags)) > 0
),
UserBadgeSummary AS (
    SELECT 
        B.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(DISTINCT B.Name, ', ') AS BadgeNames
    FROM Badges B
    GROUP BY B.UserId
),
UserPostStats AS (
    SELECT 
        U.Id AS UserId,
        COUNT(P.Id) AS TotalPosts,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN 1 END) AS Questions,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN 1 END) AS Answers,
        SUM(COALESCE(P.Score, 0)) AS TotalScore,
        AVG(COALESCE(P.Score, 0)) AS AvgScore,
        MAX(P.Score) AS MaxScore,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT C.Id) AS CommentsReceived
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY U.Id
),
RankedUsers AS (
    SELECT 
        UPS.UserId,
        UPS.TotalPosts,
        UPS.Questions,
        UPS.Answers,
        UPS.TotalScore,
        UPS.AvgScore,
        UPS.MaxScore,
        UPS.UpVotesReceived,
        UPS.DownVotesReceived,
        UPS.CommentsReceived,
        UBS.TotalBadges,
        UBS.GoldBadges,
        UBS.SilverBadges,
        UBS.BronzeBadges,
        UBS.BadgeNames,
        ROW_NUMBER() OVER (ORDER BY UPS.TotalScore DESC, UBS.GoldBadges DESC, UBS.SilverBadges DESC) AS OverallRank,
        ROW_NUMBER() OVER (PARTITION BY CASE WHEN UPS.Questions > 0 THEN 1 ELSE 0 END ORDER BY UPS.AvgScore DESC) AS QuestionRank,
        DENSE_RANK() OVER (ORDER BY UPS.UpVotesReceived - UPS.DownVotesReceived DESC) AS VoteDifferentialRank
    FROM UserPostStats UPS
    LEFT JOIN UserBadgeSummary UBS ON UPS.UserId = UBS.UserId
    WHERE UPS.TotalPosts > 0
),
TopTaggedPosts AS (
    SELECT 
        QT.UserId,
        QT.Tag,
        COUNT(*) AS TagPosts,
        DENSE_RANK() OVER (PARTITION BY QT.UserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM QuestionTags QT
    GROUP BY QT.UserId, QT.Tag
)
SELECT 
    RU.UserId,
    RU.TotalPosts,
    RU.Questions,
    RU.Answers,
    RU.TotalScore,
    ROUND(RU.AvgScore, 2) AS AvgScore,
    RU.MaxScore,
    RU.UpVotesReceived,
    RU.DownVotesReceived,
    RU.CommentsReceived,
    RU.TotalBadges,
    RU.GoldBadges,
    RU.SilverBadges,
    RU.BronzeBadges,
    RU.BadgeNames,
    RU.OverallRank,
    RU.QuestionRank,
    RU.VoteDifferentialRank,
    (SELECT STRING_AGG(CONCAT(TTP.Tag, ' (', TTP.TagPosts, ')'), '; ') 
     FROM TopTaggedPosts TTP 
     WHERE TTP.UserId = RU.UserId AND TTP.TagRank <= 3) AS TopTags,
    CASE 
        WHEN RU.GoldBadges > 5 THEN 'Elite'
        WHEN RU.SilverBadges > 10 THEN 'Advanced'
        WHEN RU.BronzeBadges > 20 THEN 'Beginner'
        ELSE 'Novice'
    END AS UserCategory
FROM RankedUsers RU
WHERE RU.OverallRank <= 1000 AND RU.TotalScore > 0
ORDER BY RU.OverallRank;