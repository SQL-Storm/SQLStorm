-- {"query": "19042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2640} 
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE
        U.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years') -- Active users in the last 3 years
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostActivityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.FavoriteCount,
        P.CommentCount,
        P.Title,
        P.Tags,
        P.Body,
        P.LastEditDate,
        P.ClosedDate,
        (P.Score * 0.5 + P.ViewCount * 0.05 + COALESCE(P.AnswerCount, 0) * 0.3 + P.CommentCount * 0.2 + COALESCE(P.FavoriteCount, 0) * 0.8) AS WeightedEngagementScore,
        CASE
            WHEN P.PostTypeId = 1 AND P.Score > 50 AND P.FavoriteCount > 10 AND P.AcceptedAnswerId IS NOT NULL THEN 'High Impact Question with Accepted Answer'
            WHEN P.PostTypeId = 1 AND P.Score > 50 AND P.FavoriteCount > 10 THEN 'High Impact Question'
            WHEN P.PostTypeId = 2 AND P.Score > 75 AND P.AcceptedAnswerId IS NOT NULL THEN 'Accepted High Quality Answer'
            WHEN P.Score > 20 AND P.ViewCount > 1000 THEN 'Popular Content'
            ELSE 'Standard Content'
        END AS ContentCategory,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByPopularity
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2) -- Questions and Answers
        AND P.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years') -- Recent posts
        AND P.Body IS NOT NULL
),
PostRevisionAnalysis AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS RevisionDate,
        PH.UserId AS EditorUserId,
        PH.Text AS RevisionText,
        LAG(PH.Text, 1, '') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousRevisionText,
        LAG(PH.UserId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEditorUserId,
        RANK() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS RevisionRankDesc,
        COUNT(PH.Id) OVER (PARTITION BY PH.PostId) AS TotalRevisions
    FROM
        PostHistory PH
    WHERE
        PH.PostHistoryTypeId IN (2, 5, 8) -- Initial Body, Edit Body, Rollback Body
),
FrequentTagUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName,
        COUNT(DISTINCT P.Id) AS TagPostCount
    FROM
        Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE
        P.Tags IS NOT NULL
        AND P.PostTypeId = 1 -- Only questions for tag analysis
    GROUP BY
        U.Id, U.DisplayName, unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))
)
SELECT
    UES.UserId,
    UES.DisplayName AS UserName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.LastAccessDate,
    UES.TotalPosts,
    UES.TotalQuestions,
    UES.TotalAnswers,
    UES.AvgPostScore,
    UES.TotalComments,
    COALESCE(BA.GoldBadges, 0) AS GoldBadges,
    COALESCE(BA.SilverBadges, 0) AS SilverBadges,
    COALESCE(BA.BronzeBadges, 0) AS BronzeBadges,
    PAM.PostId,
    PAM.Title AS PostTitle,
    PAM.PostCreationDate,
    PAM.ContentCategory,
    PAM.WeightedEngagementScore,
    PRA.TotalRevisions,
    PRA.RevisionDate AS LastBodyRevisionDate,
    PRA.PreviousRevisionText,
    PRA.RevisionText AS CurrentRevisionText,
    LE.DisplayName AS LastEditorDisplayName,
    LE.Reputation AS LastEditorReputation,
    -- String expressions and calculations
    LENGTH(PAM.Body) AS BodyLength,
    LENGTH(PAM.Title) AS TitleLength,
    (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - PAM.PostCreationDate)) / (60 * 60 * 24))::int AS DaysSincePostCreation,
    TRIM(SPLIT_PART(PAM.Title, ' ', 1)) AS FirstTitleWord,
    UPPER(LEFT(COALESCE(UES.DisplayName, 'UNKNOWN'), 3)) AS UserInitialHash,
    -- Correlated subquery 1: Check if user has a comment on any 'High Impact Question' recently
    EXISTS (
        SELECT 1
        FROM Comments C
        JOIN PostActivityMetrics PAM_sub ON C.PostId = PAM_sub.PostId
        WHERE C.UserId = UES.UserId
          AND PAM_sub.ContentCategory LIKE 'High Impact Question%'
          AND C.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
        LIMIT 1
    ) AS CommentedOnHighImpactQuestionRecently,
    -- Correlated subquery 2: Find count of posts by the same user linked as duplicates to this post
    (
        SELECT COUNT(DISTINCT PL_sub.RelatedPostId)
        FROM PostLinks PL_sub
        WHERE PL_sub.PostId = PAM.PostId
          AND PL_sub.LinkTypeId = 3 -- Duplicate
          AND EXISTS (
              SELECT 1
              FROM Posts P_sub
              WHERE P_sub.Id = PL_sub.RelatedPostId
                AND P_sub.OwnerUserId = UES.UserId
                AND P_sub.PostTypeId = PAM.PostTypeId -- Must be the same post type
          )
    ) AS NumLinkedDuplicatesBySameUser,
    -- Window function: Average weighted engagement score for user's posts
    AVG(PAM.WeightedEngagementScore) OVER (PARTITION BY UES.UserId) AS AvgUserPostEngagementScore,
    -- Window function: Rank users by their total post score
    DENSE_RANK() OVER (ORDER BY UES.TotalPostScore DESC, UES.Reputation DESC) AS OverallUserPostScoreRank,
    -- NULL logic and complex predicates
    COALESCE(T.TagName, 'UNKNOWN_TAG') AS MostFrequentTag,
    T.TagPostCount AS MostFrequentTagCount,
    (UES.Reputation > 50000 AND COALESCE(BA.GoldBadges, 0) > 0 AND UES.AvgPostScore > 100) AS IsHighlyInfluential,
    PAM.ClosedDate IS NOT NULL AND (PAM.LastEditDate < PAM.ClosedDate - INTERVAL '1 month') AS EditedBeforeClosure,
    PAM.Body ILIKE '%performance%' AND PAM.Body ILIKE '%optimization%' AND PAM.Body NOT ILIKE '%database%' AS ContainsSpecificTechKeywords
FROM
    UserEngagementSummary UES
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
) BA ON UES.UserId = BA.UserId
LEFT JOIN PostActivityMetrics PAM ON UES.UserId = PAM.OwnerUserId
LEFT JOIN (
    SELECT
        PostId,
        RevisionDate,
        RevisionText,
        PreviousRevisionText,
        TotalRevisions,
        RevisionRankDesc,
        EditorUserId
    FROM PostRevisionAnalysis
    WHERE RevisionRankDesc = 1 -- Only the most recent revision details
) PRA ON PAM.PostId = PRA.PostId
LEFT JOIN Users LE ON PRA.EditorUserId = LE.Id -- Join for editor details to get their reputation
LEFT JOIN (
    SELECT
        UserId,
        TagName,
        TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC) as rn
    FROM FrequentTagUsers
) T ON UES.UserId = T.UserId AND T.rn = 1 -- Get the most frequent tag for each user
WHERE
    UES.Reputation > 1000 -- Filter for users with significant reputation
    AND UES.TotalPosts > 5 -- At least 5 posts
    AND UES.AvgPostScore >= 5.0 -- Average post score of 5 or more
    AND (PAM.ContentCategory LIKE 'High Impact Question%' OR PAM.ContentCategory = 'Accepted High Quality Answer') -- Focus on highly engaged posts
    AND (
        UES.TotalQuestions > 2
        OR EXISTS (
            SELECT 1
            FROM Badges B_sub
            WHERE B_sub.UserId = UES.UserId AND B_sub.Class = 1 -- User has at least one Gold Badge
        )
    )
    AND (PRA.TotalRevisions > 1 OR PAM.LastEditDate IS NULL) -- Posts that have been revised or never edited
    AND COALESCE(LE.Reputation, 0) > 100 -- Editor reputation check, handles NULL for no editor
    AND (PRA.RevisionText IS NOT NULL AND PRA.PreviousRevisionText IS NOT NULL AND LENGTH(PRA.RevisionText) - LENGTH(PRA.PreviousRevisionText) > 50) -- Significant body change
    AND UES.DisplayName IS NOT NULL
    AND PAM.RankByPopularity <= 1000 -- Consider only top 1000 posts by popularity per post type
    AND NOT (PAM.Body ILIKE '%spam%' OR PAM.Title ILIKE '%clickbait%') -- Exclude potentially problematic content
ORDER BY
    OverallUserPostScoreRank ASC, UES.LastAccessDate DESC, PAM.WeightedEngagementScore DESC
LIMIT 1000;