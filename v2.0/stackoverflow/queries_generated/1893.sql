-- {"query": "1893.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2017} 

WITH UserPostSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END), 0) AS TotalAnswerScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalViewsOnPosts,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(P.AnswerCount), 0) AS TotalAnswersReceivedOnQuestions,
        MAX(P.LastActivityDate) AS LastPostActivity
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
TargetTagEngagement AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS PostsInTargetTags,
        COALESCE(SUM(P.Score), 0) AS ScoreInTargetTags,
        COALESCE(SUM(P.ViewCount), 0) AS ViewsInTargetTags,
        MAX(CASE WHEN P.PostTypeId = 1 THEN P.FavoriteCount ELSE 0 END) AS MaxFavCountInTargetTagsQ
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
      AND (
            LOWER(P.Tags) LIKE '%<performance>%' OR
            LOWER(P.Tags) LIKE '%<optimization>%' OR
            LOWER(P.Tags) LIKE '%<speed>%' OR
            LOWER(P.Tags) LIKE '%<benchmarking>%'
          )
    GROUP BY P.OwnerUserId
),
UserEditHistory AS (
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.Id) AS EditsCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) AND PH.UserId = PO.OwnerUserId THEN PH.Id ELSE NULL END) AS SelfEditsOnOwnPosts
    FROM PostHistory AS PH
    JOIN Posts AS PO ON PH.PostId = PO.Id
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserBadgesRanked AS (
    SELECT
        B.UserId,
        B.Name AS BadgeName,
        B.Class AS BadgeClass,
        B.Date AS BadgeDate,
        ROW_NUMBER() OVER(PARTITION BY B.UserId ORDER BY B.Date DESC, B.Class ASC) AS rn
    FROM Badges AS B
    WHERE B.Class IN (1,2,3)
),
MostValuablePostPerUser AS (
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS MostValuablePostId,
        P.Title AS MostValuablePostTitle,
        P.Score AS MostValuablePostScore,
        P.ViewCount AS MostValuablePostViews,
        P.AnswerCount AS MostValuablePostAnswerCount,
        P.CreationDate AS MostValuablePostDate,
        ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate DESC) AS rn
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId = 1
      AND (
            LOWER(P.Tags) LIKE '%<performance>%' OR
            LOWER(P.Tags) LIKE '%<optimization>%'
          )
)
SELECT
    U.Id AS UserID,
    U.DisplayName,
    U.Reputation,
    U.UpVotes AS UserUpVotesGiven,
    U.DownVotes AS UserDownVotesGiven,
    UPS.TotalPosts,
    UPS.TotalQuestions,
    UPS.TotalAnswers,
    UPS.TotalPostScore,
    UPS.TotalAnswerScore,
    UPS.TotalViewsOnPosts,
    TTE.PostsInTargetTags,
    TTE.ScoreInTargetTags,
    TTE.ViewsInTargetTags,
    COALESCE(UHE.SelfEditsOnOwnPosts, 0) AS SelfEditsCount,
    UBR.BadgeName AS RecentBadgeName,
    CASE
        WHEN UBR.BadgeClass = 1 THEN 'Gold Tier'
        WHEN UBR.BadgeClass = 2 THEN 'Silver Tier'
        WHEN UBR.BadgeClass = 3 THEN 'Bronze Tier'
        ELSE 'No Recent Badge'
    END AS RecentBadgeCategory,
    MVP.MostValuablePostTitle,
    MVP.MostValuablePostScore,
    MVP.MostValuablePostViews,
    COALESCE(MVP.MostValuablePostAnswerCount, 0) AS MostValuablePostAnswerCount,
    (CAST(UPS.TotalAnswerScore AS NUMERIC) / NULLIF(UPS.TotalAnswers, 0)) AS AvgAnswerScore,
    -- Correlated Subquery: Find the highest scoring comment on any of user's posts
    (SELECT MAX(C.Score) FROM Comments AS C WHERE C.PostId IN (SELECT P_INNER.Id FROM Posts AS P_INNER WHERE P_INNER.OwnerUserId = U.Id)) AS MaxCommentScoreOnOwnPosts,
    -- Another correlated subquery: Check if user has any posts closed as a duplicate
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostHistory PH_DUP
            WHERE PH_DUP.PostId IN (SELECT P_INNER.Id FROM Posts AS P_INNER WHERE P_INNER.OwnerUserId = U.Id)
              AND PH_DUP.PostHistoryTypeId = 10 -- Post Closed
              AND PH_DUP.Comment IN ('1', '101') -- CloseReasonId for Exact Duplicate/Duplicate
        ) THEN 'Has Duplicates Closed'
        ELSE 'No Duplicates Closed'
    END AS DuplicateClosureStatus,
    -- Window Function: Rank users by their total contribution (Reputation + Target Tag Score)
    RANK() OVER (ORDER BY U.Reputation DESC, TTE.ScoreInTargetTags DESC, UPS.TotalPostScore DESC) AS OverallContributionRank,
    -- Window Function: Calculate average reputation of users who joined in the same year
    AVG(U.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate)) AS AvgReputationInJoinYear,
    -- String manipulation and NULL logic
    COALESCE(SUBSTRING(U.AboutMe FROM 1 FOR 50), 'No "About Me" provided') AS AboutMeExcerpt,
    CASE
        WHEN U.WebsiteUrl IS NOT NULL AND LENGTH(U.WebsiteUrl) > 10 THEN 'Has Website'
        WHEN U.Location IS NOT NULL AND LENGTH(U.Location) > 5 THEN 'Has Location'
        ELSE 'Minimal Profile Info'
    END AS ProfileRichness,
    -- Date difference
    EXTRACT(DAY FROM (U.LastAccessDate - U.CreationDate)) AS DaysActiveSinceCreation
FROM Users AS U
LEFT JOIN UserPostSummary AS UPS ON U.Id = UPS.UserId
LEFT JOIN TargetTagEngagement AS TTE ON U.Id = TTE.UserId
LEFT JOIN UserEditHistory AS UHE ON U.Id = UHE.UserId
LEFT JOIN UserBadgesRanked AS UBR ON U.Id = UBR.UserId AND UBR.rn = 1
LEFT JOIN MostValuablePostPerUser AS MVP ON U.Id = MVP.UserId AND MVP.rn = 1
WHERE
    U.Reputation > 5000
    AND UPS.TotalAnswers > 0
    AND COALESCE(TTE.PostsInTargetTags, 0) > 0
    AND EXTRACT(DAY FROM (CURRENT_TIMESTAMP - U.LastAccessDate)) < 365 * 2
    -- Correlated Subquery for filtering users with too many deleted posts
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory AS PH_DEL
        JOIN Posts AS P_INNER ON PH_DEL.PostId = P_INNER.Id
        WHERE P_INNER.OwnerUserId = U.Id
          AND PH_DEL.PostHistoryTypeId = 12
        HAVING COUNT(DISTINCT PH_DEL.PostId) > 5
    )
ORDER BY OverallContributionRank ASC, U.Reputation DESC
LIMIT 500;
