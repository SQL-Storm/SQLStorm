-- {"query": "19024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3128} 

WITH UserActivitySummary AS (
    -- Summarizes user activity, including their post counts, vote scores, reputation tiers,
    -- and a window function to rank users by net vote score and creation date quartile.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        (U.UpVotes - U.DownVotes) AS NetVotesGiven,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreOwned,
        COUNT(DISTINCT P.Id) AS PostsCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCount,
        RANK() OVER (ORDER BY U.Reputation DESC, (U.UpVotes - U.DownVotes) DESC) AS ReputationRank,
        NTILE(4) OVER (ORDER BY U.CreationDate ASC, U.Id ASC) AS UserAgeQuartile, -- Divides users into 4 age groups
        CASE
            WHEN U.Reputation > 10000 THEN 'Elite'
            WHEN U.Reputation > 2000 THEN 'Experienced'
            WHEN U.Reputation > 500 THEN 'Contributor'
            ELSE 'Novice'
        END AS ReputationTier
    FROM
        Users AS U
    LEFT JOIN
        Posts AS P ON U.Id = P.OwnerUserId
    WHERE
        U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '2 year' -- Active users within last 2 years
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING
        COUNT(P.Id) > 5 OR U.Reputation > 1000 -- Filter for more active or reputable users
),
QuestionDetails AS (
    -- Gathers detailed information about questions, including aggregated answer scores,
    -- the latest close reason (via a correlated subquery), and a measure of 'controversy' based on comments.
    -- Includes a correlated subquery to fetch the latest comment text.
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.OwnerUserId,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.ClosedDate,
        Q.Tags,
        (SELECT COALESCE(AVG(A.Score), 0) FROM Posts AS A WHERE A.ParentId = Q.Id AND A.PostTypeId = 2) AS AvgAnswerScore,
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory AS PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS UniqueEditorsCount,
        COALESCE(
            (SELECT CRT_Sub.Name
             FROM PostHistory AS PH_Close_Sub
             JOIN CloseReasonTypes AS CRT_Sub ON PH_Close_Sub.Comment::SMALLINT = CRT_Sub.Id -- Explicit cast for potential integer conversion
             WHERE PH_Close_Sub.PostId = Q.Id AND PH_Close_Sub.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
             ORDER BY PH_Close_Sub.CreationDate DESC LIMIT 1), 'N/A'
        ) AS LatestCloseReason,
        (SELECT C_Sub.Text FROM Comments AS C_Sub WHERE C_Sub.PostId = Q.Id ORDER BY C_Sub.CreationDate DESC LIMIT 1) AS LatestCommentText,
        SUM(CASE WHEN C.Score < 0 THEN 1 ELSE 0 END) AS NegativeCommentCount,
        COUNT(PL_Dup.RelatedPostId) AS DuplicateLinkCount
    FROM
        Posts AS Q
    LEFT JOIN
        Comments AS C ON Q.Id = C.PostId
    LEFT JOIN
        PostLinks AS PL_Dup ON Q.Id = PL_Dup.PostId AND PL_Dup.LinkTypeId = 3 -- Duplicate links
    WHERE
        Q.PostTypeId = 1
    GROUP BY
        Q.Id, Q.Title, Q.CreationDate, Q.OwnerUserId, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.ClosedDate, Q.Tags
),
TopAnswerPerQuestion AS (
    -- Identifies the highest-scored answer for each question and calculates a score difference
    -- relative to the second-highest answer using LAG(). Uses QUALIFY for filtering.
    SELECT
        A.ParentId AS QuestionId,
        A.Id AS TopAnswerId,
        A.Score AS TopAnswerScore,
        A.CreationDate AS TopAnswerCreationDate,
        A.OwnerUserId AS TopAnswerOwnerId,
        LAG(A.Score, 1, 0) OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS SecondTopAnswerScore,
        (A.Score - LAG(A.Score, 1, 0) OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC)) AS ScoreDifferenceFromNext
    FROM
        Posts AS A
    WHERE
        A.PostTypeId = 2
    QUALIFY ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) = 1
),
HighlyVotedComments AS (
    -- Finds comments with high scores on questions, potentially indicating crucial feedback or problems.
    -- Uses a subquery to filter for comments attached to questions.
    SELECT
        C.PostId AS QuestionId,
        C.Text AS CommentText,
        C.Score AS CommentScore,
        C.UserId AS CommentOwnerId,
        C.CreationDate AS CommentCreationDate
    FROM
        Comments AS C
    WHERE
        C.Score > 5
        AND C.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
),
FrequentBadges AS (
    -- Identifies users who have received a significant number of gold or silver badges recently.
    SELECT
        B.UserId,
        COUNT(B.Id) AS GoldSilverBadgeCount,
        MAX(B.Date) AS LatestBadgeDate
    FROM
        Badges AS B
    WHERE
        B.Class IN (1, 2) -- Gold (1) or Silver (2) badges
        AND B.Date >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY
        B.UserId
    HAVING
        COUNT(B.Id) >= 3
),
ModeratorActivity AS (
    -- Tracks posts that have been involved in moderator actions (locked, protected, deleted/undeleted).
    -- Uses UNION ALL to combine different action types, demonstrating set operators.
    SELECT
        PH.PostId,
        'Locked/Unlocked' AS ActionType,
        PH.CreationDate AS ActionDate,
        PH.UserId AS ModeratorUserId
    FROM PostHistory AS PH WHERE PH.PostHistoryTypeId IN (14, 15) -- Post Locked, Post Unlocked
    UNION ALL
    SELECT
        PH.PostId,
        'Protected/Unprotected' AS ActionType,
        PH.CreationDate AS ActionDate,
        PH.UserId AS ModeratorUserId
    FROM PostHistory AS PH WHERE PH.PostHistoryTypeId IN (19, 20) -- Question Protected, Question Unprotected
    UNION ALL
    SELECT
        PH.PostId,
        'Deleted/Undeleted' AS ActionType,
        PH.CreationDate AS ActionDate,
        PH.UserId AS ModeratorUserId
    FROM PostHistory AS PH WHERE PH.PostHistoryTypeId IN (12, 13) -- Post Deleted, Post Undeleted
)
-- Main query to combine insights from various CTEs and identify "critical" or "influential" questions
SELECT
    QD.QuestionId,
    QD.QuestionTitle,
    QD.QuestionCreationDate,
    UA.DisplayName AS QuestionOwnerDisplayName,
    UA.Reputation AS QuestionOwnerReputation,
    QD.QuestionScore,
    QD.ViewCount,
    QD.AnswerCount,
    QD.FavoriteCount,
    QD.LatestCloseReason,
    QD.UniqueEditorsCount,
    QD.AvgAnswerScore,
    QD.NegativeCommentCount,
    QD.DuplicateLinkCount,
    TAPQ.TopAnswerScore,
    TAPQ.ScoreDifferenceFromNext,
    FB.GoldSilverBadgeCount AS OwnerGoldSilverBadges,
    COALESCE(HV.CommentText, 'No High Score Comment') AS CriticalCommentExcerpt, -- NULL logic, string expression
    MOD_ACT.ActionType AS LatestModeratorAction,
    MOD_ACT.ActionDate AS LatestModeratorActionDate,
    -- Complicated predicates/expressions/calculations
    (QD.QuestionScore::NUMERIC / NULLIF(QD.ViewCount, 0)) AS ScoreToViewRatio, -- NULL logic, type casting
    (QD.FavoriteCount::NUMERIC / NULLIF(QD.ViewCount, 0)) AS FavoriteToViewRatio,
    (QD.QuestionScore + COALESCE(QD.AvgAnswerScore, 0) + COALESCE(QD.FavoriteCount, 0)) AS CombinedEngagementScore, -- NULL logic
    CASE
        WHEN QD.ClosedDate IS NOT NULL AND QD.LatestCloseReason NOT LIKE '%Duplicate%' THEN 'Problematic (Closed Non-Duplicate)'
        WHEN QD.AnswerCount = 0 AND QD.ViewCount > 5000 THEN 'Unanswered Popular'
        WHEN QD.QuestionScore < 0 AND QD.ViewCount > 1000 THEN 'Controversial Low Score'
        WHEN QD.UniqueEditorsCount > 5 AND QD.QuestionScore > 50 THEN 'Highly Edited & Popular'
        WHEN TAPQ.ScoreDifferenceFromNext IS NOT NULL AND TAPQ.ScoreDifferenceFromNext > 50 THEN 'Dominant Answer'
        WHEN MOD_ACT.ActionType IS NOT NULL THEN 'Moderated Post'
        ELSE 'Standard'
    END AS QuestionCategory,
    -- String expressions
    UPPER(SUBSTRING(QD.QuestionTitle, 1, 1)) AS TitleFirstCharUpper,
    TRIM(REPLACE(REPLACE(QD.Tags, '>', ' '), '<', ' ')) AS CleanedTags, -- Nested string functions
    -- NULL logic checks
    COALESCE(UA.ReputationTier, 'Unknown') AS QuestionOwnerReputationTier,
    (TAPQ.TopAnswerId IS NULL AND QD.AnswerCount > 0) AS HasNoTopAnswerDespiteAnswers,
    (MOD_ACT.PostId IS NOT NULL AND MOD_ACT.ActionType = 'Deleted/Undeleted') AS WasDeletedOrUndeleted
FROM
    QuestionDetails AS QD
LEFT JOIN
    UserActivitySummary AS UA ON QD.OwnerUserId = UA.UserId
LEFT JOIN
    TopAnswerPerQuestion AS TAPQ ON QD.QuestionId = TAPQ.QuestionId
LEFT JOIN
    FrequentBadges AS FB ON QD.OwnerUserId = FB.UserId
LEFT JOIN LATERAL -- LATERAL join to get the latest moderator action for a post (correlated subquery behavior for joins)
    (SELECT
         MAX(ActionType) AS ActionType, -- Max here aggregates if multiple actions on same date, effectively taking one.
         MAX(ActionDate) AS ActionDate,
         PostId,
         ModeratorUserId
     FROM ModeratorActivity MA
     WHERE MA.PostId = QD.QuestionId
     GROUP BY PostId, ModeratorUserId
     ORDER BY ActionDate DESC LIMIT 1
    ) AS MOD_ACT ON TRUE
LEFT JOIN LATERAL -- LATERAL join for the top highly voted comment (correlated subquery behavior for joins)
    (SELECT CommentText, CommentOwnerId FROM HighlyVotedComments HVC WHERE HVC.QuestionId = QD.QuestionId ORDER BY CommentScore DESC LIMIT 1) AS HV ON TRUE
WHERE
    QD.ViewCount > 1000 -- Filter for popular questions
    AND QD.QuestionCreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 year' -- Relatively recent questions
    AND (QD.QuestionScore > 15 OR QD.AnswerCount > 7 OR QD.FavoriteCount > 3) -- Some significant engagement
    AND (
        QD.LatestCloseReason NOT LIKE '%Duplicate%' -- Not closed as a duplicate
        OR QD.ClosedDate IS NULL -- Or not closed at all
        OR QD.UniqueEditorsCount > 4 -- Or frequently edited even if closed as duplicate
    )
    AND (
        UA.Reputation > 750 -- Owner is a fairly reputable user
        OR QD.OwnerUserId IS NULL -- Or the owner has been deleted (community post)
    )
    AND (
        QD.Tags LIKE '%<sql>%' -- Specific tag interest
        OR QD.Tags LIKE '%<database>%'
        OR QD.Tags LIKE '%<performance>%'
        OR QD.Tags LIKE '%<query-optimization>%'
    )
    AND (NOT (TAPQ.TopAnswerId IS NULL AND QD.AnswerCount > 0) OR QD.AnswerCount = 0) -- Either has a top answer, or no answers at all
    AND (QD.LatestCommentText IS NOT NULL OR HV.CommentText IS NOT NULL OR QD.NegativeCommentCount > 0) -- Has some form of comment activity
ORDER BY
    CombinedEngagementScore DESC,
    QD.QuestionCreationDate DESC
LIMIT 500; -- Limit results for practical benchmarking
