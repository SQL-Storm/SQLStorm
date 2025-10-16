-- {"query": "19014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4110} 

WITH RECURSIVE
    TagParse AS (
        -- CTE 1: Parses the 'Tags' string column into individual tag names for questions.
        -- Uses GENERATE_SERIES to simulate array unnesting for string_to_array, suitable for PostgreSQL.
        SELECT
            P.Id AS PostId,
            TRIM(REPLACE(REPLACE(LOWER(SPLIT_PART(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><', n)), '<', ''), '>', '')) AS TagName,
            n AS TagOrder
        FROM
            Posts P,
            GENERATE_SERIES(1, LENGTH(P.Tags) - LENGTH(REPLACE(P.Tags, '><', '')) / 2 + 1) AS n
        WHERE
            P.Tags IS NOT NULL
            AND P.PostTypeId = 1 -- Only questions for tag parsing
            AND LENGTH(P.Tags) > 2
    ),
    QuestionBase AS (
        -- CTE 2: Gathers core data for questions and calculates initial engagement scores.
        SELECT
            P.Id AS QuestionId,
            P.OwnerUserId,
            COALESCE(U.DisplayName, P.OwnerDisplayName, 'Anonymous Community User') AS OwnerDisplayName,
            U.Reputation,
            U.CreationDate AS UserCreationDate,
            P.CreationDate AS QuestionCreationDate,
            P.LastActivityDate,
            P.Title,
            P.Body,
            P.Score AS QuestionScore,
            P.ViewCount,
            P.AnswerCount,
            P.CommentCount AS QuestionCommentCount,
            P.FavoriteCount,
            P.AcceptedAnswerId,
            P.LastEditDate,
            P.ClosedDate,
            P.CommunityOwnedDate,
            P.Tags,
            -- Complicated Expression: Calculate a weighted engagement score for questions
            (P.Score * 0.75 + P.ViewCount * 0.1 / 100 + P.AnswerCount * 0.15 + COALESCE(P.FavoriteCount, 0) * 0.2) AS CalculatedEngagementScore,
            -- Complicated Expression: Calculate age in days from creation to last activity
            EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 86400 AS AgeInDays
        FROM
            Posts P
        LEFT JOIN
            Users U ON P.OwnerUserId = U.Id
        WHERE
            P.PostTypeId = 1
            AND P.CreationDate >= '2020-01-01' -- Focus on recent active questions
            AND P.Score > 0 -- Only questions with positive scores
    ),
    PostDetailedHistoryAgg AS (
        -- CTE 3: Aggregates detailed history information for each post.
        SELECT
            PH.PostId AS QuestionId,
            -- Window Function: Calculate the time difference in hours to the previous edit of the same type
            (EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate))) / 3600)::numeric AS HoursSinceLastSameTypeEdit,
            MAX(CASE WHEN PHT.Name = 'Post Closed' THEN 1 ELSE 0 END) AS WasClosedOnce,
            MAX(CASE WHEN PHT.Name = 'Post Reopened' THEN 1 ELSE 0 END) AS WasReopenedOnce,
            MAX(CASE WHEN PHT.Name = 'Post Deleted' THEN 1 ELSE 0 END) AS WasDeletedOnce,
            COUNT(DISTINCT CASE WHEN PH.UserId IS NOT NULL AND PH.UserId <> -1 THEN PH.UserId END) AS DistinctHumanEditors,
            COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS TotalEditEvents,
            MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS LastEditHistoryDate,
            MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditHistoryDate
        FROM
            PostHistory PH
        INNER JOIN
            PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
        WHERE
            PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 19, 20) -- Relevant edit/moderation history types
        GROUP BY
            PH.PostId, PH.CreationDate, PH.PostHistoryTypeId -- Grouping for LAG, then aggregating further
    ),
    QuestionVotesAndCommentsAgg AS (
        -- CTE 4: Aggregates votes and distinct commenters for each question.
        SELECT
            Q.QuestionId,
            COUNT(DISTINCT C.UserId) AS DistinctCommenters,
            SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
            SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
            SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyGiven
        FROM
            QuestionBase Q
        LEFT JOIN
            Comments C ON Q.QuestionId = C.PostId
        LEFT JOIN
            Votes V ON Q.QuestionId = V.PostId
        GROUP BY
            Q.QuestionId
    ),
    UserBadgeGoldTagStatus AS (
        -- CTE 5: Identifies users with Gold Tag-Based Badges
        SELECT
            B.UserId,
            B.Name AS BadgeName,
            TRUE AS HasGoldTagBadge
        FROM
            Badges B
        WHERE
            B.Class = 1 AND B.TagBased = TRUE
    ),
    AnswerQuality AS (
        -- CTE 6: Gathers data for answers, potentially for later union or subquery use.
        SELECT
            A.Id AS AnswerId,
            A.ParentId AS QuestionId,
            A.OwnerUserId AS AnswerOwnerUserId,
            COALESCE(U.DisplayName, A.OwnerDisplayName, 'Anonymous Answerer') AS AnswerOwnerDisplayName,
            A.Score AS AnswerScore,
            A.CreationDate AS AnswerCreationDate,
            A.Body AS AnswerBody,
            (A.Score * 0.9 + A.CommentCount * 0.1) AS AnswerQualityScore
        FROM
            Posts A
        LEFT JOIN Users U ON A.OwnerUserId = U.Id
        WHERE
            A.PostTypeId = 2
    )
SELECT
    QB.QuestionId AS PostIdentifier,
    'Question' AS PostType,
    QB.Title AS PostTitleSnippet,
    QB.OwnerDisplayName AS OwnerIdentifier,
    QB.Reputation AS OwnerReputation,
    QB.QuestionCreationDate AS CreationTimestamp,
    QB.LastActivityDate AS LastActivityTimestamp,
    QB.QuestionScore AS TotalScore,
    QB.ViewCount,
    QB.AnswerCount AS RelatedPostCount,
    QVC.TotalUpVotes,
    QVC.TotalDownVotes,
    QVC.TotalBountyGiven,
    QB.FavoriteCount,
    PDHA.DistinctHumanEditors,
    ROUND(QB.CalculatedEngagementScore, 2) AS FinalEngagementScore,
    -- Correlated Subquery: Check if the question's owner has a gold tag badge for any of the question's specific tags.
    (
        SELECT
            COUNT(DISTINCT UBGTS.BadgeName)
        FROM
            UserBadgeGoldTagStatus UBGTS
        INNER JOIN
            TagParse TP ON TP.PostId = QB.QuestionId
        WHERE
            UBGTS.UserId = QB.OwnerUserId
            AND UBGTS.BadgeName = TP.TagName
    ) AS OwnerGoldTagBadgesOnPostTags,
    -- Window Function: Rank questions by engagement score within their creation year and reputation band.
    DENSE_RANK() OVER (
        PARTITION BY EXTRACT(YEAR FROM QB.QuestionCreationDate), FLOOR(QB.Reputation / 10000)
        ORDER BY QB.CalculatedEngagementScore DESC, QB.ViewCount DESC
    ) AS RankByEngagementInYearAndRepBand,
    -- Complicated Predicate/Calculation: Identify "hot" questions that were closed but then reopened
    CASE
        WHEN PDHA.WasClosedOnce = 1 AND PDHA.WasReopenedOnce = 1 THEN 'Closed_Reopened_Hot'
        WHEN QB.ClosedDate IS NOT NULL AND QB.CommunityOwnedDate IS NULL THEN 'Closed_But_Not_Community'
        WHEN QB.AgeInDays > 365 AND QB.ViewCount > 100000 THEN 'Evergreen_HighView'
        ELSE 'Standard'
    END AS PostStatusClassification,
    -- String Expression: Extract and normalize the first tag, or identify "multi-tag" if many.
    COALESCE(
        (SELECT TP.TagName FROM TagParse TP WHERE TP.PostId = QB.QuestionId AND TP.TagOrder = 1 LIMIT 1),
        'untagged'
    ) AS PrimaryTag,
    -- NULL Logic: Ratio of upvotes to downvotes, handling division by zero explicitly.
    CASE
        WHEN QVC.TotalDownVotes > 0 THEN ROUND(QVC.TotalUpVotes::numeric / QVC.TotalDownVotes, 2)
        WHEN QVC.TotalUpVotes = 0 AND QVC.TotalDownVotes = 0 THEN 0.00
        ELSE 9999.99 -- Effectively infinite for no downvotes but some upvotes
    END AS UpvoteToDownvoteRatio,
    -- Nested Subquery: Average score of all answers to this question, if any.
    (
        SELECT
            AVG(AQ.AnswerScore)
        FROM
            AnswerQuality AQ
        WHERE
            AQ.QuestionId = QB.QuestionId
    ) AS AvgAnswerScore,
    -- Further detailed historical analysis: time to first edit
    (EXTRACT(EPOCH FROM (PDHA.FirstEditHistoryDate - QB.QuestionCreationDate)) / 3600)::numeric AS HoursToFirstEdit,
    -- Complicated String Expression: Check for specific keywords in the title and body.
    CASE
        WHEN QB.Title ILIKE '%performance%' OR QB.Body ILIKE '%optimiza%query%' THEN 'Performance_Related'
        WHEN QB.Title ILIKE '%security%' OR QB.Body ILIKE '%vulnerab%' THEN 'Security_Related'
        ELSE 'General_Topic'
    END AS ContentTopic,
    -- A complex conditional calculation based on multiple factors.
    (QB.Reputation * 0.1 + QB.CalculatedEngagementScore * 0.5 + QVC.TotalUpVotes * 0.05 - QVC.TotalDownVotes * 0.1)::numeric AS UserPostInfluenceMetric
FROM
    QuestionBase QB
LEFT JOIN
    QuestionVotesAndCommentsAgg QVC ON QB.QuestionId = QVC.QuestionId
LEFT JOIN
    PostDetailedHistoryAgg PDHA ON QB.QuestionId = PDHA.QuestionId
WHERE
    QB.ViewCount > 1000
    AND QB.AnswerCount > 0
    AND QB.Reputation > 1000
    AND QB.AgeInDays >= 90 -- Ensure question has some age
    AND (PDHA.DistinctHumanEditors > 1 OR QB.CommentCount > 5) -- More than one editor or significant discussion
    AND (
        QB.Tags ILIKE '%<sql>%' OR QB.Tags ILIKE '%<database>%' OR QB.Tags ILIKE '%<performance>%'
    ) -- Filter for specific tags that are usually complex
GROUP BY
    QB.QuestionId, QB.Title, QB.OwnerDisplayName, QB.Reputation, QB.QuestionCreationDate, QB.LastActivityDate,
    QB.QuestionScore, QB.ViewCount, QB.AnswerCount, QVC.TotalUpVotes, QVC.TotalDownVotes, QVC.TotalBountyGiven,
    QB.FavoriteCount, PDHA.DistinctHumanEditors, QB.CalculatedEngagementScore, QB.ClosedDate, QB.CommunityOwnedDate,
    QB.AgeInDays, PDHA.WasClosedOnce, PDHA.WasReopenedOnce, PDHA.FirstEditHistoryDate, QB.Body, QB.Tags
HAVING
    COUNT(DISTINCT PDHA.TotalEditEvents) >= 1 -- Ensure at least one edit history event for complex analysis
    AND QVC.TotalUpVotes > QVC.TotalDownVotes * 2 -- Significantly more upvotes than downvotes
ORDER BY
    UserPostInfluenceMetric DESC, FinalEngagementScore DESC
LIMIT 500 -- Limit for the first part of the UNION ALL

UNION ALL

-- Set Operator (UNION ALL): Second part of the query, focusing on highly-rated answers to active questions
SELECT
    AQ.AnswerId AS PostIdentifier,
    'Answer' AS PostType,
    LEFT(AQ.AnswerBody, 250) AS PostTitleSnippet, -- Use body snippet for answers
    AQ.AnswerOwnerDisplayName AS OwnerIdentifier,
    U.Reputation AS OwnerReputation,
    AQ.AnswerCreationDate AS CreationTimestamp,
    A.LastActivityDate AS LastActivityTimestamp,
    AQ.AnswerScore AS TotalScore,
    NULL AS ViewCount, -- Not applicable in the same way for answers
    NULL AS RelatedPostCount, -- Not applicable for answers
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    NULL AS TotalBountyGiven, -- Bounties are on questions
    NULL AS FavoriteCount, -- Favorites are on questions
    COUNT(DISTINCT C.UserId) AS DistinctHumanEditors, -- Counting distinct commenters as a form of "engagement" for answers
    ROUND(AQ.AnswerQualityScore, 2) AS FinalEngagementScore,
    -- Correlated Subquery: Check if the answer's owner has *any* gold badge (not tag-specific here for variation)
    (
        SELECT
            COUNT(DISTINCT B.Id)
        FROM
            Badges B
        WHERE
            B.UserId = AQ.AnswerOwnerUserId
            AND B.Class = 1
    ) AS OwnerGoldBadges,
    -- Window Function: Rank answers by quality score within their creation year and parent question's view count band.
    DENSE_RANK() OVER (
        PARTITION BY EXTRACT(YEAR FROM AQ.AnswerCreationDate), FLOOR(QB_Parent.ViewCount / 10000)
        ORDER BY AQ.AnswerQualityScore DESC, AQ.AnswerScore DESC
    ) AS RankByQualityInYearAndViewBand,
    'Answer_Classification' AS PostStatusClassification, -- Simplified for answers
    COALESCE(
        (SELECT TP.TagName FROM TagParse TP WHERE TP.PostId = QB_Parent.QuestionId AND TP.TagOrder = 1 LIMIT 1),
        'untagged_parent'
    ) AS PrimaryTag,
    CASE
        WHEN SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) > 0 THEN ROUND(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END)::numeric / SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 2)
        WHEN SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) = 0 AND SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) = 0 THEN 0.00
        ELSE 9999.99
    END AS UpvoteToDownvoteRatio,
    NULL AS AvgAnswerScore, -- Not applicable to answers themselves
    (EXTRACT(EPOCH FROM (A.CreationDate - QB_Parent.CreationDate)) / 86400)::numeric AS DaysToAnswerQuestion, -- Time from question to answer
    CASE
        WHEN AQ.AnswerBody ILIKE '%example%' OR AQ.AnswerBody ILIKE '%code%' THEN 'Code_Example_Present'
        WHEN AQ.AnswerBody ILIKE '%solution%' THEN 'Solution_Oriented'
        ELSE 'Descriptive'
    END AS ContentTopic,
    (U.Reputation * 0.05 + AQ.AnswerQualityScore * 0.8)::numeric AS AnswerInfluenceMetric
FROM
    AnswerQuality AQ
INNER JOIN
    Posts A ON AQ.AnswerId = A.Id -- To get last activity date for answer
LEFT JOIN
    Users U ON AQ.AnswerOwnerUserId = U.Id
INNER JOIN
    QuestionBase QB_Parent ON AQ.QuestionId = QB_Parent.QuestionId -- Ensure parent question is from our base analysis set
LEFT JOIN
    Votes V ON AQ.AnswerId = V.PostId
LEFT JOIN
    Comments C ON AQ.AnswerId = C.PostId
WHERE
    AQ.AnswerScore > 20 -- High-scoring answers
    AND QB_Parent.ViewCount > 5000 -- To highly viewed questions
    AND QB_Parent.QuestionScore > 10
    AND AQ.AnswerCreationDate >= '2020-01-01' -- Recent answers
GROUP BY
    AQ.AnswerId, AQ.AnswerBody, AQ.AnswerOwnerDisplayName, U.Reputation, AQ.AnswerCreationDate, A.LastActivityDate,
    AQ.AnswerScore, AQ.AnswerQualityScore, AQ.AnswerOwnerUserId, QB_Parent.ViewCount, QB_Parent.QuestionId, QB_Parent.CreationDate
HAVING
    COUNT(DISTINCT C.UserId) > 1 OR SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) > 10 -- Engaged answers
ORDER BY
    AnswerInfluenceMetric DESC, FinalEngagementScore DESC
LIMIT 500;
