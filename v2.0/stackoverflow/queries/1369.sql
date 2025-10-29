-- {"query": "1369.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3079}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.Views
),
PostDetailsRaw AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Body,
        P.Tags,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        -- convert tag string like '<tag1><tag2>' into array; use standard functions where available
        CASE
            WHEN P.Tags IS NULL THEN NULL
            ELSE regexp_split_to_array(substring(P.Tags FROM 2 FOR char_length(P.Tags) - 2), '><')
        END AS ParsedTags
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
),
UserBadgesSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges,
        MIN(B.Date) AS FirstBadgeDate,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
UserTagImpact AS (
    SELECT
        pdr.OwnerUserId AS UserId,
        t.tag AS TagName,
        COUNT(DISTINCT pdr.PostId) AS PostsInTag,
        SUM(pdr.Score) AS TotalScoreInTag,
        AVG(CAST(pdr.Score AS NUMERIC)) AS AvgScoreInTag,
        MIN(pdr.PostCreationDate) AS FirstPostInTag,
        MAX(pdr.PostCreationDate) AS LastPostInTag
    FROM PostDetailsRaw pdr,
         LATERAL (
             SELECT unnest(pdr.ParsedTags) AS tag
         ) t
    WHERE pdr.ParsedTags IS NOT NULL
      AND t.tag IN ('sql', 'database', 'performance', 'indexing', 'query-optimization')
    GROUP BY pdr.OwnerUserId, t.tag
),
AggregatedUserTagImpact AS (
    SELECT
        UserId,
        MAX(CASE WHEN TagName = 'sql' THEN PostsInTag ELSE 0 END) AS SqlPostsCount,
        MAX(CASE WHEN TagName = 'sql' THEN TotalScoreInTag ELSE 0 END) AS SqlTotalScore,
        MAX(CASE WHEN TagName = 'database' THEN AvgScoreInTag ELSE 0.0 END) AS DatabaseAvgScore,
        MAX(CASE WHEN TagName = 'performance' THEN PostsInTag ELSE 0 END) AS PerformancePostsCount,
        MAX(CASE WHEN TagName = 'performance' THEN TotalScoreInTag ELSE 0 END) AS PerformanceTotalScore,
        MAX(CASE WHEN TagName = 'indexing' THEN PostsInTag ELSE 0 END) AS IndexingPostsCount,
        MAX(CASE WHEN TagName = 'query-optimization' THEN TotalScoreInTag ELSE 0 END) AS QueryOptTotalScore
    FROM UserTagImpact
    GROUP BY UserId
)
SELECT
    U.Id AS UserID,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserAccountCreationDate,
    U.LastAccessDate,
    U.Location,
    COALESCE(U.WebsiteUrl, 'N/A') AS WebsiteUrl,
    U.Views AS ProfileViews,
    U.UpVotes AS TotalUpVotesGiven,
    U.DownVotes AS TotalDownVotesGiven,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    UAS.TotalCommentsMade,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, UAS.TotalPostScore DESC) AS GlobalReputationRank,
    DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate) ORDER BY U.Reputation DESC) AS YearlyReputationRank,
    LAG(U.Reputation, 1, 0) OVER (ORDER BY U.CreationDate) AS PrevUserReputationByCreationDate,
    AVG(UAS.TotalPostScore) OVER (PARTITION BY COALESCE(U.Location, 'Unknown')) AS AvgPostScoreInLocationGroup,
    NTILE(10) OVER (ORDER BY UAS.TotalQuestions + UAS.TotalAnswers + UAS.TotalCommentsMade DESC) AS ActivityDecile,

    (
        SELECT COUNT(PDR.PostId)
        FROM PostDetailsRaw PDR
        WHERE PDR.OwnerUserId = U.Id
          AND PDR.PostTypeId = 1
          AND PDR.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    ) AS RecentQuestionsCount,
    (
        SELECT COUNT(PDR.PostId)
        FROM PostDetailsRaw PDR
        WHERE PDR.OwnerUserId = U.Id
          AND PDR.PostTypeId = 2
          AND PDR.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    ) AS RecentAnswersCount,
    (
        SELECT SUM(PDR.ViewCount)
        FROM PostDetailsRaw PDR
        WHERE PDR.OwnerUserId = U.Id
          AND PDR.PostTypeId = 1
          AND PDR.PostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 year')
    ) AS TotalQuestionViewsLast2Years,
    (
        SELECT COUNT(PH.Id)
        FROM PostHistory PH
        WHERE PH.UserId = U.Id
          AND PH.PostHistoryTypeId IN (4, 5, 6, 24)
          AND PH.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 month')
    ) AS EditsMadeLast6Months,
    (
        SELECT COALESCE(SUM(LinkedPostsCount), 0)
        FROM (
            SELECT PL.PostId, COUNT(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE NULL END) AS LinkedPostsCount
            FROM PostLinks PL
            GROUP BY PL.PostId
        ) AS PostLinkAggs
        WHERE PostLinkAggs.PostId IN (
            SELECT PDR_inner.PostId
            FROM PostDetailsRaw PDR_inner
            WHERE PDR_inner.OwnerUserId = U.Id
        )
    ) AS TotalLinkedPostsBySelf,
    (
        SELECT MAX(PDR_inner.Score)
        FROM PostDetailsRaw PDR_inner
        WHERE PDR_inner.OwnerUserId = U.Id AND PDR_inner.PostTypeId = 1
    ) AS MaxQuestionScore,
    (
        SELECT MIN(PDR_inner.PostCreationDate)
        FROM PostDetailsRaw PDR_inner
        WHERE PDR_inner.OwnerUserId = U.Id AND PDR_inner.PostTypeId = 2
    ) AS FirstAnswerDate,
    CAST(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60 * 60 * 24 * 365.25) AS NUMERIC(10, 2)) AS AccountAgeYears,
    COALESCE(CHAR_LENGTH(U.AboutMe), 0) AS AboutMeLength,
    NULLIF(TRIM(SUBSTRING(U.AboutMe FROM 1 FOR 150)), '') AS AboutMeSnippet,
    LOWER(U.DisplayName) LIKE '%dev%' AS IsDevInDisplayName,
    UPPER(SUBSTRING(COALESCE(U.Location, 'UNKNOWN') FROM 1 FOR 3)) AS LocationPrefix,
    COALESCE(AUTI.SqlPostsCount, 0) AS SqlPostsCount,
    COALESCE(AUTI.SqlTotalScore, 0) AS SqlTotalScore,
    COALESCE(AUTI.DatabaseAvgScore, 0.0) AS DatabaseAvgScore,
    COALESCE(AUTI.PerformancePostsCount, 0) AS PerformancePostsCount,
    COALESCE(AUTI.PerformanceTotalScore, 0) AS PerformanceTotalScore,
    COALESCE(AUTI.IndexingPostsCount, 0) AS IndexingPostsCount,
    COALESCE(AUTI.QueryOptTotalScore, 0) AS QueryOptTotalScore,
    NULLIF(UAS.TotalPostScore + U.UpVotes - U.DownVotes + COALESCE(UBS.TotalBadges * 10, 0) + (U.Views / 100), 0) AS WeightedUserImpactScore,
    CASE
        WHEN COALESCE(UBS.GoldBadges, 0) >= 5 AND UAS.TotalAnswers > 50 AND U.Reputation > 50000 THEN 'Elite Contributor'
        WHEN U.Reputation > 10000 AND UAS.TotalPostScore > 5000 AND UAS.TotalQuestions >= 10 THEN 'Highly Influential Questioner'
        WHEN UAS.TotalAnswers >= 100 AND UAS.TotalPostScore > 7500 AND U.DownVotes < 500 THEN 'Prodigious Answerer'
        WHEN U.LastAccessDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AND U.Reputation < 5000 THEN 'Dormant User'
        WHEN (UAS.TotalQuestions + UAS.TotalAnswers + UAS.TotalCommentsMade) > 500 THEN 'Hyper-Active Community Member'
        ELSE 'Regular Contributor'
    END AS UserCategory,
    EXISTS (
        SELECT 1
        FROM PostDetailsRaw Q
        WHERE Q.OwnerUserId = U.Id
          AND Q.PostTypeId = 1
          AND EXISTS (
              SELECT 1
              FROM Posts A
              WHERE A.ParentId = Q.PostId
                AND A.OwnerUserId = U.Id
                AND A.PostTypeId = 2
          )
    ) AS HasAnsweredOwnQuestion
FROM Users U
LEFT JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
LEFT JOIN UserBadgesSummary UBS ON U.Id = UBS.UserId
LEFT JOIN AggregatedUserTagImpact AUTI ON U.Id = AUTI.UserId
WHERE
    U.Reputation > 500
    AND U.DisplayName IS NOT NULL AND TRIM(U.DisplayName) <> ''
    AND (
        U.Location ILIKE '%us%' OR U.Location ILIKE '%europe%' OR U.Location ILIKE '%asia%' OR U.Location IS NULL
    )
    AND U.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 year')
    AND (
        (U.WebsiteUrl IS NOT NULL AND CHAR_LENGTH(U.WebsiteUrl) > 5) OR CHAR_LENGTH(COALESCE(U.AboutMe, '')) > 50 OR U.Views > 100
    )
    AND (COALESCE(UAS.TotalQuestions, 0) > 3 OR COALESCE(UAS.TotalAnswers, 0) > 5 OR COALESCE(UAS.TotalCommentsMade, 0) > 10)
    AND (
        EXISTS (SELECT 1 FROM UserTagImpact UTI_filt WHERE UTI_filt.UserId = U.Id AND UTI_filt.TagName IN ('sql', 'database') AND UTI_filt.PostsInTag >= 2 AND UTI_filt.AvgScoreInTag > 1.5) OR
        EXISTS (SELECT 1 FROM UserTagImpact UTI_filt WHERE UTI_filt.UserId = U.Id AND UTI_filt.TagName = 'performance' AND UTI_filt.TotalScoreInTag >= 20 AND UTI_filt.PostsInTag >= 1)
    )
    AND (U.Id % 7) <> 0
ORDER BY
    GlobalReputationRank ASC, UserID
LIMIT 1000;