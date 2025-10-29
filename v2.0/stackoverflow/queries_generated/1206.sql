-- {"query": "1206.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2300} 
WITH UserPostStats AS (
    SELECT
        U.Id AS UserId,
        COUNT(P.Id) AS TotalPosts,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(CAST(P.Score AS NUMERIC)), 0.0) AS AvgPostScore,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END), 0) AS TotalQuestionViewCount,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS QuestionsWithAcceptedAnswer,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND Q.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END), 0) AS AcceptedAnswersGiven
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts AS Q ON P.PostTypeId = 2 AND P.ParentId = Q.Id -- Q is the question for an answer P
    GROUP BY U.Id
),
UserCommentActivity AS (
    SELECT
        U.Id AS UserId,
        COUNT(C.Id) AS TotalComments,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COALESCE(SUM(CASE WHEN C.PostId IN (SELECT P.Id FROM Posts P WHERE P.OwnerUserId = U.Id) THEN 1 ELSE 0 END), 0) AS CommentsOnOwnPosts
    FROM Users AS U
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id
),
UserBadgeSummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END), 0) AS TagBasedBadges,
        COALESCE(SUM(CASE WHEN B.TagBased = FALSE THEN 1 ELSE 0 END), 0) AS NamedBadges
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id
),
TagExpertise AS (
    WITH UserTagAgg AS (
        SELECT
            P.OwnerUserId AS UserId,
            TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
            SUM(P.Score) AS TagCombinedScore
        FROM Posts AS P
        WHERE P.OwnerUserId IS NOT NULL
          AND P.Tags IS NOT NULL
          AND LENGTH(P.Tags) > 2 -- Ensure tags string is not just '<>'
          AND P.PostTypeId IN (1, 2)
        GROUP BY P.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')))
    )
    SELECT
        UserId,
        STRING_AGG(TagName || ' (' || TagCombinedScore || ')', '; ') AS TopTagsWithScore,
        SUM(TagCombinedScore) AS OverallTopTagScore
    FROM (
        SELECT
            UserId,
            TagName,
            TagCombinedScore,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCombinedScore DESC, TagName ASC) AS TagRank
        FROM UserTagAgg
    ) AS RankedUserTags
    WHERE TagRank <= 3 -- Top 3 tags for each user
    GROUP BY UserId
)
SELECT
    U.Id AS UserIdentifier,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    UPS.TotalPosts,
    UPS.TotalPostScore,
    UCA.TotalComments,
    UBS.GoldBadges,
    TE.TopTagsWithScore,
    COALESCE(U.Views, 0) AS UserProfileViews,
    COALESCE(U.UpVotes, 0) AS UserUpVotesGiven,
    COALESCE(U.DownVotes, 0) AS UserDownVotesGiven,
    FLOOR(EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (3600 * 24 * 365.25)) AS YearsOnPlatform,
    CASE
        WHEN U.Reputation >= 100000 THEN 'Legend'
        WHEN U.Reputation >= 25000 THEN 'Guru'
        WHEN U.Reputation >= 5000 THEN 'Expert'
        WHEN U.Reputation >= 1000 THEN 'Journeyman'
        ELSE 'Novice'
    END AS ReputationTier,
    (COALESCE(UPS.TotalPostScore, 0) * 0.5
     + COALESCE(UPS.AcceptedAnswersGiven, 0) * 10
     + COALESCE(UCA.TotalCommentScore, 0) * 0.1
     + COALESCE(UBS.GoldBadges, 0) * 50
     + COALESCE(UBS.SilverBadges, 0) * 10
     + COALESCE(UBS.BronzeBadges, 0) * 1) AS InfluenceScore,
    RANK() OVER (ORDER BY (COALESCE(UPS.TotalPostScore, 0) * 0.5 + COALESCE(UPS.AcceptedAnswersGiven, 0) * 10 + COALESCE(UCA.TotalCommentScore, 0) * 0.1 + COALESCE(UBS.GoldBadges, 0) * 50 + COALESCE(UBS.SilverBadges, 0) * 10 + COALESCE(UBS.BronzeBadges, 0) * 1) DESC) AS OverallInfluenceRank,
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile,
    (
        SELECT COUNT(DISTINCT PH.PostId)
        FROM PostHistory AS PH
        WHERE PH.UserId = U.Id
          AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
          AND PH.CreationDate > (NOW() - INTERVAL '6 months')
          AND EXISTS (
                SELECT 1
                FROM Posts AS P_sub
                WHERE P_sub.Id = PH.PostId
                  AND P_sub.PostTypeId = 1
                  AND P_sub.ViewCount > 1000
                  AND P_sub.OwnerUserId = U.Id
          )
    ) AS RecentHighViewPostEdits,
    CASE
        WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 100 AND U.AboutMe ILIKE '%SQL%' THEN 'Verbose SQL Enthusiast'
        WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 50 THEN 'Verbose User'
        WHEN U.AboutMe IS NOT NULL AND U.AboutMe ILIKE '%developer%' THEN 'Developer Mentioned'
        ELSE 'No AboutMe / Short'
    END AS AboutMeCategory,
    COALESCE(U.Location, 'Unknown Location') AS UserLocation,
    NULLIF(U.WebsiteUrl, '') AS UserWebsite,
    CASE
        WHEN (U.Reputation > 5000
              AND COALESCE(UPS.TotalPostScore, 0) > 1000
              AND COALESCE(UPS.AcceptedAnswersGiven, 0) > 5
              AND COALESCE(UCA.TotalComments, 0) > 50
              AND (COALESCE(UBS.GoldBadges, 0) > 0 OR COALESCE(UBS.SilverBadges, 0) > 2)) THEN 'Highly Engaged Influencer'
        WHEN (U.Reputation > 1000
              AND COALESCE(UPS.TotalPosts, 0) > 100
              AND COALESCE(UPS.AvgPostScore, 0.0) > 5
              AND U.LastAccessDate > (NOW() - INTERVAL '1 month')) THEN 'Active Contributor'
        ELSE 'General User'
    END AS UserEngagementProfile
FROM Users AS U
LEFT JOIN UserPostStats AS UPS ON U.Id = UPS.UserId
LEFT JOIN UserCommentActivity AS UCA ON U.Id = UCA.UserId
LEFT JOIN UserBadgeSummary AS UBS ON U.Id = UBS.UserId
LEFT JOIN TagExpertise AS TE ON U.Id = TE.UserId
WHERE U.Id IN (
    SELECT SubU.Id FROM Users SubU
    INNER JOIN UserPostStats SubUPS ON SubU.Id = SubUPS.UserId
    WHERE SubU.Reputation >= 10000 AND COALESCE(SubUPS.TotalPostScore, 0) >= 5000
    UNION ALL
    SELECT SubU.Id FROM Users SubU
    INNER JOIN UserCommentActivity SubUCA ON SubU.Id = SubUCA.UserId
    WHERE SubU.LastAccessDate >= (NOW() - INTERVAL '3 months') AND COALESCE(SubUCA.TotalComments, 0) >= 200
    UNION ALL
    SELECT SubU.Id FROM Users SubU
    INNER JOIN UserBadgeSummary SubUBS ON SubU.Id = SubUBS.UserId
    WHERE COALESCE(SubUBS.GoldBadges, 0) >= 3
)
AND U.CreationDate <= (NOW() - INTERVAL '1 year')
AND U.DisplayName IS NOT NULL
ORDER BY OverallInfluenceRank ASC, U.Reputation DESC, U.LastAccessDate DESC;