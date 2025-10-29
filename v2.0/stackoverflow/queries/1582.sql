-- {"query": "1582.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2433} 
WITH ActiveUsersWithBadges AS (
    -- Identify highly active users who have received a significant number of badges recently
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(B.Id) AS TotalBadges,
        MAX(B.Date) AS LastBadgeDate,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadgesCount
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation >= 15000 -- Filter for high-reputation users
      AND B.Date >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 year') -- Badges received within the last 3 years
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(B.Id) >= 10 -- Users with at least 10 recent badges
),
QuestionDetails AS (
    -- Extract core details for questions, including aggregated comment info and initial tags
    SELECT
        P.Id AS QuestionId,
        P.Title AS QuestionTitle,
        P.CreationDate AS QuestionCreationDate,
        P.ViewCount,
        P.Score AS QuestionScore,
        P.OwnerUserId AS QuestionOwnerId,
        U.DisplayName AS QuestionOwnerDisplayName,
        P.AcceptedAnswerId,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        PH_Tags.Text AS InitialTagsRaw, -- Raw string of initial tags
        (SELECT COUNT(DISTINCT C.UserId) FROM Comments C WHERE C.PostId = P.Id AND C.UserId IS NOT NULL) AS DistinctCommentersCount,
        (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 8) AS TotalBountyAmount, -- Sum of bounty amounts
        P.LastActivityDate
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN PostHistory PH_Tags ON P.Id = PH_Tags.PostId AND PH_Tags.PostHistoryTypeId = 3 -- Get initial tags from history
    WHERE P.PostTypeId = 1 -- Only questions
      AND P.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 year') -- Questions created in the last 6 years
      AND P.Score >= 0
),
AnswerPerformanceMetrics AS (
    -- Analyze answer performance, including ranking within its parent question and owner's general answer performance
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerId,
        AnsU.DisplayName AS AnswerOwnerDisplayName,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.CommentCount AS AnswerCommentCount,
        -- Window function: Rank answers by score within each question, breaking ties by creation date
        ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS RankInQuestion,
        -- Correlated subquery: Calculate the average score of other answers by the same user
        (SELECT AVG(CAST(SubA.Score AS NUMERIC)) FROM Posts SubA WHERE SubA.OwnerUserId = A.OwnerUserId AND SubA.Id != A.Id AND SubA.PostTypeId = 2 AND SubA.Score >= 0) AS AvgScoreOtherAnswersBySameUser
    FROM Posts A
    JOIN Users AnsU ON A.OwnerUserId = AnsU.Id
    WHERE A.PostTypeId = 2 -- Only answers
      AND A.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 year')
      AND A.Score >= 0
),
PostEditActivity AS (
    -- Summarize editing activity for each post, including distinct editors and last content edit date
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalEdits,
        MAX(PH.CreationDate) AS LastEditDate,
        COUNT(DISTINCT PH.UserId) AS DistinctEditorsCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS LastContentEditDate -- Title, Body, Tags edits
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4,5,6,7,8,9) -- Edits or Rollbacks of Title, Body, Tags
    GROUP BY PH.PostId
),
RelatedPostInfo AS (
    -- Identify linked and duplicate posts, aggregating related post IDs
    SELECT
        PL.PostId AS SourcePostId,
        STRING_AGG(DISTINCT CASE WHEN PL.LinkTypeId = 1 THEN CAST(PL.RelatedPostId AS VARCHAR) ELSE NULL END, ', ') AS LinkedPostIds,
        STRING_AGG(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN CAST(PL.RelatedPostId AS VARCHAR) ELSE NULL END, ', ') AS DuplicateOfPostIds,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId ELSE NULL END) AS DuplicateCount
    FROM PostLinks PL
    GROUP BY PL.PostId
)
-- Main query: Combine insights from all CTEs to generate a comprehensive view of questions and their ecosystem
SELECT
    QD.QuestionId,
    QD.QuestionTitle,
    QD.QuestionCreationDate,
    QD.ViewCount,
    QD.QuestionScore,
    QD.QuestionOwnerDisplayName,
    COALESCE(AUB_Q.Reputation, 0) AS QuestionOwnerReputation,
    COALESCE(AUB_Q.GoldBadgesCount, 0) AS QuestionOwnerGoldBadges,
    QD.AnswerCount,
    QD.FavoriteCount,
    QD.DistinctCommentersCount,
    COALESCE(QD.TotalBountyAmount, 0) AS QuestionTotalBounty,
    -- String expression: Extract the first tag from the raw initial tags string, handling potential NULLs
    TRIM(BOTH '>' FROM SUBSTRING(QD.InitialTagsRaw FROM POSITION('<' IN QD.InitialTagsRaw) + 1 FOR COALESCE(NULLIF(POSITION('>' IN QD.InitialTagsRaw), 0) - POSITION('<' IN QD.InitialTagsRaw) - 1, 0))) AS FirstInitialTag,
    -- Complicated calculation: Score-to-view ratio, handling division by zero with NULLIF and COALESCE
    COALESCE(CAST(QD.QuestionScore AS NUMERIC) / NULLIF(QD.ViewCount, 0), 0.0) AS ScorePerViewRatio,
    -- Time elapsed in days from question creation to its last activity
    EXTRACT(EPOCH FROM (QD.LastActivityDate - QD.QuestionCreationDate)) / (24 * 3600) AS DaysToLastActivity,
    COALESCE(PEA_Q.TotalEdits, 0) AS QuestionTotalEdits,
    PEA_Q.LastEditDate AS QuestionLastEditDate,
    COALESCE(PEA_Q.DistinctEditorsCount, 0) AS QuestionDistinctEditors,
    RPI.LinkedPostIds AS QuestionLinkedPosts,
    RPI.DuplicateOfPostIds AS QuestionDuplicateOfPosts,
    COALESCE(RPI.DuplicateCount, 0) AS IsDuplicateOfCount,
    -- Accepted answer details (if any)
    AA.AnswerId AS AcceptedAnswerId,
    AA.AnswerOwnerDisplayName AS AcceptedAnswerOwner,
    AA.AnswerScore AS AcceptedAnswerScore,
    AA.AnswerCreationDate AS AcceptedAnswerCreationDate,
    COALESCE(AA.RankInQuestion, 0) AS AcceptedAnswerRankInQuestion,
    COALESCE(PEA_A.TotalEdits, 0) AS AcceptedAnswerTotalEdits,
    COALESCE(AA.AvgScoreOtherAnswersBySameUser, 0.0) AS AcceptedAnswerOwnerAvgOtherScores,
    -- Window function: Calculate the average score of accepted answers for all questions by the same original owner
    AVG(AA.AnswerScore) OVER (PARTITION BY QD.QuestionOwnerId) AS AvgAcceptedAnswerScoreForOwnerQuestions,
    -- NULL logic and conditional expression: Categorize question status based on accepted answer and closure
    CASE
        WHEN QD.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN QD.AcceptedAnswerId IS NOT NULL AND AA.AnswerScore IS NOT NULL AND AA.AnswerScore > QD.QuestionScore THEN 'AcceptedAnswerOutperformsQuestion'
        WHEN QD.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswerPresent'
        ELSE 'NoAcceptedAnswerYet'
    END AS QuestionLifecycleStatus,
    -- Complicated string and numeric expression: Calculate a "Relevance Score"
    -- Based on activity, views, and score, penalizing older posts and questions with low answers/favorites
    (
        (QD.QuestionScore * 0.5) + (QD.ViewCount * 0.01) + (QD.FavoriteCount * 2) + (QD.AnswerCount * 1.5)
        - (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - QD.LastActivityDate)) / (3600 * 24 * 30.0)) -- penalize by months since last activity
        + (CASE WHEN QD.InitialTagsRaw LIKE '%<performance>%' OR QD.QuestionTitle ILIKE '%benchmark%' THEN 100 ELSE 0 END) -- Boost specific keywords
    ) AS RelevanceScore
FROM QuestionDetails QD
LEFT JOIN ActiveUsersWithBadges AUB_Q ON QD.QuestionOwnerId = AUB_Q.UserId
LEFT JOIN AnswerPerformanceMetrics AA ON QD.AcceptedAnswerId = AA.AnswerId
LEFT JOIN PostEditActivity PEA_Q ON QD.QuestionId = PEA_Q.PostId
LEFT JOIN PostEditActivity PEA_A ON QD.AcceptedAnswerId = PEA_A.PostId
LEFT JOIN RelatedPostInfo RPI ON QD.QuestionId = RPI.SourcePostId
WHERE QD.ViewCount >= 100 -- Focus on questions with at least 100 views
  AND QD.FavoriteCount IS NOT NULL -- Exclude questions where favorite count is not tracked
  AND QD.QuestionId IN (SELECT DISTINCT PostId FROM Comments WHERE CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')) -- Correlated subquery: only questions with comments in the last year
  AND (QD.QuestionTitle LIKE '%SQL%' OR QD.InitialTagsRaw LIKE '%<sql>%') -- Must contain 'SQL' in title or tags
ORDER BY RelevanceScore DESC, QD.QuestionScore DESC, QD.ViewCount DESC
LIMIT 500;