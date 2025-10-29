-- {"query": "1795.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3056} 

WITH UserPostEngagement AS (
    -- CTE to aggregate user activity related to posts, comments, and acceptance rates.
    -- It calculates various metrics for each user, including post counts by type, total scores, view counts,
    -- comment counts, and details about accepted answers.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPosts,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsCount,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersCount,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        -- Count of questions owned by the user that have an accepted answer.
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS AcceptedAnswersForOwnQuestionsCount,
        -- Count of answers owned by the user that were accepted by others for their questions.
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND P.Id = Acc.AcceptedAnswerId THEN 1 ELSE 0 END), 0) AS OwnAnswersAcceptedCount,
        -- Average length of the body text for posts owned by the user.
        COALESCE(AVG(LENGTH(P.Body)) FILTER (WHERE P.Body IS NOT NULL), 0) AS AvgPostBodyLength,
        -- Total number of comments made by the user.
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        -- Sum of scores for comments made by the user.
        COALESCE(SUM(C.Score), 0) AS TotalCommentScoreMade,
        -- Latest activity date across all posts owned by the user.
        MAX(P.LastActivityDate) AS LatestPostActivityDate,
        -- Count of unique tags used by the user in their questions, after splitting the tags string.
        COALESCE(COUNT(DISTINCT tag_split.tag) FILTER (WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL), 0) AS UniqueQuestionTags
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts AS Acc ON P.PostTypeId = 1 AND P.Id = Acc.ParentId AND P.AcceptedAnswerId = Acc.Id
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN LATERAL regexp_split_to_table(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><') AS tag_split(tag) ON P.PostTypeId = 1 AND P.Tags IS NOT NULL
    GROUP BY U.Id, U.DisplayName
),
UserReputationAndHistory AS (
    -- CTE to analyze reputation, badge achievements, and post history events for each user.
    -- It includes counts for different badge classes, post history events, and a correlated subquery for average scores.
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        U.Views AS ProfileViews,
        -- Counts of different badge classes.
        COALESCE(COUNT(DISTINCT B.Id), 0) AS TotalBadges,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        -- Date of the latest badge awarded to the user.
        MAX(B.Date) AS LatestBadgeDate,
        -- Counts for specific post history types, such as edits and post closures/reopens.
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END), 0) AS EditHistoryCount, -- Title, Body, Tags edits
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0) AS PostClosedHistoryCount,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END), 0) AS PostReopenedHistoryCount,
        -- Average length of comments made by the user in post history entries.
        COALESCE(AVG(LENGTH(PH.Comment)) FILTER (WHERE PH.Comment IS NOT NULL AND TRIM(PH.Comment) != ''), 0) AS AvgPostHistoryCommentLength,
        -- Correlated subquery: Calculates the average score of all questions owned by the user,
        -- excluding their single highest-scoring question to assess consistent quality.
        (
            SELECT COALESCE(AVG(SQ.Score), 0)
            FROM Posts AS SQ
            WHERE SQ.OwnerUserId = U.Id
              AND SQ.PostTypeId = 1
              AND SQ.Id NOT IN (
                  SELECT Q_MAX.Id
                  FROM Posts AS Q_MAX
                  WHERE Q_MAX.OwnerUserId = U.Id AND Q_MAX.PostTypeId = 1
                  ORDER BY Q_MAX.Score DESC NULLS LAST
                  LIMIT 1
              )
        ) AS AvgQuestionScoreExcludingBest
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN PostHistory AS PH ON U.Id = PH.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
TopGlobalQuestionTags AS (
    -- CTE to identify the top 3 most frequently used tags globally, which can be used for filtering or analysis.
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 3
)
SELECT
    UPE.UserId,
    COALESCE(UPE.DisplayName, 'Anonymous User') AS UserDisplayName,
    URH.Reputation,
    UPE.TotalPosts,
    UPE.QuestionsCount,
    UPE.AnswersCount,
    URH.GoldBadges,
    URH.SilverBadges,
    URH.BronzeBadges,
    UPE.TotalPostScore,
    UPE.TotalPostViews,
    UPE.TotalCommentsMade,
    URH.ProfileViews,
    -- A composite "Contribution Score" calculated using a weighted sum of various user metrics.
    CAST(
        (UPE.TotalPostScore * 0.5) +
        (UPE.TotalCommentsMade * 0.2) +
        (URH.Reputation * 0.1) +
        (UPE.OwnAnswersAcceptedCount * 5) +
        (URH.GoldBadges * 10 + URH.SilverBadges * 5 + URH.BronzeBadges * 1) +
        (UPE.EditHistoryCount * 0.5) +
        (UPE.UniqueQuestionTags * 0.3)
    AS NUMERIC) AS ContributionScore,
    -- Ratio of questions with accepted answers to total questions asked by the user.
    CASE
        WHEN UPE.QuestionsCount > 0 THEN CAST(UPE.AcceptedAnswersForOwnQuestionsCount AS NUMERIC) / UPE.QuestionsCount
        ELSE 0.0
    END AS QuestionAcceptanceRatio,
    -- Ratio of the user's answers that were accepted by others to their total answers.
    CASE
        WHEN UPE.AnswersCount > 0 THEN CAST(UPE.OwnAnswersAcceptedCount AS NUMERIC) / UPE.AnswersCount
        ELSE 0.0
    END AS OwnAnswerAcceptanceRatio,
    -- Number of days since the user's last post activity.
    EXTRACT(EPOCH FROM (NOW() - UPE.LatestPostActivityDate)) / 3600 / 24 AS DaysSinceLastPostActivity,
    -- Total number of days since the user's account was created.
    EXTRACT(EPOCH FROM (NOW() - URH.UserCreationDate)) / 3600 / 24 AS DaysSinceUserCreation,
    -- Reputation gained per day since account creation.
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - URH.UserCreationDate)) > 0
        THEN URH.Reputation / (EXTRACT(EPOCH FROM (NOW() - URH.UserCreationDate)) / 3600 / 24)
        ELSE 0.0
    END AS ReputationPerDay,
    -- Average question score excluding the best-scoring question (from the correlated subquery).
    URH.AvgQuestionScoreExcludingBest,
    -- Boolean flag indicating if the user has posted questions using any of the top global tags.
    EXISTS (
        SELECT 1
        FROM Posts AS P_Tags
        WHERE P_Tags.OwnerUserId = UPE.UserId
          AND P_Tags.PostTypeId = 1
          AND P_Tags.Tags IS NOT NULL
          AND EXISTS (
              SELECT 1
              FROM regexp_split_to_table(SUBSTRING(P_Tags.Tags FROM 2 FOR LENGTH(P_Tags.Tags) - 2), '><') AS UserTag(tag)
              INNER JOIN TopGlobalQuestionTags AS TGT ON UserTag.tag = TGT.TagName
          )
    ) AS ParticipatesInTopTags,
    -- Boolean flag indicating if the user's 'AboutMe' section contains keywords related to 'sql', 'database', or 'performance' (case-insensitive).
    (U.AboutMe ILIKE '%sql%' OR U.AboutMe ILIKE '%database%' OR U.AboutMe ILIKE '%performance%') AS HasRelevantAboutMeKeywords,
    -- Boolean flag indicating if the user has had a post closed and subsequently reopened, suggesting potential post improvement or review.
    (URH.PostClosedHistoryCount > 0 AND URH.PostReopenedHistoryCount > 0) AS HasClosedAndReopenedPosts,
    -- Rank users based on their calculated Contribution Score in descending order.
    RANK() OVER (ORDER BY
        (
            (UPE.TotalPostScore * 0.5) +
            (UPE.TotalCommentsMade * 0.2) +
            (URH.Reputation * 0.1) +
            (UPE.OwnAnswersAcceptedCount * 5) +
            (URH.GoldBadges * 10 + URH.SilverBadges * 5 + URH.BronzeBadges * 1) +
            (UPE.EditHistoryCount * 0.5) +
            (UPE.UniqueQuestionTags * 0.3)
        ) DESC
    ) AS OverallContributionRank,
    -- Assign users into 10 deciles based on their ReputationPerDay, with the highest rate in decile 1.
    NTILE(10) OVER (ORDER BY
        (
            CASE
                WHEN EXTRACT(EPOCH FROM (NOW() - URH.UserCreationDate)) > 0
                THEN URH.Reputation / (EXTRACT(EPOCH FROM (NOW() - URH.UserCreationDate)) / 3600 / 24)
                ELSE 0.0
            END
        ) DESC
    ) AS ReputationPerDayDecile
FROM Users AS U
INNER JOIN UserPostEngagement AS UPE ON U.Id = UPE.UserId
INNER JOIN UserReputationAndHistory AS URH ON U.Id = URH.UserId
WHERE
    U.Reputation >= 1000 -- Filter for users with a minimum reputation threshold.
    AND UPE.TotalPosts >= 10 -- Require a minimum number of total posts.
    AND UPE.AnswersCount >= 3 -- Require a minimum number of answers.
    AND UPE.AvgPostBodyLength > 100 -- Ensure posts generally have substantial content.
    AND (URH.GoldBadges + URH.SilverBadges) >= 1 -- Users must have at least one Gold or Silver badge.
    AND UPE.LatestPostActivityDate IS NOT NULL -- Exclude users with no recent post activity.
    AND (
        (U.Location IS NOT NULL AND LENGTH(TRIM(U.Location)) > 0 AND U.Location NOT ILIKE '%internet%' AND U.Location NOT ILIKE '%earth%')
        OR
        (U.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(U.WebsiteUrl)) > 0)
    ) -- Filter for users with some identifiable location or website, excluding generic entries.
    AND (NOW() - U.CreationDate) < INTERVAL '5 year' -- Focus on users created within the last 5 years to prioritize recent engagement.
    AND URH.AvgQuestionScoreExcludingBest > 0 -- Questions must have a positive average score, excluding the best one.
ORDER BY OverallContributionRank ASC, DaysSinceLastPostActivity ASC
LIMIT 1000;
