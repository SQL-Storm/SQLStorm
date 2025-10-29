-- {"query": "1156.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2557} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views,
        U.UpVotes AS CastUpVotes,    -- Upvotes cast by the user
        U.DownVotes AS CastDownVotes, -- Downvotes cast by the user
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN VP.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalReceivedUpVotes, -- Votes received on user's posts
        SUM(CASE WHEN VP.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalReceivedDownVotes
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes VP ON P.Id = VP.PostId AND VP.VoteTypeId IN (2,3) -- Votes on user's posts
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.FavoriteCount,
        P.Tags,
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId IS NOT NULL) AS DistinctEditors,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS QuestionUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS QuestionDownVotes,
        COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'), 1), 0) AS TagCount,
        -- Correlated subquery 1: Latest comment text for a post
        (SELECT Text FROM Comments WHERE PostId = P.Id ORDER BY CreationDate DESC LIMIT 1) AS LatestCommentOnPost
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId = 1 -- Only questions
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.LastActivityDate, P.ClosedDate, P.FavoriteCount, P.Tags
),
BadgeDistribution AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
QuestionTagBreakdown AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
DuplicateQuestionLinks AS (
    SELECT
        PL.PostId AS OriginalQuestionId,
        PL.RelatedPostId AS DuplicateQuestionId,
        P.CreationDate AS OriginalCreationDate,
        P.Score AS OriginalScore,
        -- Correlated subquery 2: Fetch details of the duplicated question
        (SELECT MAX(Q.CreationDate) FROM Posts Q WHERE Q.Id = PL.RelatedPostId AND Q.PostTypeId = 1) AS DuplicateCreationDate,
        (SELECT AVG(Q.Score) FROM Posts Q WHERE Q.Id = PL.RelatedPostId AND Q.PostTypeId = 1) AS DuplicateScoreAverage
    FROM PostLinks PL
    JOIN Posts P ON PL.PostId = P.Id
    WHERE PL.LinkTypeId = 3 -- Duplicate link type
)
-- Main query
SELECT
    UAS.UserId,
    COALESCE(U.DisplayName, 'Deleted User') AS UserDisplayName,
    UAS.Reputation,
    UAS.CreationDate AS UserCreationDate,
    UAS.LastAccessDate,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    UAS.TotalComments,
    UAS.TotalReceivedUpVotes,
    UAS.TotalReceivedDownVotes,
    COALESCE(BD.GoldBadges, 0) AS GoldBadges,
    COALESCE(BD.SilverBadges, 0) AS SilverBadges,
    COALESCE(BD.BronzeBadges, 0) AS BronzeBadges,
    SUM(PEM.PostScore) AS TotalOwnedQuestionScore,
    SUM(PEM.ViewCount) AS TotalOwnedQuestionViews,
    COALESCE(SUM(PEM.AnswerCount), 0) AS TotalOwnedAnswersOnQuestions,
    AVG(PEM.DistinctEditors) AS AvgDistinctEditorsPerQuestion,
    MAX(PEM.LatestCommentOnPost) AS LatestCommentAcrossOwnedQuestions,
    COUNT(DISTINCT DQL.OriginalQuestionId) AS QuestionsMarkedAsDuplicate, -- Count distinct questions owned by user that are 'original' in a duplicate link
    NTILE(10) OVER (ORDER BY UAS.Reputation DESC, UAS.TotalPostScore DESC) AS ReputationTier,
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM UAS.CreationDate) ORDER BY UAS.TotalPosts DESC, UAS.Reputation DESC) AS PostsRankInCreationYear,
    -- Complex calculation: User engagement ratio combining votes and comments
    CAST(UAS.TotalReceivedUpVotes + UAS.TotalComments AS DECIMAL) / NULLIF(UAS.TotalReceivedUpVotes + UAS.TotalReceivedDownVotes + UAS.TotalComments + UAS.TotalQuestions + UAS.TotalAnswers, 0) AS UserEngagementRatio,
    -- String expression: First 100 characters of AboutMe or a default message, converted to uppercase
    UPPER(SUBSTRING(COALESCE(U.AboutMe, 'No info provided, quite mysterious...'), 1, 100)) AS AboutMePreview,
    -- NULL logic and date difference (age of account vs. time since last access)
    AGE(CURRENT_TIMESTAMP, UAS.LastAccessDate) AS TimeSinceLastAccess,
    AGE(CURRENT_TIMESTAMP, UAS.CreationDate) AS AccountAge,
    -- Correlated subquery 3: Check if user has ever posted an answer that became accepted for a "highly viewed" question
    EXISTS (
        SELECT 1
        FROM Posts A_corr
        JOIN Posts Q_corr ON A_corr.ParentId = Q_corr.Id
        WHERE A_corr.OwnerUserId = UAS.UserId
          AND A_corr.Id = Q_corr.AcceptedAnswerId
          AND Q_corr.ViewCount > 50000 -- Highly viewed threshold
          AND Q_corr.CreationDate BETWEEN (UAS.CreationDate + INTERVAL '6 month') AND UAS.LastAccessDate -- Question posted in user's more active period
    ) AS HasAcceptedAnswerOnHighlyViewedQuestion,
    -- Aggregated tag information for the user's questions
    COUNT(DISTINCT CASE WHEN QTB.TagName IN ('sql', 'database', 'performance', 'indexing') THEN QTB.QuestionId END) AS RelevantTagQuestions,
    STRING_AGG(DISTINCT QTB.TagName, '; ') FILTER (WHERE QTB.TagName IN ('sql', 'database') AND QTB.TagName IS NOT NULL) AS PopularSqlTagsList
FROM UserActivitySummary UAS
LEFT JOIN Users U ON UAS.UserId = U.Id
LEFT JOIN PostEngagementMetrics PEM ON UAS.UserId = PEM.OwnerUserId AND PEM.PostCreationDate > (UAS.CreationDate + INTERVAL '1 month') -- Only questions posted by user after their first month of activity
LEFT JOIN BadgeDistribution BD ON UAS.UserId = BD.UserId
LEFT JOIN QuestionTagBreakdown QTB ON UAS.UserId = QTB.OwnerUserId
LEFT JOIN DuplicateQuestionLinks DQL ON PEM.PostId = DQL.OriginalQuestionId -- Links owned questions to their duplicate status
WHERE
    UAS.Reputation > 5000 -- Filter for more established users
    AND UAS.TotalQuestions > 5 -- At least 5 questions
    AND (U.Location LIKE '%United States%' OR U.Location LIKE '%Canada%' OR U.Location LIKE '%Europe%' OR U.Location IS NULL) -- Complex location predicate with NULL logic
    AND UAS.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '6 month') -- Recently active users
    AND EXISTS (
        SELECT 1
        FROM Posts P_inner
        WHERE P_inner.OwnerUserId = UAS.UserId
          AND P_inner.PostTypeId = 2 -- An answer
          AND P_inner.CreationDate BETWEEN UAS.CreationDate AND UAS.LastAccessDate -- Within their active period
          AND P_inner.Score >= 10 -- Has at least one highly upvoted answer
          AND P_inner.Body LIKE '%JOIN%' AND P_inner.Body NOT LIKE '%CSS%' -- String pattern matching on answer body
    ) -- Correlated subquery 4: User has at least one answer with specific content and score
GROUP BY
    UAS.UserId, U.DisplayName, UAS.Reputation, UAS.CreationDate, UAS.LastAccessDate,
    UAS.TotalPosts, UAS.TotalQuestions, UAS.TotalAnswers, UAS.TotalPostScore,
    UAS.TotalComments, UAS.TotalReceivedUpVotes, UAS.TotalReceivedDownVotes,
    BD.GoldBadges, BD.SilverBadges, BD.BronzeBadges, U.AboutMe, U.Location
HAVING
    COUNT(DISTINCT PEM.PostId) >= 3 -- At least 3 questions qualifying for PostEngagementMetrics join
    AND (AVG(PEM.QuestionUpVotes) > 5 OR COALESCE(BD.GoldBadges, 0) >= 1) -- Average question upvotes or at least one gold badge
    AND SUM(CASE WHEN DQL.OriginalQuestionId IS NOT NULL THEN 1 ELSE 0 END) < 5 -- Not too many questions marked as duplicates
ORDER BY
    ReputationTier ASC,
    PostsRankInCreationYear ASC,
    TotalOwnedQuestionScore DESC
LIMIT 1000;
